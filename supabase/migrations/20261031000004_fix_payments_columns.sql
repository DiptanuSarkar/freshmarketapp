-- =============================================================================
-- Migration: 20261031000004_fix_payments_columns.sql
-- Description: Align payments table insert columns with actual schema
-- =============================================================================

-- 3. Updated rpc_prepare_razorpay_order_atomic with payment_method 'razorpay'
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
  v_delivery_zone record;
  v_address_snapshot jsonb;
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
  -- Step 1: Idempotency Check
  IF p_checkout_request_id IS NOT NULL THEN
    SELECT * INTO v_existing_order
    FROM public.orders
    WHERE user_id = p_user_id AND checkout_request_id = p_checkout_request_id;

    IF v_existing_order.id IS NOT NULL THEN
      SELECT * INTO v_existing_payment
      FROM public.payments
      WHERE order_id = v_existing_order.id AND status = 'pending'
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_existing_payment.id IS NOT NULL AND v_existing_payment.expires_at > now() THEN
        RETURN jsonb_build_object(
          'success', true,
          'is_idempotent_retry', true,
          'order_id', v_existing_order.id,
          'order_number', v_existing_order.order_number,
          'payment_id', v_existing_payment.id,
          'subtotal', v_existing_order.subtotal,
          'delivery_fee', v_existing_order.delivery_fee,
          'discount', v_existing_order.discount,
          'total', v_existing_order.total,
          'amount_in_paise', (v_existing_order.total * 100)::bigint,
          'currency', 'INR',
          'expires_at', v_existing_payment.expires_at,
          'delivery_address_snapshot', v_existing_order.delivery_address_snapshot,
          'delivery_slot_snapshot', v_existing_order.delivery_slot_snapshot,
          'created_at', v_existing_order.created_at
        );
      END IF;
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
  SELECT a.*
  INTO v_address
  FROM public.addresses a
  WHERE a.id = p_address_id AND a.user_id = p_user_id;

  IF v_address.id IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Delivery address does not exist or belong to user' USING ERRCODE = 'P0002';
  END IF;

  -- Step 4: Validate Map Coordinates & Agartala Delivery Zone
  IF v_address.latitude IS NULL OR v_address.longitude IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_MAP_VERIFIED: Delivery address has not been verified on map' USING ERRCODE = 'P0002';
  END IF;

  IF v_address.latitude < -90.0 OR v_address.latitude > 90.0 OR v_address.longitude < -180.0 OR v_address.longitude > 180.0 THEN
    RAISE EXCEPTION 'INVALID_COORDINATES: Coordinates outside valid geographical bounds' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_delivery_zone
  FROM public.delivery_zones
  WHERE is_active = true
    AND extensions.ST_Covers(boundary, extensions.ST_SetSRID(extensions.ST_MakePoint(v_address.longitude, v_address.latitude), 4326))
  LIMIT 1;

  IF v_delivery_zone.id IS NULL THEN
    RAISE EXCEPTION 'OUTSIDE_DELIVERY_ZONE: Delivery address is outside FreshMarket Agartala delivery zone' USING ERRCODE = 'P0003';
  END IF;

  -- Immutable Address Snapshot
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
    'delivery_instructions', COALESCE(v_address.delivery_instructions, ''),
    'latitude', v_address.latitude,
    'longitude', v_address.longitude
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

  -- Step 6: Lock Inventory Rows Deterministically
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
      pv.weight,
      pv.is_active AS variant_active,
      pv.price,
      pv.discounted_price,
      p.id AS product_id,
      p.category_id,
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

    IF (v_item.quantity_available - v_item.reserved_quantity) < v_item.quantity THEN
      RAISE EXCEPTION 'OUT_OF_STOCK: Insufficient stock for % (%). Available: %',
        v_item.product_name,
        v_item.variant_name,
        GREATEST(0, v_item.quantity_available - v_item.reserved_quantity)
      USING ERRCODE = 'P0006';
    END IF;

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

  -- Step 8: Calculate Delivery Fee from Authoritative Subtotal
  IF v_subtotal >= v_delivery_zone.free_delivery_threshold THEN
    v_delivery_fee := 0.00;
  ELSE
    v_delivery_fee := v_delivery_zone.delivery_fee;
  END IF;

  -- Step 9: Revalidate Coupon
  IF p_coupon_code IS NOT NULL AND TRIM(p_coupon_code) <> '' THEN
    SELECT * INTO v_coupon
    FROM public.coupons
    WHERE UPPER(code) = UPPER(TRIM(p_coupon_code))
      AND is_active = true
      AND (starts_at IS NULL OR starts_at <= now())
      AND (ends_at IS NULL OR ends_at >= now())
    FOR UPDATE;

    IF v_coupon.id IS NULL THEN
      RAISE EXCEPTION 'COUPON_INVALID: Coupon code does not exist or has expired' USING ERRCODE = 'P0007';
    END IF;

    IF v_subtotal < v_coupon.min_order_value THEN
      RAISE EXCEPTION 'MINIMUM_ORDER_NOT_MET: Minimum cart total of ₹% required for coupon %',
        v_coupon.min_order_value, v_coupon.code
      USING ERRCODE = 'P0007';
    END IF;

    IF v_coupon.usage_limit IS NOT NULL THEN
      IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id) >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: Global usage limit reached for coupon %', v_coupon.code USING ERRCODE = 'P0007';
      END IF;
    END IF;

    IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND user_id = p_user_id) >= v_coupon.usage_per_user THEN
      RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: You have already redeemed coupon %', v_coupon.code USING ERRCODE = 'P0007';
    END IF;

    IF v_coupon.is_public IS NOT TRUE THEN
      IF NOT EXISTS (SELECT 1 FROM public.coupon_users WHERE coupon_id = v_coupon.id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'COUPON_INVALID: Coupon % is not assigned to your account', v_coupon.code USING ERRCODE = 'P0007';
      END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM public.coupon_categories WHERE coupon_id = v_coupon.id) THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.cart_items ci
        JOIN public.product_variants pv ON pv.id = ci.variant_id
        JOIN public.products p ON p.id = pv.product_id
        JOIN public.coupon_categories cc ON cc.category_id = p.category_id
        WHERE ci.cart_id = v_cart_id AND cc.coupon_id = v_coupon.id
      ) THEN
        RAISE EXCEPTION 'COUPON_INVALID: Coupon % applies only to specific butcher categories', v_coupon.code USING ERRCODE = 'P0007';
      END IF;
    END IF;

    IF v_coupon.discount_type = 'percentage' THEN
      v_coupon_discount := ROUND((v_subtotal * v_coupon.discount_value / 100.0), 2);
      IF v_coupon.max_discount IS NOT NULL AND v_coupon_discount > v_coupon.max_discount THEN
        v_coupon_discount := v_coupon.max_discount;
      END IF;
    ELSE
      v_coupon_discount := LEAST(v_coupon.discount_value, v_subtotal);
    END IF;

    v_coupon_id := v_coupon.id;
  END IF;

  v_grand_total := GREATEST(0.00, ROUND(v_subtotal - v_coupon_discount + v_delivery_fee, 2));

  -- Step 10: Reserve Inventory
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
    UPDATE public.inventory
    SET reserved_quantity = reserved_quantity + v_item.quantity,
        updated_at = now()
    WHERE variant_id = v_item.variant_id;
  END LOOP;

  -- Step 11: Create Order Record in payment_pending status with payment_method 'razorpay'
  v_order_number := 'FM-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substring(gen_random_uuid()::text from 1 for 6));

  INSERT INTO public.orders (
    user_id,
    order_number,
    status,
    total,
    subtotal,
    discount,
    delivery_fee,
    payment_method,
    payment_status,
    delivery_address_id,
    delivery_slot_id,
    delivery_address_snapshot,
    delivery_slot_snapshot,
    customer_notes,
    checkout_request_id
  ) VALUES (
    p_user_id,
    v_order_number,
    'payment_pending',
    v_grand_total,
    v_subtotal,
    v_coupon_discount,
    v_delivery_fee,
    'razorpay',
    'pending',
    p_address_id,
    p_delivery_slot_id,
    v_address_snapshot,
    v_slot_snapshot,
    p_customer_notes,
    p_checkout_request_id
  )
  RETURNING id INTO v_order_id;

  -- Step 12: Insert Order Items
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
    END;
  END LOOP;

  -- Step 13: Create Initial Payment Record
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
  )
  RETURNING id INTO v_payment_id;

  -- Step 14: Log Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes
  ) VALUES (
    v_order_id,
    'payment_pending',
    'Order initialized for online payment. Awaiting payment authorization.'
  );

  -- Step 15: Return Payload
  RETURN jsonb_build_object(
    'success', true,
    'is_idempotent_retry', false,
    'order_id', v_order_id,
    'order_number', v_order_number,
    'payment_id', v_payment_id,
    'subtotal', v_subtotal,
    'delivery_fee', v_delivery_fee,
    'discount', v_coupon_discount,
    'total', v_grand_total,
    'amount_in_paise', (v_grand_total * 100)::bigint,
    'currency', 'INR',
    'expires_at', v_expires_at,
    'delivery_address_snapshot', v_address_snapshot,
    'delivery_slot_snapshot', v_slot_snapshot,
    'created_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) TO service_role;
