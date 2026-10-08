import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function mapErrorToResponse(errorMsg: string): { code: string; message: string } {
  if (errorMsg.includes("EMPTY_CART")) {
    return {
      code: "EMPTY_CART",
      message: "Your cart is empty. Please add items before placing an order.",
    };
  }
  if (errorMsg.includes("ADDRESS_NOT_FOUND") || errorMsg.includes("ADDRESS_INVALID")) {
    return {
      code: "ADDRESS_NOT_FOUND",
      message: "Please select a valid delivery address with a PIN code.",
    };
  }
  if (errorMsg.includes("AREA_NOT_SERVICEABLE")) {
    return {
      code: "AREA_NOT_SERVICEABLE",
      message: "We do not currently deliver fresh cuts to this PIN code.",
    };
  }
  if (errorMsg.includes("DELIVERY_SLOT_UNAVAILABLE")) {
    return {
      code: "DELIVERY_SLOT_UNAVAILABLE",
      message: "The selected delivery slot is no longer available. Please select another slot.",
    };
  }
  if (errorMsg.includes("OUT_OF_STOCK")) {
    return {
      code: "OUT_OF_STOCK",
      message: "One or more cuts in your cart just sold out. Please review your cart quantities.",
    };
  }
  if (errorMsg.includes("PRODUCT_UNAVAILABLE")) {
    return {
      code: "PRODUCT_UNAVAILABLE",
      message: "An item in your cart is currently unavailable from our butchery.",
    };
  }
  if (errorMsg.includes("VARIANT_UNAVAILABLE")) {
    return {
      code: "VARIANT_UNAVAILABLE",
      message: "The selected package size is temporarily unavailable.",
    };
  }
  if (errorMsg.includes("COUPON_EXPIRED")) {
    return {
      code: "COUPON_EXPIRED",
      message: "This coupon code has expired.",
    };
  }
  if (errorMsg.includes("COUPON_USAGE_EXCEEDED")) {
    return {
      code: "COUPON_USAGE_EXCEEDED",
      message: "Coupon redemption limit has been reached.",
    };
  }
  if (errorMsg.includes("MINIMUM_ORDER_NOT_MET")) {
    return {
      code: "MINIMUM_ORDER_NOT_MET",
      message: "Your order total does not meet the minimum requirement for this coupon.",
    };
  }
  if (errorMsg.includes("COUPON_INVALID")) {
    return {
      code: "COUPON_INVALID",
      message: "The coupon code provided is invalid or not applicable to your order.",
    };
  }
  return {
    code: "CHECKOUT_FAILED",
    message: "Unable to complete order placement. Please verify your details and try again.",
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
          error_code: "CHECKOUT_FAILED",
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

    // 2. Validate client payload
    let body: {
      checkout_request_id?: string;
      address_id?: string;
      delivery_slot_id?: string;
      coupon_code?: string | null;
      customer_notes?: string | null;
    };

    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CHECKOUT_FAILED",
          message: "Invalid request payload format.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const {
      checkout_request_id,
      address_id,
      delivery_slot_id,
      coupon_code,
      customer_notes,
    } = body;

    if (!checkout_request_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "CHECKOUT_FAILED",
          message: "Missing idempotency identifier (checkout_request_id).",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!address_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "ADDRESS_NOT_FOUND",
          message: "Please select a valid delivery address.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!delivery_slot_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "DELIVERY_SLOT_UNAVAILABLE",
          message: "Please select a delivery slot.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 3. Execute atomic transaction in PostgreSQL using service_role
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: orderResult, error: rpcError } = await adminClient.rpc(
      "rpc_create_cod_order_atomic",
      {
        p_user_id: user.id,
        p_checkout_request_id: checkout_request_id,
        p_address_id: address_id,
        p_delivery_slot_id: delivery_slot_id,
        p_coupon_code: coupon_code ? coupon_code.trim() : null,
        p_customer_notes: customer_notes ? customer_notes.trim() : null,
      }
    );

    if (rpcError) {
      console.error("rpc_create_cod_order_atomic failed:", rpcError);
      const mapped = mapErrorToResponse(rpcError.message || "");
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

    return new Response(JSON.stringify(orderResult), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : "Unknown error";
    console.error("create-cod-order exception:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "CHECKOUT_FAILED",
        message: "An unexpected error occurred while placing your order. Please try again.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
