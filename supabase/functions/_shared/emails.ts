import { SupabaseClient } from "npm:@supabase/supabase-js@2.48.1";
import { getSupabaseUrl, getSecretKey } from "./keys.ts";

export interface TransactionalEmailJobParams {
  userId?: string;
  recipientEmail: string;
  eventType: string;
  templateKey: string;
  payload: Record<string, unknown>;
  eventKey: string;
  triggerDispatch?: boolean;
}

/**
 * Escapes HTML characters for security.
 */
export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Base email layout wrapper with professional FreshMarket branding.
 */
function wrapHtmlLayout(title: string, bodyContent: string): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F8FAFC; margin: 0; padding: 0; color: #1E293B; }
    .container { max-width: 600px; margin: 24px auto; background-color: #FFFFFF; border-radius: 12px; overflow: hidden; border: 1px solid #E2E8F0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05); }
    .header { background: linear-gradient(135deg, #0F766E 0%, #134E4A 100%); padding: 32px 24px; text-align: center; }
    .header h1 { color: #FFFFFF; margin: 0; font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
    .header p { color: #CCFBF1; margin: 6px 0 0 0; font-size: 13px; font-weight: 500; }
    .content { padding: 32px 24px; }
    .footer { background-color: #F1F5F9; padding: 20px 24px; text-align: center; font-size: 12px; color: #64748B; border-top: 1px solid #E2E8F0; }
    .order-box { background-color: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; padding: 16px; margin: 20px 0; }
    .badge { display: inline-block; padding: 4px 10px; border-radius: 9999px; font-size: 11px; font-weight: 700; background-color: #CCFBF1; color: #0F766E; }
    .price-row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 14px; }
    .total-row { display: flex; justify-content: space-between; padding: 12px 0 0 0; margin-top: 8px; border-top: 2px solid #E2E8F0; font-size: 16px; font-weight: 800; color: #0F766E; }
    .btn { display: inline-block; background-color: #0F766E; color: #FFFFFF; text-decoration: none; padding: 12px 24px; border-radius: 8px; font-weight: 700; font-size: 14px; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>FreshMarket</h1>
      <p>Artisanal Butchery &amp; Cold-Chain Express • Agartala</p>
    </div>
    <div class="content">
      ${bodyContent}
    </div>
    <div class="footer">
      <p>Need assistance? Contact our Agartala Care Team via WhatsApp or email care@freshmarket.in</p>
      <p>&copy; ${new Date().getFullYear()} FreshMarket. All rights reserved.</p>
    </div>
  </div>
</body>
</html>`;
}

/**
 * Builds email subject, HTML, and plain-text body according to templateKey and payload.
 */
export function renderEmailTemplate(
  templateKey: string,
  payload: Record<string, unknown>
): { subject: string; html: string; text: string } {
  const orderNumber = String(payload.order_number || payload.order_id || "Order");
  const total = payload.total !== undefined ? `₹${payload.total}` : "";

  switch (templateKey) {
    case "order_confirmed": {
      const paymentMethod = String(payload.payment_method || "COD").toUpperCase();
      const subject = `Order Confirmed: #${orderNumber} • FreshMarket`;
      const htmlBody = `
        <div style="text-align: center; margin-bottom: 24px;">
          <span class="badge">ORDER CONFIRMED</span>
          <h2 style="margin: 12px 0 4px 0; color: #0F766E; font-size: 20px;">Your butchery cuts are being prepped!</h2>
          <p style="color: #64748B; font-size: 14px; margin: 0;">Order #${escapeHtml(orderNumber)} has been received and scheduled for dispatch.</p>
        </div>
        <div class="order-box">
          <table style="width: 100%; border-collapse: collapse;">
            <tr><td style="color: #64748B; padding: 4px 0; font-size: 13px;">Order Number:</td><td style="text-align: right; font-weight: 700; font-size: 13px;">#${escapeHtml(orderNumber)}</td></tr>
            <tr><td style="color: #64748B; padding: 4px 0; font-size: 13px;">Payment Method:</td><td style="text-align: right; font-weight: 700; font-size: 13px;">${escapeHtml(paymentMethod)}</td></tr>
            <tr><td style="color: #64748B; padding: 4px 0; font-size: 13px;">Delivery Zone:</td><td style="text-align: right; font-weight: 700; font-size: 13px;">Agartala City AMC</td></tr>
            <tr style="border-top: 1px solid #E2E8F0;"><td style="color: #0F766E; padding: 8px 0 0 0; font-weight: 800; font-size: 16px;">Total Amount:</td><td style="text-align: right; color: #0F766E; padding: 8px 0 0 0; font-weight: 800; font-size: 16px;">${escapeHtml(total)}</td></tr>
          </table>
        </div>
        <p style="font-size: 13px; color: #475569; line-height: 1.5;">
          Our chilled, non-frozen fresh cuts will be hygienically prepped and dispatched in temperature-controlled carriers directly to your address.
        </p>
      `;
      const text = `FreshMarket Order Confirmed: #${orderNumber}\n\nYour order #${orderNumber} for ${total} has been confirmed via ${paymentMethod}.\nDelivery: Agartala City Zone.\nThank you for choosing FreshMarket!`;
      return { subject, html: wrapHtmlLayout(subject, htmlBody), text };
    }

    case "order_cancelled": {
      const reason = String(payload.reason || "Customer requested cancellation");
      const subject = `Order Cancelled: #${orderNumber} • FreshMarket`;
      const htmlBody = `
        <div style="text-align: center; margin-bottom: 24px;">
          <span class="badge" style="background-color: #FEE2E2; color: #DC2626;">ORDER CANCELLED</span>
          <h2 style="margin: 12px 0 4px 0; color: #DC2626; font-size: 20px;">Order #${escapeHtml(orderNumber)} has been cancelled</h2>
          <p style="color: #64748B; font-size: 14px; margin: 0;">Reason: ${escapeHtml(reason)}</p>
        </div>
        <div class="order-box">
          <p style="margin: 0; font-size: 13px; color: #475569;">
            Reserved stock has been released. If this was a paid order, your refund has been initiated to your original payment source or FreshMarket Wallet.
          </p>
        </div>
      `;
      const text = `FreshMarket Order Cancelled: #${orderNumber}\n\nYour order #${orderNumber} has been cancelled.\nReason: ${reason}\nAny eligible refund has been processed.`;
      return { subject, html: wrapHtmlLayout(subject, htmlBody), text };
    }

    case "payment_successful": {
      const subject = `Payment Successful for Order #${orderNumber} • FreshMarket`;
      const htmlBody = `
        <div style="text-align: center; margin-bottom: 24px;">
          <span class="badge">PAYMENT SUCCESSFUL</span>
          <h2 style="margin: 12px 0 4px 0; color: #0F766E; font-size: 20px;">Payment of ${escapeHtml(total)} Received</h2>
          <p style="color: #64748B; font-size: 14px; margin: 0;">Your online payment for order #${escapeHtml(orderNumber)} was successfully processed.</p>
        </div>
      `;
      const text = `FreshMarket Payment Successful\n\nPayment of ${total} for order #${orderNumber} was confirmed.`;
      return { subject, html: wrapHtmlLayout(subject, htmlBody), text };
    }

    case "refund_processed": {
      const refundAmount = payload.refund_amount !== undefined ? `₹${payload.refund_amount}` : total;
      const subject = `Refund Processed for Order #${orderNumber} • FreshMarket`;
      const htmlBody = `
        <div style="text-align: center; margin-bottom: 24px;">
          <span class="badge">REFUND PROCESSED</span>
          <h2 style="margin: 12px 0 4px 0; color: #0F766E; font-size: 20px;">Refund of ${escapeHtml(refundAmount)} Processed</h2>
          <p style="color: #64748B; font-size: 14px; margin: 0;">Your refund for order #${escapeHtml(orderNumber)} has been credited or submitted to the banking gateway.</p>
        </div>
      `;
      const text = `FreshMarket Refund Processed\n\nRefund of ${refundAmount} for order #${orderNumber} has been processed.`;
      return { subject, html: wrapHtmlLayout(subject, htmlBody), text };
    }

    default: {
      const subject = `Notification for Order #${orderNumber} • FreshMarket`;
      const htmlBody = `<p>You have a new update regarding order #${escapeHtml(orderNumber)}.</p>`;
      const text = `FreshMarket update for order #${orderNumber}.`;
      return { subject, html: wrapHtmlLayout(subject, htmlBody), text };
    }
  }
}

/**
 * Centrally and idempotently enqueues a transactional email job in public.transactional_email_jobs.
 * Non-blocking: failures are logged and never throw to caller or disrupt commerce.
 */
export async function createTransactionalEmailJob(
  client: SupabaseClient,
  params: TransactionalEmailJobParams
): Promise<{ success: boolean; jobId?: string; isDuplicate?: boolean }> {
  try {
    const { data, error } = await client.rpc("rpc_enqueue_transactional_email", {
      p_user_id: params.userId || null,
      p_event_key: params.eventKey,
      p_event_type: params.eventType,
      p_recipient_email: params.recipientEmail,
      p_template_key: params.templateKey,
      p_payload: params.payload || {},
    });

    if (error) {
      console.warn("Non-blocking error enqueuing transactional email:", error.message);
      return { success: false };
    }

    const jobId = data?.job_id;

    // Trigger immediate async dispatch worker without awaiting
    if (params.triggerDispatch !== false && jobId) {
      const url = `${getSupabaseUrl()}/functions/v1/dispatch-transactional-emails`;
      const secret = getSecretKey();
      fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${secret}`,
        },
        body: JSON.stringify({ job_id: jobId }),
      }).catch((e) => {
        console.warn("Immediate email dispatch trigger deferred to worker:", e);
      });
    }

    return {
      success: true,
      jobId,
      isDuplicate: data?.is_duplicate ?? false,
    };
  } catch (err) {
    console.warn("Unexpected non-blocking exception during email enqueue:", err);
    return { success: false };
  }
}
