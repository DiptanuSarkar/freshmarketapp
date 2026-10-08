import { createClient } from "jsr:@supabase/supabase-js@2";

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

async function computeHmacSha256(data: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signatureBuffer = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(data)
  );
  const hashArray = Array.from(new Uint8Array(signatureBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  try {
    const signature = req.headers.get("x-razorpay-signature");
    if (!signature) {
      console.warn("Webhook rejected: missing x-razorpay-signature header");
      return new Response(JSON.stringify({ error: "Missing webhook signature" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
    if (!webhookSecret) {
      console.error("RAZORPAY_WEBHOOK_SECRET is not configured");
      return new Response(JSON.stringify({ error: "Webhook secret unconfigured" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // CRITICAL: Read EXACT RAW REQUEST BODY before any parsing
    const rawBody = await req.text();

    // Verify HMAC SHA256 of raw body
    const expectedSignature = await computeHmacSha256(rawBody, webhookSecret);
    if (!timingSafeEqual(expectedSignature, signature)) {
      console.warn("Webhook rejected: invalid signature");
      return new Response(JSON.stringify({ error: "Invalid webhook signature" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Parse verified payload
    let event: {
      entity?: string;
      account_id?: string;
      event?: string;
      contains?: string[];
      payload?: {
        payment?: {
          entity?: {
            id?: string;
            order_id?: string;
            amount?: number;
            currency?: string;
            status?: string;
            method?: string;
            error_code?: string;
            error_description?: string;
            error_source?: string;
            error_step?: string;
            error_reason?: string;
          };
        };
        order?: {
          entity?: {
            id?: string;
            amount_paid?: number;
            status?: string;
          };
        };
      };
      created_at?: number;
    };

    try {
      event = JSON.parse(rawBody);
    } catch {
      return new Response(JSON.stringify({ error: "Malformed payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const eventType = event.event;
    if (!eventType) {
      return new Response(JSON.stringify({ status: "ignored_no_event_type" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const paymentEntity = event.payload?.payment?.entity;
    const rzOrderId = paymentEntity?.order_id || event.payload?.order?.entity?.id || null;
    const rzPaymentId = paymentEntity?.id || null;

    // Build deduplication key for this event
    const eventKey = `${eventType}_${rzOrderId || 'no_order'}_${rzPaymentId || 'no_payment'}_${event.created_at || Date.now()}`;

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY") ??
      "";

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Idempotency check: insert webhook event row
    const { error: insertError } = await adminClient
      .from("payment_webhook_events")
      .insert({
        provider: "razorpay",
        event_key: eventKey,
        event_type: eventType,
        gateway_order_id: rzOrderId,
        gateway_payment_id: rzPaymentId,
        processing_status: "received",
        payload: event,
      });

    if (insertError && insertError.code === "23505") {
      // Duplicate event delivery
      console.log(`Webhook event ${eventKey} already received. Returning 200.`);
      return new Response(
        JSON.stringify({ status: "already_processed", duplicate: true, event_key: eventKey }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Process event types
    if (eventType === "payment.captured" || eventType === "order.paid") {
      if (rzOrderId && paymentEntity) {
        // Find matching FreshMarket pending payment by gateway_order_id
        const { data: dbPayment } = await adminClient
          .from("payments")
          .select("id, order_id, amount, status")
          .eq("gateway_order_id", rzOrderId)
          .order("created_at", { ascending: false })
          .limit(1)
          .single();

        if (dbPayment) {
          const expectedPaise = Math.round(Number(dbPayment.amount) * 100);

          // Verify amount and currency
          if (
            paymentEntity.currency === "INR" &&
            paymentEntity.amount === expectedPaise
          ) {
            // Atomically confirm payment
            await adminClient.rpc("rpc_confirm_razorpay_payment_atomic", {
              p_order_id: dbPayment.order_id,
              p_gateway_payment_id: rzPaymentId,
              p_gateway_order_id: rzOrderId,
              p_gateway_signature: null,
              p_gateway_method: paymentEntity.method || "webhook",
              p_gateway_status: paymentEntity.status || "captured",
            });

            await adminClient
              .from("payment_webhook_events")
              .update({
                processing_status: "processed",
                processed_at: new Date().toISOString(),
              })
              .eq("event_key", eventKey);
          } else {
            console.warn(
              `Webhook amount/currency mismatch for order ${rzOrderId}: expected ${expectedPaise} INR, got ${paymentEntity.amount} ${paymentEntity.currency}`
            );
          }
        }
      }
    } else if (eventType === "payment.failed") {
      if (rzOrderId && paymentEntity) {
        const { data: dbPayment } = await adminClient
          .from("payments")
          .select("id, order_id")
          .eq("gateway_order_id", rzOrderId)
          .order("created_at", { ascending: false })
          .limit(1)
          .single();

        if (dbPayment) {
          await adminClient.rpc("rpc_record_razorpay_payment_failure_atomic", {
            p_order_id: dbPayment.order_id,
            p_gateway_payment_id: rzPaymentId,
            p_error_code: paymentEntity.error_code || null,
            p_error_description: paymentEntity.error_description || null,
            p_error_source: paymentEntity.error_source || null,
            p_error_step: paymentEntity.error_step || null,
            p_error_reason: paymentEntity.error_reason || null,
          });

          await adminClient
            .from("payment_webhook_events")
            .update({
              processing_status: "processed",
              processed_at: new Date().toISOString(),
            })
              .eq("event_key", eventKey);
        }
      }
    } else {
      // Other events acknowledged and marked ignored
      await adminClient
        .from("payment_webhook_events")
        .update({
          processing_status: "ignored",
          processed_at: new Date().toISOString(),
        })
        .eq("event_key", eventKey);

      return new Response(JSON.stringify({ status: "ok", ignored: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ status: "ok" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled webhook processing error:", errorMsg);
    return new Response(JSON.stringify({ error: "Webhook processing error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
