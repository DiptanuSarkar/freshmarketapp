import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/keys.ts";
import { sendFcmMessage } from "../_shared/fcm.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const serviceClient = createServiceClient();
    let body: { job_id?: string; limit?: number } = {};
    try {
      body = await req.json();
    } catch (_) {}

    const limit = body.limit || 20;

    // 1. Claim pending jobs atomically using FOR UPDATE SKIP LOCKED
    const { data: claimedJobs, error: claimError } = await serviceClient.rpc(
      "rpc_claim_pending_push_jobs",
      { p_limit: limit }
    );

    if (claimError) {
      return new Response(
        JSON.stringify({ success: false, error: claimError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const jobs = claimedJobs || [];
    const results: Array<{
      job_id: string;
      user_id: string;
      tokens_count: number;
      sent_count: number;
      failed_count: number;
      status: string;
    }> = [];

    for (const job of jobs) {
      // 2. Fetch active FCM tokens for this customer
      const { data: tokens, error: tokenError } = await serviceClient
        .from("fcm_tokens")
        .select("id, token, device_type")
        .eq("user_id", job.user_id)
        .eq("is_active", true);

      if (tokenError || !tokens || tokens.length === 0) {
        // No active tokens registered: mark job as sent (in-app history remains authoritative)
        await serviceClient
          .from("notification_push_jobs")
          .update({
            status: "sent",
            sent_at: new Date().toISOString(),
            last_error_code: "NO_ACTIVE_TOKENS",
            last_error_message: "Customer has no active registered FCM device tokens.",
            updated_at: new Date().toISOString(),
          })
          .eq("id", job.job_id);

        results.push({
          job_id: job.job_id,
          user_id: job.user_id,
          tokens_count: 0,
          sent_count: 0,
          failed_count: 0,
          status: "sent_no_tokens",
        });
        continue;
      }

      let sentCount = 0;
      let failedCount = 0;
      let hasTransientError = false;
      let lastErrorMessage = "";

      // Channel ID mapping based on type
      let channelId = "freshmarket_general";
      const typeStr = (job.notif_type || "").toLowerCase();
      if (typeStr.startsWith("order_")) channelId = "freshmarket_orders";
      else if (typeStr.startsWith("payment_")) channelId = "freshmarket_payments";
      else if (typeStr.startsWith("refund_") || typeStr.startsWith("wallet_")) channelId = "freshmarket_refunds";

      const payloadData = {
        ...(typeof job.data === "object" && job.data !== null ? job.data : {}),
        type: job.notif_type,
        notification_id: job.notification_id,
      };

      // 3. Dispatch to each active device token
      for (const t of tokens) {
        const sendResult = await sendFcmMessage({
          token: t.token,
          title: job.title,
          body: job.body,
          data: payloadData,
          channelId,
        });

        if (sendResult.status === "success") {
          sentCount++;
          await serviceClient.from("notification_push_deliveries").upsert(
            {
              notification_id: job.notification_id,
              job_id: job.job_id,
              fcm_token_id: t.id,
              status: "sent",
              provider_message_id: sendResult.messageId,
              attempts: 1,
              sent_at: new Date().toISOString(),
            },
            { onConflict: "notification_id,fcm_token_id" }
          );
        } else if (sendResult.status === "invalid_token") {
          // Deactivate permanent invalid / unregistered token immediately
          await serviceClient
            .from("fcm_tokens")
            .update({ is_active: false, updated_at: new Date().toISOString() })
            .eq("id", t.id);

          await serviceClient.from("notification_push_deliveries").upsert(
            {
              notification_id: job.notification_id,
              job_id: job.job_id,
              fcm_token_id: t.id,
              status: "invalid_token",
              last_error: sendResult.error,
              attempts: 1,
            },
            { onConflict: "notification_id,fcm_token_id" }
          );
        } else if (sendResult.status === "transient_error") {
          failedCount++;
          hasTransientError = true;
          lastErrorMessage = sendResult.error;

          await serviceClient.from("notification_push_deliveries").upsert(
            {
              notification_id: job.notification_id,
              job_id: job.job_id,
              fcm_token_id: t.id,
              status: "failed",
              last_error: sendResult.error,
              attempts: 1,
            },
            { onConflict: "notification_id,fcm_token_id" }
          );
        } else {
          // Permanent failure
          failedCount++;
          lastErrorMessage = sendResult.error;

          await serviceClient.from("notification_push_deliveries").upsert(
            {
              notification_id: job.notification_id,
              job_id: job.job_id,
              fcm_token_id: t.id,
              status: "failed",
              last_error: sendResult.error,
              attempts: 1,
            },
            { onConflict: "notification_id,fcm_token_id" }
          );
        }
      }

      // 4. Update parent job status based on delivery outcomes
      const newAttemptCount = (job.attempt_count || 0) + 1;

      if (sentCount > 0 || (!hasTransientError && failedCount === 0)) {
        await serviceClient
          .from("notification_push_jobs")
          .update({
            status: "sent",
            sent_at: new Date().toISOString(),
            attempt_count: newAttemptCount,
            updated_at: new Date().toISOString(),
          })
          .eq("id", job.job_id);

        results.push({
          job_id: job.job_id,
          user_id: job.user_id,
          tokens_count: tokens.length,
          sent_count: sentCount,
          failed_count: failedCount,
          status: "sent",
        });
      } else if (hasTransientError && newAttemptCount < 5) {
        // Exponential backoff: next attempt in 30s * attemptCount^2
        const delaySeconds = Math.min(30 * newAttemptCount * newAttemptCount, 900);
        const nextAttemptAt = new Date(Date.now() + delaySeconds * 1000).toISOString();

        await serviceClient
          .from("notification_push_jobs")
          .update({
            status: "pending",
            attempt_count: newAttemptCount,
            next_attempt_at: nextAttemptAt,
            last_error_code: "TRANSIENT_FCM_ERROR",
            last_error_message: lastErrorMessage,
            updated_at: new Date().toISOString(),
          })
          .eq("id", job.job_id);

        results.push({
          job_id: job.job_id,
          user_id: job.user_id,
          tokens_count: tokens.length,
          sent_count: sentCount,
          failed_count: failedCount,
          status: "retry_pending",
        });
      } else {
        // Max attempts reached or permanent failure
        await serviceClient
          .from("notification_push_jobs")
          .update({
            status: "failed",
            attempt_count: newAttemptCount,
            last_error_code: "MAX_ATTEMPTS_EXCEEDED",
            last_error_message: lastErrorMessage || "Delivery failed permanently",
            updated_at: new Date().toISOString(),
          })
          .eq("id", job.job_id);

        results.push({
          job_id: job.job_id,
          user_id: job.user_id,
          tokens_count: tokens.length,
          sent_count: sentCount,
          failed_count: failedCount,
          status: "failed",
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        claimed_count: jobs.length,
        results,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
