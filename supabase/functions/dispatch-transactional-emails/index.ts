import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/keys.ts";
import { renderEmailTemplate } from "../_shared/emails.ts";

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

    const limit = body.limit || 10;

    // 1. Claim pending jobs atomically using FOR UPDATE SKIP LOCKED
    const { data: claimedJobs, error: claimError } = await serviceClient.rpc(
      "rpc_claim_pending_email_jobs",
      { p_limit: limit }
    );

    if (claimError) {
      console.error("rpc_claim_pending_email_jobs failed:", claimError);
      return new Response(
        JSON.stringify({ success: false, error: claimError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const jobs = claimedJobs || [];
    const results: Array<{
      job_id: string;
      recipient_email: string;
      status: string;
      provider_message_id?: string;
      error?: string;
    }> = [];

    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const fromAddress = Deno.env.get("EMAIL_FROM_ADDRESS") || "onboarding@resend.dev";
    const fromName = Deno.env.get("EMAIL_FROM_NAME") || "FreshMarket";

    for (const job of jobs) {
      const rendered = renderEmailTemplate(job.template_key, job.payload || {});

      if (!resendApiKey) {
        // Development / Mock fallback when RESEND_API_KEY is not yet configured
        const mockMsgId = `mock_resend_${crypto.randomUUID()}`;
        console.log(`[MOCK EMAIL DISPATCH] To: ${job.recipient_email} | Subject: "${rendered.subject}" | MessageId: ${mockMsgId}`);

        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "sent",
          p_provider_msg_id: mockMsgId,
          p_error_code: null,
          p_error_message: null,
          p_is_transient: false,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "sent_mock",
          provider_message_id: mockMsgId,
        });
        continue;
      }

      // Live Resend HTTPS API dispatch
      try {
        const resendRes = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${resendApiKey}`,
          },
          body: JSON.stringify({
            from: `${fromName} <${fromAddress}>`,
            to: [job.recipient_email],
            subject: rendered.subject,
            html: rendered.html,
            text: rendered.text,
          }),
        });

        if (resendRes.ok) {
          const resData = await resendRes.json();
          const providerId = resData.id || `resend_${crypto.randomUUID()}`;

          await serviceClient.rpc("rpc_record_email_job_result", {
            p_job_id: job.job_id,
            p_status: "sent",
            p_provider_msg_id: providerId,
            p_error_code: null,
            p_error_message: null,
            p_is_transient: false,
          });

          results.push({
            job_id: job.job_id,
            recipient_email: job.recipient_email,
            status: "sent",
            provider_message_id: providerId,
          });
        } else {
          const status = resendRes.status;
          const errBody = await resendRes.text();
          const isTransient = status >= 500 || status === 429;

          console.warn(`Resend API dispatch failed for job ${job.job_id} (${status}):`, errBody);

          await serviceClient.rpc("rpc_record_email_job_result", {
            p_job_id: job.job_id,
            p_status: "failed",
            p_provider_msg_id: null,
            p_error_code: `HTTP_${status}`,
            p_error_message: errBody.slice(0, 500),
            p_is_transient: isTransient,
          });

          results.push({
            job_id: job.job_id,
            recipient_email: job.recipient_email,
            status: isTransient ? "pending_retry" : "failed_permanent",
            error: errBody.slice(0, 200),
          });
        }
      } catch (sendErr: unknown) {
        const errMsg = sendErr instanceof Error ? sendErr.message : "Network error";
        console.error(`Network error during email dispatch for job ${job.job_id}:`, errMsg);

        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_msg_id: null,
          p_error_code: "NETWORK_ERROR",
          p_error_message: errMsg,
          p_is_transient: true,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "pending_retry",
          error: errMsg,
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed_count: jobs.length,
        results,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : "Unknown error";
    console.error("dispatch-transactional-emails fatal exception:", errorMsg);
    return new Response(
      JSON.stringify({ success: false, error: errorMsg }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
