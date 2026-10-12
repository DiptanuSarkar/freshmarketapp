import { corsHeaders } from "../_shared/cors.ts";
import { createServiceClient, createUserClient } from "../_shared/keys.ts";

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
  if (errorMsg.includes("AREA_NOT_SERVICEABLE") || errorMsg.includes("UNSUPPORTED_PINCODE")) {
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
  if (errorMsg.includes("INSUFFICIENT_FUNDS") || errorMsg.includes("INSUFFICIENT_WALLET")) {
    return {
      code: "INSUFFICIENT_WALLET_BALANCE",
      message: "Your FreshMarket wallet balance is insufficient for full payment.",
    };
  }
  return {
    code: "CHECKOUT_FAILED",
    message: "Unable to complete wallet payment. Please try again or choose another payment method.",
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

    let userClient;
    let adminClient;
    try {
      userClient = createUserClient(authHeader);
      adminClient = createServiceClient();
    } catch {
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

    // 3. Atomically prepare order
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
      console.error("rpc_prepare_razorpay_order_atomic failed in wallet flow:", prepError);
      const mapped = mapErrorToResponse(prepError.message);
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

    const orderData = prepResult as {
      id: string;
      order_number: string;
      total: number;
      status: string;
      payment_status: string;
      is_idempotent_retry?: boolean;
    };

    // If order was already confirmed in an earlier call
    if (orderData.status === "confirmed" && orderData.payment_status === "completed") {
      return new Response(
        JSON.stringify({
          success: true,
          is_idempotent_retry: true,
          id: orderData.id,
          order_number: orderData.order_number,
          total: orderData.total,
          status: "confirmed",
          payment_status: "completed",
          payment_method: "wallet",
          is_wallet_only: true,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 4. Reserve wallet funds for this order
    const { data: reserveResult, error: reserveError } = await adminClient.rpc(
      "rpc_reserve_wallet_for_order_atomic",
      {
        p_user_id: user.id,
        p_order_id: orderData.id,
      }
    );

    if (reserveError) {
      console.error("rpc_reserve_wallet_for_order_atomic failed:", reserveError);
      // Compensate order on failure
      await adminClient.rpc("rpc_fail_razorpay_initialization_atomic", {
        p_order_id: orderData.id,
        p_reason: `Wallet reservation failed: ${reserveError.message}`,
      });
      const mapped = mapErrorToResponse(reserveError.message);
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

    const reserveData = reserveResult as {
      success: boolean;
      wallet_amount: number;
      gateway_amount: number;
      is_wallet_only: boolean;
    };

    // If wallet balance does not cover full order, reject pure wallet checkout
    if (!reserveData.is_wallet_only || reserveData.gateway_amount > 0) {
      await adminClient.rpc("rpc_fail_razorpay_initialization_atomic", {
        p_order_id: orderData.id,
        p_reason: "Insufficient wallet balance for wallet-only payment",
      });
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "INSUFFICIENT_WALLET_BALANCE",
          message: `Wallet balance (₹${reserveData.wallet_amount}) is less than order total (₹${orderData.total}). Please use mixed payment or another method.`,
          wallet_amount_available: reserveData.wallet_amount,
          remaining_amount: reserveData.gateway_amount,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 5. Confirm Wallet-Only Order
    const { data: confirmResult, error: confirmError } = await adminClient.rpc(
      "rpc_confirm_wallet_only_order_atomic",
      {
        p_user_id: user.id,
        p_order_id: orderData.id,
      }
    );

    if (confirmError) {
      console.error("rpc_confirm_wallet_only_order_atomic failed:", confirmError);
      await adminClient.rpc("rpc_fail_razorpay_initialization_atomic", {
        p_order_id: orderData.id,
        p_reason: `Wallet deduction failed: ${confirmError.message}`,
      });
      const mapped = mapErrorToResponse(confirmError.message);
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

    // 6. Clear Customer Cart
    const { data: userCart } = await adminClient
      .from("carts")
      .select("id")
      .eq("user_id", user.id)
      .maybeSingle();

    if (userCart) {
      await adminClient.from("cart_items").delete().eq("cart_id", userCart.id);
      await adminClient
        .from("carts")
        .update({ applied_coupon_id: null, updated_at: new Date().toISOString() })
        .eq("id", userCart.id);
    }

    return new Response(
      JSON.stringify({
        success: true,
        id: orderData.id,
        order_number: orderData.order_number,
        total: orderData.total,
        status: "confirmed",
        payment_status: "completed",
        payment_method: "wallet",
        wallet_amount_used: orderData.total,
        gateway_amount: 0.0,
        is_wallet_only: true,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled error in create-wallet-payment-order:", errorMsg);
    return new Response(
      JSON.stringify({
        success: false,
        error_code: "INTERNAL_ERROR",
        message: "An unexpected error occurred during wallet checkout.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
