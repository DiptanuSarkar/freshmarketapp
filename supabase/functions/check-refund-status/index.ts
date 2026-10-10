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

    // 2. Parse request body
    let body: { order_id?: string; refund_id?: string };
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

    const { order_id, refund_id } = body;
    if (!order_id && !refund_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "MISSING_IDENTIFIER",
          message: "Either order_id or refund_id is required.",
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

    // 3. Find refund record
    let query = adminClient
      .from("refunds")
      .select("*, refund_components(*), orders!inner(user_id, order_number)")
      .eq("orders.user_id", user.id);

    if (refund_id) {
      query = query.eq("id", refund_id);
    } else if (order_id) {
      query = query.eq("order_id", order_id).order("created_at", { ascending: false });
    }

    const { data: refundRows, error: fetchError } = await query;

    if (fetchError || !refundRows || refundRows.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "REFUND_NOT_FOUND",
          message: "Refund record not found.",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const refund = refundRows[0];

    // 4. Reconcile with Razorpay API if any gateway component is processing and has gateway_refund_id
    const razorpayComponent = refund.refund_components?.find(
      (c: { method: string; status: string }) => c.method === "razorpay" && c.status === "processing"
    );

    if (
      razorpayComponent &&
      razorpayComponent.gateway_refund_id &&
      razorpayKeyId &&
      razorpayKeySecret
    ) {
      const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
      try {
        const rzRes = await fetch(
          `https://api.razorpay.com/v1/refunds/${razorpayComponent.gateway_refund_id}`,
          {
            headers: {
              Authorization: `Basic ${basicAuth}`,
            },
          }
        );

        if (rzRes.ok) {
          const rzRefund = await rzRes.json();
          if (rzRefund.status && rzRefund.status !== razorpayComponent.provider_status) {
            await adminClient.rpc("rpc_record_gateway_refund_submission_atomic", {
              p_refund_id: refund.id,
              p_gateway_refund_id: rzRefund.id,
              p_provider_status: rzRefund.status,
            });

            // Re-fetch updated refund record
            const { data: updatedRows } = await adminClient
              .from("refunds")
              .select("*, refund_components(*)")
              .eq("id", refund.id)
              .maybeSingle();

            if (updatedRows) {
              Object.assign(refund, updatedRows);
            }
          }
        }
      } catch (err) {
        console.warn("Reconciliation call to Razorpay failed:", err);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        refund: {
          id: refund.id,
          order_id: refund.order_id,
          payment_id: refund.payment_id,
          amount: refund.amount,
          status: refund.status,
          reason: refund.reason,
          wallet_amount: refund.wallet_amount,
          gateway_amount: refund.gateway_amount,
          created_at: refund.created_at,
          processed_at: refund.processed_at,
          failed_at: refund.failed_at,
          components: refund.refund_components || [],
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled error in check-refund-status:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "INTERNAL_ERROR",
        message: "An unexpected error occurred while checking refund status.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
