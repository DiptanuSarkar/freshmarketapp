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
  if (errorMsg.includes("ORDER_EXPIRED")) {
    return {
      code: "ORDER_EXPIRED",
      message: "The payment window for this order has expired. Please place a new order.",
    };
  }
  if (errorMsg.includes("ORDER_NOT_RETRYABLE")) {
    return {
      code: "ORDER_NOT_RETRYABLE",
      message: "This order is not eligible for payment retry.",
    };
  }
  return {
    code: "CHECKOUT_FAILED",
    message: "Unable to initialize online payment. Please verify your details and try again.",
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
    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

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
      order_id?: string;
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

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Handle Payment Retry Flow (for existing payment_pending order)
    if (body.order_id) {
      const { data: retryResult, error: retryError } = await adminClient.rpc(
        "rpc_prepare_razorpay_retry_atomic",
        {
          p_user_id: user.id,
          p_order_id: body.order_id,
        }
      );

      if (retryError) {
        console.error("rpc_prepare_razorpay_retry_atomic failed:", retryError);
        const mapped = mapErrorToResponse(retryError.message);
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

      const orderData = retryResult as {
        id: string;
        order_number: string;
        payment_id: string;
        amount_paise: number;
        attempt_no: number;
        delivery_address_snapshot: Record<string, unknown>;
      };

      // Call Razorpay Orders API for retry attempt
      const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
      const rzResponse = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          Authorization: `Basic ${basicAuth}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: orderData.amount_paise,
          currency: "INR",
          receipt: `${orderData.order_number}-A${orderData.attempt_no}`.substring(0, 40),
          partial_payment: false,
          notes: {
            freshmarket_order_id: orderData.id,
            freshmarket_order_number: orderData.order_number,
            user_id: user.id,
            attempt_no: String(orderData.attempt_no),
          },
        }),
      });

      if (!rzResponse.ok) {
        const rzErrorText = await rzResponse.text();
        console.error("Razorpay order creation failed during retry:", rzResponse.status, rzErrorText);
        return new Response(
          JSON.stringify({
            success: false,
            error_code: "GATEWAY_INIT_FAILED",
            message: "Unable to create payment attempt with Razorpay. Please try again.",
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const rzOrder = await rzResponse.json();

      // Update payment record with new gateway order ID
      await adminClient.rpc("rpc_set_payment_gateway_order", {
        p_order_id: orderData.id,
        p_payment_id: orderData.payment_id,
        p_gateway_order_id: rzOrder.id,
      });

      const recipientName =
        (orderData.delivery_address_snapshot?.recipient_name as string) ||
        user.user_metadata?.full_name ||
        "Customer";
      const contactPhone =
        (orderData.delivery_address_snapshot?.phone as string) ||
        user.phone ||
        "";

      return new Response(
        JSON.stringify({
          success: true,
          internal_order_id: orderData.id,
          internal_order_number: orderData.order_number,
          payment_id: orderData.payment_id,
          razorpay_order_id: rzOrder.id,
          razorpay_key_id: razorpayKeyId,
          amount_paise: orderData.amount_paise,
          currency: "INR",
          prefill: {
            name: recipientName,
            email: user.email || "",
            contact: contactPhone,
          },
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Initial Online Checkout Flow
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

    // Execute atomic preparation transaction
    const { data: prepResult, error: prepError } = await adminClient.rpc(
      "rpc_prepare_razorpay_order_atomic",
      {
        p_user_id: user.id,
        p_checkout_request_id: checkout_request_id,
        p_address_id: address_id,
        p_delivery_slot_id: delivery_slot_id,
        p_coupon_code: coupon_code ? coupon_code.trim() : null,
        p_customer_notes: customer_notes ? customer_notes.trim() : null,
      }
    );

    if (prepError) {
      console.error("rpc_prepare_razorpay_order_atomic failed:", prepError);
      const mapped = mapErrorToResponse(prepError.message);
      return new Response(
        JSON.stringify({
          success: false,
          error_code: mapped.code,
          message: mapped.message,
          raw_error: prepError.message,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const orderData = prepResult as {
      id: string;
      order_number: string;
      payment_id: string;
      amount_paise: number;
      is_idempotent_retry?: boolean;
      gateway_order_id?: string;
      delivery_address_snapshot: Record<string, unknown>;
    };

    // If idempotent retry and gateway order ID is already assigned, return it
    if (orderData.is_idempotent_retry && orderData.gateway_order_id) {
      const recipientName =
        (orderData.delivery_address_snapshot?.recipient_name as string) ||
        user.user_metadata?.full_name ||
        "Customer";
      const contactPhone =
        (orderData.delivery_address_snapshot?.phone as string) ||
        user.phone ||
        "";

      return new Response(
        JSON.stringify({
          success: true,
          is_idempotent_retry: true,
          internal_order_id: orderData.id,
          internal_order_number: orderData.order_number,
          payment_id: orderData.payment_id,
          razorpay_order_id: orderData.gateway_order_id,
          razorpay_key_id: razorpayKeyId,
          amount_paise: orderData.amount_paise,
          currency: "INR",
          prefill: {
            name: recipientName,
            email: user.email || "",
            contact: contactPhone,
          },
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Call external Razorpay Orders API server-side
    const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`);
    const rzResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        Authorization: `Basic ${basicAuth}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: orderData.amount_paise,
        currency: "INR",
        receipt: orderData.order_number.substring(0, 40),
        partial_payment: false,
        notes: {
          freshmarket_order_id: orderData.id,
          freshmarket_order_number: orderData.order_number,
          user_id: user.id,
        },
      }),
    });

    if (!rzResponse.ok) {
      const rzErrorText = await rzResponse.text();
      console.error("Razorpay order creation failed:", rzResponse.status, rzErrorText);

      // Phase 6 Compensation: Release inventory reservations and cancel pending order
      await adminClient.rpc("rpc_fail_razorpay_initialization_atomic", {
        p_order_id: orderData.id,
        p_reason: `Razorpay Orders API rejected initialization: ${rzResponse.status}`,
      });

      return new Response(
        JSON.stringify({
          success: false,
          error_code: "GATEWAY_INIT_FAILED",
          message: "Unable to initiate payment with Razorpay. Please try again or select Cash on Delivery.",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const rzOrder = await rzResponse.json();

    // Store returned Razorpay order ID in payments record
    await adminClient.rpc("rpc_set_payment_gateway_order", {
      p_order_id: orderData.id,
      p_payment_id: orderData.payment_id,
      p_gateway_order_id: rzOrder.id,
    });

    const recipientName =
      (orderData.delivery_address_snapshot?.recipient_name as string) ||
      user.user_metadata?.full_name ||
      "Customer";
    const contactPhone =
      (orderData.delivery_address_snapshot?.phone as string) ||
      user.phone ||
      "";

    return new Response(
      JSON.stringify({
        success: true,
        internal_order_id: orderData.id,
        internal_order_number: orderData.order_number,
        payment_id: orderData.payment_id,
        razorpay_order_id: rzOrder.id,
        razorpay_key_id: razorpayKeyId,
        amount_paise: orderData.amount_paise,
        currency: "INR",
        prefill: {
          name: recipientName,
          email: user.email || "",
          contact: contactPhone,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled error in create-razorpay-order:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "INTERNAL_ERROR",
        message: "An unexpected server error occurred.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
