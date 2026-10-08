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
          message: "Authorization header is missing.",
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
          error_code: "CHECKOUT_FAILED",
          message: "Server configuration missing.",
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
          message: "Invalid or expired session. Please log in again.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 2. Parse non-authoritative client choices
    let body: {
      address_id?: string | null;
      delivery_slot_id?: string | null;
      coupon_code?: string | null;
    } = {};

    try {
      if (req.headers.get("content-length") !== "0") {
        body = await req.json();
      }
    } catch {
      // Empty or invalid body is acceptable; defaults to null
    }

    const addressId = body.address_id ?? null;
    const deliverySlotId = body.delivery_slot_id ?? null;
    const couponCode = body.coupon_code ? body.coupon_code.trim() : null;

    // 3. Call server-authoritative calculation RPC using service_role
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: quoteResult, error: rpcError } = await adminClient.rpc(
      "rpc_calculate_checkout_quote",
      {
        p_user_id: user.id,
        p_address_id: addressId,
        p_delivery_slot_id: deliverySlotId,
        p_coupon_code: couponCode,
      }
    );

    if (rpcError) {
      console.error("rpc_calculate_checkout_quote error:", rpcError);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CHECKOUT_FAILED",
          message: "Unable to calculate checkout quote at this time.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!quoteResult || quoteResult.success === false) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: quoteResult?.error_code ?? "CHECKOUT_FAILED",
          message: quoteResult?.message ?? "Unable to calculate checkout quote.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(JSON.stringify(quoteResult), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : "Unknown error";
    console.error("checkout-quote exception:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "CHECKOUT_FAILED",
        message: "An unexpected error occurred while calculating your quote.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
