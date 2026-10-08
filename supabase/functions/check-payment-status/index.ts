import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

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

    // 2. Parse request
    let body: { order_id?: string };
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

    const { order_id } = body;
    if (!order_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "MISSING_ORDER_ID",
          message: "order_id is required.",
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

    // 3. Load order
    const { data: order, error: orderError } = await adminClient
      .from("orders")
      .select("id, order_number, user_id, status, total, payment_status, created_at")
      .eq("id", order_id)
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

    // If order already terminal (confirmed or cancelled), return immediately
    if (order.status !== "payment_pending") {
      return new Response(
        JSON.stringify({
          success: true,
          internal_order_id: order.id,
          order_number: order.order_number,
          status: order.status,
          payment_status: order.payment_status,
          reconciled: false,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 4. Order is payment_pending: check if payment was captured in Razorpay
    const { data: payment } = await adminClient
      .from("payments")
      .select("id, amount, status, gateway_order_id, expires_at")
      .eq("order_id", order_id)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (payment && payment.gateway_order_id && razorpayKeyId && razorpayKeySecret) {
      const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
      const rzPaymentsRes = await fetch(
        `https://api.razorpay.com/v1/orders/${payment.gateway_order_id}/payments`,
        {
          headers: {
            Authorization: `Basic ${basicAuth}`,
          },
        }
      );

      if (rzPaymentsRes.ok) {
        const rzPaymentsData = await rzPaymentsRes.json();
        const paymentsList = rzPaymentsData.items as Array<{
          id: string;
          status: string;
          amount: number;
          currency: string;
          method: string;
        }>;

        const capturedPayment = paymentsList?.find((p) => p.status === "captured");
        if (capturedPayment) {
          // Reconcile and confirm payment in database
          await adminClient.rpc("rpc_confirm_razorpay_payment_atomic", {
            p_order_id: order.id,
            p_gateway_payment_id: capturedPayment.id,
            p_gateway_order_id: payment.gateway_order_id,
            p_gateway_signature: null,
            p_gateway_method: capturedPayment.method || "reconciliation",
            p_gateway_status: "captured",
          });

          return new Response(
            JSON.stringify({
              success: true,
              internal_order_id: order.id,
              order_number: order.order_number,
              status: "confirmed",
              payment_status: "completed",
              reconciled: true,
            }),
            {
              status: 200,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }
    }

    // If order is older than 15 minutes, trigger expiry
    const orderCreatedAt = new Date(order.created_at).getTime();
    const fifteenMinutesAgo = Date.now() - 15 * 60 * 1000;
    if (orderCreatedAt < fifteenMinutesAgo) {
      await adminClient.rpc("rpc_expire_pending_razorpay_orders");

      return new Response(
        JSON.stringify({
          success: true,
          internal_order_id: order.id,
          order_number: order.order_number,
          status: "cancelled",
          payment_status: "cancelled",
          reconciled: true,
          expired: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        internal_order_id: order.id,
        order_number: order.order_number,
        status: "payment_pending",
        payment_status: payment?.status || "pending",
        reconciled: false,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled error in check-payment-status:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "INTERNAL_ERROR",
        message: "An unexpected error occurred while checking payment status.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
