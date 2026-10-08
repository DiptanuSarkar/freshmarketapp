import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "AUTH_REQUIRED",
          message: "Authorization header is required.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      "";
    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY") ??
      "";
    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CONFIG_ERROR",
          message: "Server environment misconfigured.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!razorpayKeyId || !razorpayKeySecret) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "RAZORPAY_CONFIG_MISSING",
          message: "Razorpay credentials are not configured in server environment.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 1. Authenticate user from incoming JWT
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "AUTH_REQUIRED",
          message: "Your session has expired. Please sign in again.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 2. Parse request payload
    let body: {
      internal_order_id?: string;
      razorpay_payment_id?: string;
      razorpay_order_id?: string;
      razorpay_signature?: string;
    };

    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "INVALID_REQUEST",
          message: "Invalid request payload format.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const {
      internal_order_id,
      razorpay_payment_id,
      razorpay_order_id,
      razorpay_signature,
    } = body;

    if (!internal_order_id || !razorpay_payment_id || !razorpay_order_id || !razorpay_signature) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "MISSING_FIELDS",
          message: "internal_order_id, razorpay_payment_id, razorpay_order_id, and razorpay_signature are required.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // 3. Load order from database for this authenticated customer
    const { data: order, error: orderError } = await adminClient
      .from("orders")
      .select("id, order_number, user_id, status, total, payment_status")
      .eq("id", internal_order_id)
      .eq("user_id", user.id)
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "ORDER_NOT_FOUND",
          message: "Order was not found or does not belong to you.",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // If order is already confirmed, return success idempotently
    if (order.status === "confirmed" && order.payment_status === "completed") {
      return new Response(
        JSON.stringify({
          success: true,
          already_confirmed: true,
          internal_order_id: order.id,
          order_number: order.order_number,
          status: "confirmed",
          payment_status: "completed",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 4. Load latest payment record for this order
    const { data: payment, error: paymentError } = await adminClient
      .from("payments")
      .select("id, order_id, amount, status, gateway_order_id")
      .eq("order_id", internal_order_id)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (paymentError || !payment) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "PAYMENT_NOT_FOUND",
          message: "No payment record found for this order.",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Authoritative check: stored gateway_order_id must match client callback
    const storedGatewayOrderId = payment.gateway_order_id;
    if (!storedGatewayOrderId || storedGatewayOrderId !== razorpay_order_id) {
      console.error(
        `Gateway order mismatch: stored "${storedGatewayOrderId}" vs client "${razorpay_order_id}"`
      );
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "GATEWAY_ORDER_MISMATCH",
          message: "Payment order reference does not match server records.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 5. Authoritative Signature Verification
    // Razorpay signature formula: HMAC_SHA256(order_id + "|" + payment_id, secret)
    const expectedSignature = await computeHmacSha256(
      `${storedGatewayOrderId}|${razorpay_payment_id}`,
      razorpayKeySecret
    );

    if (!timingSafeEqual(expectedSignature, razorpay_signature)) {
      console.error("Payment signature verification failed for order", internal_order_id);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "SIGNATURE_VERIFICATION_FAILED",
          message: "Payment signature could not be verified.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 6. Authoritative Gateway Payment Status Verification via Razorpay REST API
    const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
    const rzPaymentRes = await fetch(
      `https://api.razorpay.com/v1/payments/${razorpay_payment_id}`,
      {
        headers: {
          Authorization: `Basic ${basicAuth}`,
        },
      }
    );

    if (!rzPaymentRes.ok) {
      const errText = await rzPaymentRes.text();
      console.error("Failed to fetch Razorpay payment:", rzPaymentRes.status, errText);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "GATEWAY_FETCH_FAILED",
          message: "Unable to verify payment with payment gateway.",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const rzPayment = await rzPaymentRes.json();

    // Verify order ID on payment entity
    if (rzPayment.order_id !== storedGatewayOrderId) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "PAYMENT_ORDER_MISMATCH",
          message: "The payment is associated with a different gateway order.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Verify currency
    if (rzPayment.currency !== "INR") {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "INVALID_CURRENCY",
          message: "Payment currency must be INR.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Verify amount in paise
    const expectedPaise = Math.round(Number(payment.amount) * 100);
    if (rzPayment.amount !== expectedPaise) {
      console.error(
        `Amount mismatch: expected ${expectedPaise} paise, got ${rzPayment.amount}`
      );
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "AMOUNT_MISMATCH",
          message: "Payment amount does not match order amount.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Verify status is captured
    if (rzPayment.status !== "captured") {
      console.warn(`Payment status is "${rzPayment.status}", not captured.`);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "PAYMENT_NOT_CAPTURED",
          message: `Payment is currently ${rzPayment.status}. FreshMarket only fulfills captured payments.`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 7. Atomic confirmation in PostgreSQL
    const { data: confirmResult, error: confirmError } = await adminClient.rpc(
      "rpc_confirm_razorpay_payment_atomic",
      {
        p_order_id: internal_order_id,
        p_gateway_payment_id: razorpay_payment_id,
        p_gateway_order_id: storedGatewayOrderId,
        p_gateway_signature: razorpay_signature,
        p_gateway_method: rzPayment.method || "online",
        p_gateway_status: rzPayment.status,
      }
    );

    if (confirmError) {
      console.error("rpc_confirm_razorpay_payment_atomic failed:", confirmError);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CONFIRMATION_FAILED",
          message: "Failed to confirm payment in database. Please check payment status.",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        verified: true,
        captured: true,
        internal_order_id: internal_order_id,
        order_number: order.order_number,
        status: "confirmed",
        payment_status: "completed",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled error in verify-razorpay-payment:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "INTERNAL_ERROR",
        message: "An unexpected error occurred during payment verification.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
