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

    // 3. Execute atomic cancellation transaction in PostgreSQL
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

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
