import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import nodemailer from "npm:nodemailer@10.3.1";
import { corsHeaders } from "../_shared/cors.ts";
import { createServiceClient } from "../_shared/keys.ts";
import { renderEmailTemplate } from "../_shared/emails.ts";

export interface SmtpConfig {
  host: string;
  port: number;
  secure: boolean;
  auth: {
    user: string;
    pass: string;
  };
  fromEmail: string;
  fromName: string;
  replyTo?: string;
}

export interface FailureClassification {
  code: string;
  message: string;
  isTransient: boolean;
}

export function isValidEmail(email: string): boolean {
  if (!email || typeof email !== "string") return false;
  const trimmed = email.trim();
  if (trimmed.length > 254) return false;
  const emailRegex =
    /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;
  return emailRegex.test(trimmed);
}

export function getSmtpConfig(): { config: SmtpConfig | null; error?: string } {
  const host = Deno.env.get("SMTP_HOST");
  const portStr = Deno.env.get("SMTP_PORT");
  const secureStr = Deno.env.get("SMTP_SECURE");
  const user = Deno.env.get("SMTP_USER");
  const pass = Deno.env.get("SMTP_PASS");
  const fromEmail = Deno.env.get("SMTP_FROM_EMAIL");
  const fromName = Deno.env.get("SMTP_FROM_NAME") || "FreshMarket";
  const replyTo = Deno.env.get("SMTP_REPLY_TO");

  if (!host || !user || !pass || !fromEmail) {
    return {
      config: null,
      error: "Missing required SMTP credentials (SMTP_HOST, SMTP_USER, SMTP_PASS, SMTP_FROM_EMAIL)",
    };
  }

  // Supabase rule: Hosted Edge Functions MUST use port 465 with secure: true
  const port = portStr ? parseInt(portStr, 10) : 465;
  const secure = secureStr !== undefined ? secureStr === "true" || secureStr === "1" : true;

  return {
    config: {
      host,
      port,
      secure,
      auth: { user, pass },
      fromEmail,
      fromName,
      replyTo: replyTo || undefined,
    },
  };
}

export function createSmtpTransporter(config: SmtpConfig) {
  return nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.secure, // true for port 465 (TLS from connection start)
    auth: {
      user: config.auth.user,
      pass: config.auth.pass,
    },
    connectionTimeout: 10000, // 10s serverless timeout
    greetingTimeout: 10000,
    socketTimeout: 15000,
    tls: {
      minVersion: "TLSv1.2",
      rejectUnauthorized: true,
    },
  });
}

