import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function mapCancelError(errorMsg: string): { code: string; message: string } {
  if (errorMsg.includes("ORDER_NOT_FOUND")) {
    return {
      code: "ORDER_NOT_FOUND",
      message: "Order was not found or does not belong to your account.",
    };
  }
  if (errorMsg.includes("ORDER_NOT_CANCELLABLE")) {
    return {
      code: "ORDER_NOT_CANCELLABLE",
      message: "This order is already being prepared or out for delivery and can no longer be cancelled.",
    };
  }
  return {
    code: "CANCELLATION_FAILED",
    message: "Unable to process order cancellation at this time.",
  };
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

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CANCELLATION_FAILED",
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

    // 2. Validate payload
    let body: { order_id?: string; reason?: string };
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CANCELLATION_FAILED",
          message: "Invalid cancellation request format.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const orderId = body.order_id;
    const reason = body.reason?.trim() || "Customer requested cancellation";

    if (!orderId) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "ORDER_NOT_FOUND",
          message: "Order ID is required for cancellation.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 3. Check order payment status to determine cancellation path
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: order, error: orderFetchError } = await adminClient
      .from("orders")
      .select("id, status, payment_status, payment_method, total")
      .eq("id", orderId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (orderFetchError || !order) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "ORDER_NOT_FOUND",
          message: "Order was not found or does not belong to your account.",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // A. Paid Order Refund Flow
    if (order.payment_status === "completed") {
      const refundRequestId = `RFND-REQ-${orderId}-${Date.now()}`;
      const { data: refundResult, error: prepRefundError } = await adminClient.rpc(
        "rpc_prepare_order_cancellation_refund_atomic",
        {
          p_user_id: user.id,
          p_order_id: orderId,
          p_reason: reason,
          p_refund_request_id: refundRequestId,
        }
      );

      if (prepRefundError) {
        console.error("rpc_prepare_order_cancellation_refund_atomic failed:", prepRefundError);
        const mapped = mapCancelError(prepRefundError.message || "");
        return new Response(
          JSON.stringify({
            success: false,
            error_code: mapped.code,
            message: mapped.message,
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // If online/gateway portion exists, invoke Razorpay Refunds API
      if (refundResult.requires_gateway_refund && refundResult.gateway_payment_id) {
        const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
        const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

        if (razorpayKeyId && razorpayKeySecret) {
          const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
          try {
            const rzRefundRes = await fetch(
              `https://api.razorpay.com/v1/payments/${refundResult.gateway_payment_id}/refund`,
              {
                method: "POST",
                headers: {
                  Authorization: `Basic ${basicAuth}`,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  amount: Math.round(Number(refundResult.gateway_refund_amount) * 100),
                  speed: "optimum",
                  notes: {
                    freshmarket_order_id: refundResult.order_id,
                    freshmarket_refund_id: refundResult.refund_id,
                  },
                  receipt: `RFND-${refundResult.order_number}`.substring(0, 40),
                }),
              }
            );

            if (rzRefundRes.ok) {
              const rzRefund = await rzRefundRes.json();
              await adminClient.rpc("rpc_record_gateway_refund_submission_atomic", {
                p_refund_id: refundResult.refund_id,
                p_gateway_refund_id: rzRefund.id,
                p_provider_status: rzRefund.status || "processed",
              });
            } else {
              const rzErrText = await rzRefundRes.text();
              console.error("Razorpay refund creation failed:", rzRefundRes.status, rzErrText);
              await adminClient.rpc("rpc_record_gateway_refund_submission_atomic", {
                p_refund_id: refundResult.refund_id,
                p_gateway_refund_id: null,
                p_provider_status: "failed",
                p_error_code: `RZ_HTTP_${rzRefundRes.status}`,
                p_error_message: rzErrText,
              });
            }
          } catch (rzErr) {
            console.error("Razorpay refund network error:", rzErr);
          }
        }
      }

      return new Response(JSON.stringify(refundResult), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // B. Unpaid / COD Order Cancellation Flow
    const { data: cancelResult, error: rpcError } = await adminClient.rpc(
      "rpc_cancel_order_atomic",
      {
        p_user_id: user.id,
        p_order_id: orderId,
        p_reason: reason,
      }
    );

    if (rpcError) {
      console.error("rpc_cancel_order_atomic failed:", rpcError);
      const mapped = mapCancelError(rpcError.message || "");
      return new Response(
        JSON.stringify({
          success: false,
          error_code: mapped.code,
          message: mapped.message,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(JSON.stringify(cancelResult), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : "Unknown error";
    console.error("cancel-order exception:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "CANCELLATION_FAILED",
        message: "An unexpected error occurred while cancelling your order.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
