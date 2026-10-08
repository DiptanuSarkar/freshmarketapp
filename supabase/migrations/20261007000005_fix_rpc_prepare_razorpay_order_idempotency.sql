-- =============================================================================
-- Migration: 20261007000005_fix_rpc_prepare_razorpay_order_idempotency.sql
-- Description: Fixes record nullity check in rpc_prepare_razorpay_order_atomic
--              using 'IF FOUND THEN' instead of 'IF record IS NOT NULL'
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_prepare_razorpay_order_atomic(
  p_user_id uuid,
  p_checkout_request_id uuid,
  p_address_id uuid,
  p_delivery_slot_id uuid,
  p_coupon_code text DEFAULT NULL,
  p_customer_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_existing_order record;
  v_existing_payment record;
  v_cart_id uuid;
  v_address record;
  v_address_snapshot jsonb;
  v_service_area record;
  v_delivery_fee numeric(10,2) := 0.00;
  v_slot record;
  v_slot_snapshot jsonb;

  v_variant_ids uuid[];
  v_item record;
  v_subtotal numeric(10,2) := 0.00;
  v_total_item_discount numeric(10,2) := 0.00;
  v_coupon record;
  v_coupon_discount numeric(10,2) := 0.00;
  v_coupon_id uuid := NULL;
  v_grand_total numeric(10,2) := 0.00;

  v_order_id uuid;
  v_order_number text;
  v_payment_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Step 1: Idempotency Check (Duplicate request returns existing order/payment)
  IF p_checkout_request_id IS NOT NULL THEN
    SELECT * INTO v_existing_order
    FROM public.orders
    WHERE user_id = p_user_id AND checkout_request_id = p_checkout_request_id;

    IF FOUND THEN
      -- If order is already completed/confirmed or payment_pending
      SELECT * INTO v_existing_payment
      FROM public.payments
      WHERE order_id = v_existing_order.id
      ORDER BY created_at DESC
      LIMIT 1;

      RETURN jsonb_build_object(
        'success', true,
        'is_idempotent_retry', true,
        'id', v_existing_order.id,
        'order_number', v_existing_order.order_number,
        'total', v_existing_order.total,
        'subtotal', v_existing_order.subtotal,
        'discount', v_existing_order.discount,
        'delivery_fee', v_existing_order.delivery_fee,
        'status', v_existing_order.status,
        'payment_method', v_existing_order.payment_method,
        'payment_status', v_existing_order.payment_status,
        'payment_id', v_existing_payment.id,
        'gateway_order_id', v_existing_payment.gateway_order_id,
        'amount_paise', (ROUND(v_existing_order.total * 100))::bigint,
        'currency', 'INR',
        'expires_at', v_existing_payment.expires_at,
        'delivery_address_snapshot', v_existing_order.delivery_address_snapshot,
        'delivery_slot_snapshot', v_existing_order.delivery_slot_snapshot,
        'created_at', v_existing_order.created_at
      );
    END IF;
  END IF;

  -- Step 2: Validate Cart Exists and is not empty
  SELECT id INTO v_cart_id
  FROM public.carts
  WHERE user_id = p_user_id;

  IF v_cart_id IS NULL THEN
    RAISE EXCEPTION 'EMPTY_CART: No active cart found' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE cart_id = v_cart_id) THEN
    RAISE EXCEPTION 'EMPTY_CART: Cart contains no items' USING ERRCODE = 'P0001';
  END IF;

  -- Step 3: Validate Customer Address & Ownership
  SELECT a.*, sa.id AS service_area_id, sa.is_active AS sa_active
  INTO v_address
  FROM public.addresses a
  LEFT JOIN public.service_areas sa ON sa.pincode = a.pincode
  WHERE a.id = p_address_id AND a.user_id = p_user_id;

  IF v_address.id IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Delivery address does not exist or belong to user' USING ERRCODE = 'P0002';
  END IF;

  -- Step 4: Validate Service Area
  IF v_address.service_area_id IS NULL OR v_address.sa_active IS NOT TRUE THEN
    RAISE EXCEPTION 'UNSUPPORTED_PINCODE: Address pincode is not serviceable' USING ERRCODE = 'P0003';
  END IF;

  SELECT * INTO v_service_area
  FROM public.service_areas
  WHERE id = v_address.service_area_id;

  -- Build immutable address snapshot
  v_address_snapshot := jsonb_build_object(
    'id', v_address.id,
    'label', v_address.label,
    'recipient_name', v_address.recipient_name,
    'phone', v_address.phone,
    'address_line1', v_address.address_line1,
    'address_line2', COALESCE(v_address.address_line2, ''),
    'landmark', COALESCE(v_address.landmark, ''),
    'city', v_address.city,
    'state', v_address.state,
    'pincode', v_address.pincode,
    'delivery_instructions', COALESCE(v_address.delivery_instructions, '')
  );

  -- Step 5: Validate Delivery Slot
  SELECT * INTO v_slot
  FROM public.delivery_slots
  WHERE id = p_delivery_slot_id AND is_active = true;

  IF v_slot.id IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_SLOT_UNAVAILABLE: Selected delivery slot is invalid or inactive' USING ERRCODE = 'P0004';
  END IF;

  v_slot_snapshot := jsonb_build_object(
    'id', v_slot.id,
    'name', v_slot.name,
    'start_time', v_slot.start_time,
    'end_time', v_slot.end_time
  );

  -- Step 6: Lock Inventory Rows Deterministically (Sorted by variant_id to avoid deadlocks)
  SELECT array_agg(ci.variant_id ORDER BY ci.variant_id)
  INTO v_variant_ids
  FROM public.cart_items ci
  WHERE ci.cart_id = v_cart_id;

  PERFORM 1
  FROM public.inventory inv
  WHERE inv.variant_id = ANY(v_variant_ids)
  ORDER BY inv.variant_id
  FOR UPDATE;

  -- Step 7: Validate Stock & Active Status for Each Item
  FOR v_item IN
    SELECT
      ci.variant_id,
      ci.quantity,
      pv.sku,
      pv.name AS variant_name,
      pv.is_active AS variant_active,
      pv.price,
      pv.discounted_price,
      p.id AS product_id,
      p.name AS product_name,
      p.is_active AS product_active,
      inv.quantity_available,
      inv.reserved_quantity
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    JOIN public.inventory inv ON inv.variant_id = ci.variant_id
    WHERE ci.cart_id = v_cart_id
  LOOP
    IF v_item.product_active IS NOT TRUE THEN
      RAISE EXCEPTION 'PRODUCT_UNAVAILABLE: Product % is currently inactive', v_item.product_name USING ERRCODE = 'P0005';
    END IF;

    IF v_item.variant_active IS NOT TRUE THEN
      RAISE EXCEPTION 'VARIANT_UNAVAILABLE: Variant % is currently inactive', v_item.variant_name USING ERRCODE = 'P0005';
    END IF;

    -- Invariant: Sellable stock = quantity_available - reserved_quantity
    IF (v_item.quantity_available - v_item.reserved_quantity) < v_item.quantity THEN
      RAISE EXCEPTION 'OUT_OF_STOCK: Insufficient stock for % (%). Available: %',
        v_item.product_name,
        v_item.variant_name,
        GREATEST(0, v_item.quantity_available - v_item.reserved_quantity)
      USING ERRCODE = 'P0006';
    END IF;

    -- Calculate line subtotal
    DECLARE
      v_effective_price numeric(10,2);
    BEGIN
      v_effective_price := COALESCE(v_item.discounted_price, v_item.price);
      v_subtotal := v_subtotal + ROUND(v_effective_price * v_item.quantity, 2);
      IF v_item.discounted_price IS NOT NULL AND v_item.discounted_price < v_item.price THEN
        v_total_item_discount := v_total_item_discount + ROUND((v_item.price - v_item.discounted_price) * v_item.quantity, 2);
      END IF;
    END;
  END LOOP;

  -- Step 8: Calculate Delivery Fee
  IF v_subtotal >= v_service_area.min_order_for_free_delivery THEN
    v_delivery_fee := 0.00;
  ELSE
    v_delivery_fee := v_service_area.delivery_charge;
  END IF;

  -- Step 9: Revalidate Coupon Inside Transaction
  IF p_coupon_code IS NOT NULL AND TRIM(p_coupon_code) <> '' THEN
    SELECT * INTO v_coupon
    FROM public.coupons
    WHERE UPPER(code) = UPPER(TRIM(p_coupon_code)) AND is_active = true
    FOR UPDATE;

    IF v_coupon IS NULL THEN
      RAISE EXCEPTION 'COUPON_INVALID: Coupon code does not exist or is inactive' USING ERRCODE = 'P0007';
    END IF;

    IF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN
      RAISE EXCEPTION 'COUPON_EXPIRED: Coupon is not yet active' USING ERRCODE = 'P0008';
    END IF;

    IF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN
      RAISE EXCEPTION 'COUPON_EXPIRED: Coupon offer has expired' USING ERRCODE = 'P0008';
    END IF;

    IF v_subtotal < v_coupon.min_order_value THEN
      RAISE EXCEPTION 'MINIMUM_ORDER_NOT_MET: Minimum order of ₹% required for coupon %', v_coupon.min_order_value, v_coupon.code USING ERRCODE = 'P0009';
    END IF;

    -- Total usage limit check
    IF v_coupon.usage_limit IS NOT NULL THEN
      DECLARE
        v_total_redemptions int;
      BEGIN
        SELECT COUNT(*) INTO v_total_redemptions
        FROM public.coupon_redemptions
        WHERE coupon_id = v_coupon.id AND is_reversed = false;

        IF v_total_redemptions >= v_coupon.usage_limit THEN
          RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: Coupon total usage limit reached' USING ERRCODE = 'P0010';
        END IF;
      END;
    END IF;

    -- Per-customer usage limit check
    IF v_coupon.per_user_limit IS NOT NULL THEN
      DECLARE
        v_user_redemptions int;
      BEGIN
        SELECT COUNT(*) INTO v_user_redemptions
        FROM public.coupon_redemptions
        WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false;

        IF v_user_redemptions >= v_coupon.per_user_limit THEN
          RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: You have already redeemed coupon % maximum allowed times', v_coupon.code USING ERRCODE = 'P0010';
        END IF;
      END;
    END IF;

    -- Compute coupon discount
    IF v_coupon.discount_type = 'percentage' THEN
      v_coupon_discount := ROUND((v_subtotal * v_coupon.discount_value) / 100.0, 2);
      IF v_coupon.max_discount_amount IS NOT NULL AND v_coupon_discount > v_coupon.max_discount_amount THEN
        v_coupon_discount := v_coupon.max_discount_amount;
      END IF;
    ELSIF v_coupon.discount_type = 'flat' THEN
      v_coupon_discount := LEAST(v_coupon.discount_value, v_subtotal);
    END IF;

    v_coupon_id := v_coupon.id;
  END IF;

  -- Grand Total calculation
  v_grand_total := GREATEST(0.00, v_subtotal - v_coupon_discount) + v_delivery_fee;

  -- Step 10: Insert Pending Online Order (status = payment_pending)
  INSERT INTO public.orders (
    user_id,
    delivery_address_id,
    delivery_address_snapshot,
    delivery_slot_id,
    delivery_slot_snapshot,
    delivery_date,
    status,
    subtotal,
    discount,
    delivery_fee,
    packaging_fee,
    total,
    payment_method,
    payment_status,
    customer_notes,
    checkout_request_id
  ) VALUES (
    p_user_id,
    v_address.id,
    v_address_snapshot,
    v_slot.id,
    v_slot_snapshot,
    CURRENT_DATE,
    'payment_pending',
    v_subtotal,
    v_coupon_discount,
    v_delivery_fee,
    0.00,
    v_grand_total,
    'razorpay',
    'pending',
    p_customer_notes,
    p_checkout_request_id
  ) RETURNING id, order_number INTO v_order_id, v_order_number;

  -- Step 11: Insert Order Items & Reserve Inventory
  FOR v_item IN
    SELECT
      ci.variant_id,
      ci.quantity,
      pv.sku,
      pv.name AS variant_name,
      pv.weight,
      pv.price,
      pv.discounted_price,
      p.name AS product_name
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE ci.cart_id = v_cart_id
  LOOP
    DECLARE
      v_effective_price numeric(10,2);
      v_line_total numeric(10,2);
    BEGIN
      v_effective_price := COALESCE(v_item.discounted_price, v_item.price);
      v_line_total := ROUND(v_effective_price * v_item.quantity, 2);

      INSERT INTO public.order_items (
        order_id,
        variant_id,
        sku,
        product_name,
        variant_name,
        weight,
        price,
        quantity,
        total_price
      ) VALUES (
        v_order_id,
        v_item.variant_id,
        v_item.sku,
        v_item.product_name,
        v_item.variant_name,
        v_item.weight,
        v_effective_price,
        v_item.quantity,
        v_line_total
      );

      -- Atomic Inventory Reservation
      UPDATE public.inventory
      SET reserved_quantity = reserved_quantity + v_item.quantity,
          updated_at = now()
      WHERE variant_id = v_item.variant_id;

      -- Stock Movement Log
      INSERT INTO public.stock_movements (
        variant_id,
        quantity_changed,
        movement_type,
        reference_id
      ) VALUES (
        v_item.variant_id,
        v_item.quantity,
        'reservation',
        v_order_id
      );
    END;
  END LOOP;

  -- Step 12: Record Coupon Redemption (Reserved with order)
  IF v_coupon_id IS NOT NULL THEN
    INSERT INTO public.coupon_redemptions (
      coupon_id,
      user_id,
      order_id,
      discount_applied
    ) VALUES (
      v_coupon_id,
      p_user_id,
      v_order_id,
      v_coupon_discount
    );
  END IF;

  -- Step 13: Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    v_order_id,
    'payment_pending',
    'Awaiting online payment via Razorpay',
    p_user_id
  );

  -- Step 14: Payment Record (Pending with 15 minute expiry)
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO public.payments (
    order_id,
    payment_method,
    amount,
    status,
    provider,
    payment_attempt_no,
    expires_at
  ) VALUES (
    v_order_id,
    'razorpay',
    v_grand_total,
    'pending',
    'razorpay',
    1,
    v_expires_at
  ) RETURNING id INTO v_payment_id;

  -- Step 15: Return Complete Preparation Details
  RETURN jsonb_build_object(
    'success', true,
    'id', v_order_id,
    'order_number', v_order_number,
    'payment_id', v_payment_id,
    'total', v_grand_total,
    'subtotal', v_subtotal,
    'discount', v_coupon_discount,
    'delivery_fee', v_delivery_fee,
    'amount_paise', (ROUND(v_grand_total * 100))::bigint,
    'currency', 'INR',
    'status', 'payment_pending',
    'payment_method', 'razorpay',
    'payment_status', 'pending',
    'expires_at', v_expires_at,
    'delivery_address_snapshot', v_address_snapshot,
    'delivery_slot_snapshot', v_slot_snapshot,
    'created_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) TO service_role;