export function classifySmtpError(err: unknown): FailureClassification {
  if (!err) {
    return { code: "UNKNOWN_ERROR", message: "Unknown error occurred", isTransient: false };
  }

  const errObj = err as Record<string, unknown>;
  const rawCode = String(errObj.code || "");
  const responseCode = typeof errObj.responseCode === "number" ? errObj.responseCode : 0;
  const rawMessage = String(errObj.message || "SMTP error");

  // Sanitize message so no password or auth configuration is logged
  const sanitizedMessage = rawMessage
    .replace(/(password|pass|auth|key|token)[=:\s]+[^\s,;]+/gi, "$1=[REDACTED]")
    .slice(0, 500);

  // Authentication error (EAUTH or response 535) -> Permanent
  if (
    rawCode === "EAUTH" ||
    responseCode === 535 ||
    /auth/i.test(rawCode) ||
    /authentication failed/i.test(rawMessage)
  ) {
    return {
      code: "EAUTH",
      message: sanitizedMessage || "SMTP authentication failed",
      isTransient: false,
    };
  }

  // Recipient / envelope rejected (EENVELOPE or response 550..554) -> Permanent
  if (rawCode === "EENVELOPE" || (responseCode >= 550 && responseCode <= 554)) {
    return {
      code: rawCode || `SMTP_${responseCode}`,
      message: sanitizedMessage || "Recipient address rejected or invalid envelope",
      isTransient: false,
    };
  }

  // General 5xx SMTP errors -> Permanent
  if (responseCode >= 500 && responseCode < 600) {
    return {
      code: `SMTP_${responseCode}`,
      message: sanitizedMessage,
      isTransient: false,
    };
  }

  // Connection / Socket / Timeout errors -> Retryable
  if (
    rawCode === "ECONNECTION" ||
    rawCode === "ETIMEDOUT" ||
    rawCode === "ESOCKET" ||
    rawCode === "ECONNRESET" ||
    rawCode === "ECONNREFUSED" ||
    rawCode === "EHOSTUNREACH" ||
    /timeout/i.test(rawMessage) ||
    /socket/i.test(rawMessage)
  ) {
    return {
      code: rawCode || "ETIMEDOUT",
      message: sanitizedMessage,
      isTransient: true,
    };
  }

  // SMTP 4xx temporary errors -> Retryable
  if (responseCode >= 400 && responseCode < 500) {
    return {
      code: `SMTP_${responseCode}`,
      message: sanitizedMessage,
      isTransient: true,
    };
  }

  // EMESSAGE formatting errors -> Permanent
  if (rawCode === "EMESSAGE") {
    return {
      code: "EMESSAGE",
      message: sanitizedMessage,
      isTransient: false,
    };
  }

  // Default network / unexpected errors -> Retryable
  return {
    code: rawCode || "SMTP_DISPATCH_ERROR",
    message: sanitizedMessage,
    isTransient: true,
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const serviceClient = createServiceClient();
    let body: {
      action?: string;
      job_id?: string;
      limit?: number;
      recipient_email?: string;
      mock_transport?: {
        simulate: "success" | "eauth" | "timeout" | "envelope" | "server_500";
      };
    } = {};

    try {
      body = await req.json();
    } catch (_) {}

    // -------------------------------------------------------------------------
    // ACTION: verify_connection (Direct diagnostic verification of SMTP TLS port 465)
    // -------------------------------------------------------------------------
    if (body.action === "verify_connection") {
      const { config, error } = getSmtpConfig();
      if (!config) {
        return new Response(
          JSON.stringify({ success: false, error: error || "SMTP credentials missing" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      try {
        const transporter = createSmtpTransporter(config);
        await transporter.verify();
        return new Response(
          JSON.stringify({
            success: true,
            verified: true,
            transport: "nodemailer_smtp_tls",
            host: config.host,
            port: config.port,
            secure: config.secure,
            from: `"${config.fromName}" <${config.fromEmail}>`,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      } catch (verifyErr) {
        const classified = classifySmtpError(verifyErr);
        console.error("SMTP verify_connection failed:", classified.code, classified.message);
        return new Response(
          JSON.stringify({
            success: false,
            verified: false,
            error_code: classified.code,
            error_message: classified.message,
            is_transient: classified.isTransient,
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // -------------------------------------------------------------------------
    // ACTION: send_test_email (Direct transactional email test)
    // -------------------------------------------------------------------------
    if (body.action === "send_test_email") {
      const targetEmail = body.recipient_email;
      if (!targetEmail || !isValidEmail(targetEmail)) {
        return new Response(
          JSON.stringify({ success: false, error: "Invalid recipient_email address" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { config, error } = getSmtpConfig();
      if (!config) {
        return new Response(
          JSON.stringify({ success: false, error: error || "SMTP credentials missing" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const rendered = renderEmailTemplate("order_confirmed", {
        order_number: "FM-SMTP-VERIFY",
        total: "199.00",
        payment_method: "COD",
      });

      try {
        const transporter = createSmtpTransporter(config);
        const info = await transporter.sendMail({
          from: `"${config.fromName}" <${config.fromEmail}>`,
          to: targetEmail,
          replyTo: config.replyTo,
          subject: rendered.subject,
          html: rendered.html,
          text: rendered.text,
        });

        return new Response(
          JSON.stringify({
            success: true,
            status: "sent",
            messageId: info.messageId,
            accepted: info.accepted,
            transport: "nodemailer_smtp_tls",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      } catch (sendErr) {
        const classified = classifySmtpError(sendErr);
        console.error("SMTP send_test_email failed:", classified.code, classified.message);
        return new Response(
          JSON.stringify({
            success: false,
            error_code: classified.code,
            error_message: classified.message,
            is_transient: classified.isTransient,
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // -------------------------------------------------------------------------
    // ACTION: query_recent_jobs (diagnostic inspection for verification)
    // -------------------------------------------------------------------------
    if (body.action === "query_recent_jobs") {
      const { data, error } = await serviceClient
        .from("transactional_email_jobs")
        .select("id, event_key, event_type, recipient_email, template_key, status, attempt_count, provider_message_id, last_error_code, last_error_message, created_at, sent_at")
        .order("created_at", { ascending: false })
        .limit(body.limit || 10);

      return new Response(
        JSON.stringify({ success: !error, jobs: data, error: error?.message }),
        { status: error ? 500 : 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------------------
    // ACTION: test_outbox_flow (Phase 15 end-to-end server outbox test)
    // -------------------------------------------------------------------------
    if (body.action === "test_outbox_flow") {
      const targetEmail = body.recipient_email || "freshmarkets.com@gmail.com";
      if (!isValidEmail(targetEmail)) {
        return new Response(
          JSON.stringify({ success: false, error: "Invalid recipient_email" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const eventKey = `test_outbox_${Date.now()}`;
      const { data: enqueueData, error: enqueueErr } = await serviceClient.rpc(
        "rpc_enqueue_transactional_email",
        {
          p_user_id: null,
          p_event_key: eventKey,
          p_event_type: "order_confirmed",
          p_recipient_email: targetEmail,
          p_template_key: "order_confirmed",
          p_payload: {
            order_number: "FM-SMTP-DEV-TEST",
            total: "249.00",
            payment_method: "COD",
          },
        }
      );

      if (enqueueErr) {
        return new Response(
          JSON.stringify({ success: false, step: "enqueue", error: enqueueErr.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const jobId = enqueueData?.job_id;

      const { config, error: cfgErr } = getSmtpConfig();
      if (!config) {
        return new Response(
          JSON.stringify({ success: false, step: "config", error: cfgErr }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const transporter = createSmtpTransporter(config);
      const rendered = renderEmailTemplate("order_confirmed", {
        order_number: "FM-SMTP-DEV-TEST",
        total: "249.00",
        payment_method: "COD",
      });

      const info = await transporter.sendMail({
        from: `"${config.fromName}" <${config.fromEmail}>`,
        to: targetEmail,
        replyTo: config.replyTo,
        subject: rendered.subject,
        html: rendered.html,
        text: rendered.text,
      });

      await serviceClient.rpc("rpc_record_email_job_result", {
        p_job_id: jobId,
        p_status: "sent",
        p_provider_msg_id: info.messageId,
        p_error_code: null,
        p_error_message: null,
        p_is_transient: false,
      });

      const { data: jobRow } = await serviceClient
        .from("transactional_email_jobs")
        .select("*")
        .eq("id", jobId)
        .single();

      return new Response(
        JSON.stringify({
          success: true,
          job_created: true,
          smtp_accepted: true,
          message_id_stored: Boolean(jobRow?.provider_message_id),
          job: jobRow,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // -------------------------------------------------------------------------
    // STANDARD BATCH OUTBOX DISPATCH
    // -------------------------------------------------------------------------
    const limit = body.limit || 10;

    // Claim pending jobs atomically using FOR UPDATE SKIP LOCKED
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

    // Lazy initialization of real SMTP transporter if needed
    let smtpConfig: SmtpConfig | null = null;
    let configError: string | undefined = undefined;
    let realTransporter: ReturnType<typeof createSmtpTransporter> | null = null;

    if (!body.mock_transport) {
      const cfg = getSmtpConfig();
      smtpConfig = cfg.config;
      configError = cfg.error;
      if (smtpConfig) {
        realTransporter = createSmtpTransporter(smtpConfig);
      }
    }

    for (const job of jobs) {
      // 1. Recipient validation
      if (!isValidEmail(job.recipient_email)) {
        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_msg_id: null,
          p_error_code: "INVALID_RECIPIENT",
          p_error_message: "Recipient email format is missing or invalid",
          p_is_transient: false,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "failed_permanent",
          error: "INVALID_RECIPIENT",
        });
        continue;
      }

      // 2. Render Template
      const rendered = renderEmailTemplate(job.template_key, job.payload || {});
      if (!rendered.subject || !rendered.html) {
        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_msg_id: null,
          p_error_code: "INVALID_TEMPLATE",
          p_error_message: "Email template rendering produced empty subject or body",
          p_is_transient: false,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "failed_permanent",
          error: "INVALID_TEMPLATE",
        });
        continue;
      }

      // 3. Mock transport execution for automated test suites
      if (body.mock_transport) {
        const sim = body.mock_transport.simulate;
        if (sim === "success") {
          const mockMsgId = `<fm_mock_${crypto.randomUUID()}@freshmarket.in>`;
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
            status: "sent",
            provider_message_id: mockMsgId,
          });
          continue;
        } else if (sim === "eauth") {
          const err = Object.assign(new Error("535 5.7.8 Username and Password not accepted"), {
            code: "EAUTH",
            responseCode: 535,
          });
          const classified = classifySmtpError(err);
          await serviceClient.rpc("rpc_record_email_job_result", {
            p_job_id: job.job_id,
            p_status: "failed",
            p_provider_msg_id: null,
            p_error_code: classified.code,
            p_error_message: classified.message,
            p_is_transient: classified.isTransient,
          });

          results.push({
            job_id: job.job_id,
            recipient_email: job.recipient_email,
            status: "failed_permanent",
            error: classified.message,
          });
          continue;
        } else if (sim === "timeout") {
          const err = Object.assign(new Error("Connection timed out after 10000ms"), {
            code: "ETIMEDOUT",
          });
          const classified = classifySmtpError(err);
          await serviceClient.rpc("rpc_record_email_job_result", {
            p_job_id: job.job_id,
            p_status: "failed",
            p_provider_msg_id: null,
            p_error_code: classified.code,
            p_error_message: classified.message,
            p_is_transient: classified.isTransient,
          });

          results.push({
            job_id: job.job_id,
            recipient_email: job.recipient_email,
            status: "pending_retry",
            error: classified.message,
          });
          continue;
        } else if (sim === "envelope") {
          const err = Object.assign(new Error("550 5.1.1 User unknown"), {
            code: "EENVELOPE",
            responseCode: 550,
          });
          const classified = classifySmtpError(err);
          await serviceClient.rpc("rpc_record_email_job_result", {
            p_job_id: job.job_id,
            p_status: "failed",
            p_provider_msg_id: null,
            p_error_code: classified.code,
            p_error_message: classified.message,
            p_is_transient: classified.isTransient,
          });

          results.push({
            job_id: job.job_id,
            recipient_email: job.recipient_email,
            status: "failed_permanent",
            error: classified.message,
          });
          continue;
        }
      }

      // 4. Real Nodemailer SMTP Dispatch
      if (!smtpConfig || !realTransporter) {
        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_msg_id: null,
          p_error_code: "SMTP_CONFIG_ERROR",
          p_error_message: configError || "SMTP credentials are not configured",
          p_is_transient: false,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "failed_permanent",
          error: "SMTP_CONFIG_ERROR",
        });
        continue;
      }

      try {
        const info = await realTransporter.sendMail({
          from: `"${smtpConfig.fromName}" <${smtpConfig.fromEmail}>`,
          to: job.recipient_email,
          replyTo: smtpConfig.replyTo,
          subject: rendered.subject,
          html: rendered.html,
          text: rendered.text,
        });

        const providerMsgId = info.messageId || `<smtp_${crypto.randomUUID()}@freshmarket.in>`;

        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "sent",
          p_provider_msg_id: providerMsgId,
          p_error_code: null,
          p_error_message: null,
          p_is_transient: false,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: "sent",
          provider_message_id: providerMsgId,
        });
      } catch (sendErr: unknown) {
        const classified = classifySmtpError(sendErr);
        console.warn(`SMTP delivery error for job ${job.job_id}:`, classified.code, classified.message);

        await serviceClient.rpc("rpc_record_email_job_result", {
          p_job_id: job.job_id,
          p_status: "failed",
          p_provider_msg_id: null,
          p_error_code: classified.code,
          p_error_message: classified.message,
          p_is_transient: classified.isTransient,
        });

        results.push({
          job_id: job.job_id,
          recipient_email: job.recipient_email,
          status: classified.isTransient ? "pending_retry" : "failed_permanent",
          error: classified.message,
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed_count: jobs.length,
        transport: "nodemailer_smtp_tls",
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
