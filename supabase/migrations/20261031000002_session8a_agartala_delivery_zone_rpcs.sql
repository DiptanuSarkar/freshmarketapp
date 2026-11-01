-- =============================================================================
-- Migration: 20261031000002_session8a_agartala_delivery_zone_rpcs.sql
-- Description: Session 8A — Forward update for commerce RPCs aligning schema column types
-- =============================================================================

-- 6. Updated rpc_calculate_checkout_quote with server geo-serviceability
CREATE OR REPLACE FUNCTION public.rpc_calculate_checkout_quote(
  p_user_id uuid,
  p_address_id uuid DEFAULT NULL,
  p_delivery_slot_id uuid DEFAULT NULL,
  p_coupon_code text DEFAULT NULL,
  p_use_wallet boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cart_id uuid;
  v_cart_applied_coupon_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_subtotal numeric(10,2) := 0.00;
  v_total_item_discount numeric(10,2) := 0.00;
  v_all_stock_valid boolean := true;
  v_has_items boolean := false;
  v_item_count int := 0;

  v_address record;
  v_service_area record;
  v_delivery_zone record;
  v_is_serviceable boolean := false;
  v_service_area_name text := NULL;
  v_delivery_fee numeric(10,2) := 0.00;
  v_min_order_for_free_delivery numeric(10,2) := 499.00;

  v_slot record;
  v_slot_valid boolean := false;

  v_target_coupon_code text := p_coupon_code;
  v_coupon record;
  v_applied_coupon_code text := NULL;
  v_coupon_applied boolean := false;
  v_coupon_discount numeric(10,2) := 0.00;
  v_coupon_message text := NULL;
  v_total_redemptions int := 0;
  v_user_redemptions int := 0;
  v_grand_total numeric(10,2) := 0.00;

  -- Wallet variables
  v_wallet record;
  v_wallet_balance numeric(10,2) := 0.00;
  v_wallet_reserved numeric(10,2) := 0.00;
  v_wallet_available numeric(10,2) := 0.00;
  v_wallet_amount_applied numeric(10,2) := 0.00;
  v_gateway_payable numeric(10,2) := 0.00;
BEGIN
  -- 1. Find customer cart
  SELECT id, applied_coupon_id INTO v_cart_id, v_cart_applied_coupon_id
  FROM public.carts
  WHERE user_id = p_user_id;

  IF v_cart_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'EMPTY_CART',
      'message', 'No active cart found for this customer.'
    );
  END IF;

  IF v_target_coupon_code IS NULL AND v_cart_applied_coupon_id IS NOT NULL THEN
    SELECT code INTO v_target_coupon_code
    FROM public.coupons
    WHERE id = v_cart_applied_coupon_id AND is_active = true;
  END IF;

  -- 2. Evaluate items in cart
  FOR v_item IN
    SELECT
      ci.id AS cart_item_id,
      ci.variant_id,
      ci.quantity,
      pv.product_id,
      pv.sku,
      pv.name AS variant_name,
      pv.weight,
      pv.price,
      pv.discounted_price,
      pv.is_active AS variant_active,
      p.name AS product_name,
      p.category_id,
      p.is_active AS product_active,
      COALESCE(inv.quantity_available, 0) AS quantity_available,
      COALESCE(inv.reserved_quantity, 0) AS reserved_quantity,
      COALESCE(
        (SELECT pi.image_url FROM public.product_images pi WHERE pi.product_id = p.id ORDER BY pi.display_order ASC LIMIT 1),
        'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80'
      ) AS image_url
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    LEFT JOIN public.inventory inv ON inv.variant_id = pv.id
    WHERE ci.cart_id = v_cart_id
  LOOP
    v_has_items := true;
    v_item_count := v_item_count + v_item.quantity;

    DECLARE
      v_effective_unit_price numeric(10,2);
      v_item_line_total numeric(10,2);
      v_sellable_stock int;
      v_is_item_stock_ok boolean;
      v_item_disc numeric(10,2) := 0.00;
    BEGIN
      v_effective_unit_price := COALESCE(v_item.discounted_price, v_item.price);
      v_item_line_total := ROUND(v_effective_unit_price * v_item.quantity, 2);
      IF v_item.discounted_price IS NOT NULL AND v_item.discounted_price < v_item.price THEN
        v_item_disc := ROUND((v_item.price - v_item.discounted_price) * v_item.quantity, 2);
      END IF;

      v_sellable_stock := GREATEST(0, v_item.quantity_available - v_item.reserved_quantity);
      v_is_item_stock_ok := (v_item.product_active AND v_item.variant_active AND v_sellable_stock >= v_item.quantity);

      IF NOT v_is_item_stock_ok THEN
        v_all_stock_valid := false;
      END IF;

      v_subtotal := v_subtotal + v_item_line_total;
      v_total_item_discount := v_total_item_discount + v_item_disc;

      v_items := v_items || jsonb_build_object(
        'cart_item_id', v_item.cart_item_id,
        'variant_id', v_item.variant_id,
        'product_id', v_item.product_id,
        'product_name', v_item.product_name,
        'variant_title', v_item.variant_name,
        'sku', v_item.sku,
        'weight', v_item.weight,
        'unit_price', v_effective_unit_price,
        'original_price', v_item.price,
        'quantity', v_item.quantity,
        'total_price', v_item_line_total,
        'image_url', v_item.image_url,
        'available_stock', v_sellable_stock,
        'is_stock_available', v_is_item_stock_ok
      );
    END;
  END LOOP;

  IF NOT v_has_items THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'EMPTY_CART',
      'message', 'Your cart is empty.'
    );
  END IF;

  -- 3. Address & Geo-Serviceability Validation
  IF p_address_id IS NOT NULL THEN
    SELECT * INTO v_address
    FROM public.addresses
    WHERE id = p_address_id AND user_id = p_user_id;

    IF v_address IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'ADDRESS_NOT_FOUND',
        'message', 'Selected delivery address does not exist or does not belong to customer.'
      );
    END IF;

    -- If map coordinates are present, evaluate against active Agartala delivery zone
    IF v_address.latitude IS NOT NULL AND v_address.longitude IS NOT NULL THEN
      IF v_address.latitude < -90.0 OR v_address.latitude > 90.0 OR v_address.longitude < -180.0 OR v_address.longitude > 180.0 THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'INVALID_COORDINATES',
          'message', 'Selected delivery address contains invalid geographical coordinates.'
        );
      END IF;

      SELECT 
        id, code, name, delivery_fee, free_delivery_threshold, minimum_order_amount
      INTO v_delivery_zone
      FROM public.delivery_zones
      WHERE is_active = true
        AND extensions.ST_Covers(boundary, extensions.ST_SetSRID(extensions.ST_MakePoint(v_address.longitude, v_address.latitude), 4326))
      LIMIT 1;

      IF v_delivery_zone.id IS NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'OUTSIDE_DELIVERY_ZONE',
          'message', 'FreshMarket currently delivers only within Agartala city.'
        );
      END IF;

      v_is_serviceable := true;
      v_service_area_name := v_delivery_zone.name;
      v_min_order_for_free_delivery := v_delivery_zone.free_delivery_threshold;

      IF v_subtotal >= v_delivery_zone.free_delivery_threshold THEN
        v_delivery_fee := 0.00;
      ELSE
        v_delivery_fee := v_delivery_zone.delivery_fee;
      END IF;
    ELSE
      -- Coordinates are absent: check legacy service_areas / PIN code
      SELECT * INTO v_service_area
      FROM public.service_areas
      WHERE pincode = v_address.pincode AND is_active = true;

      IF v_service_area IS NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'UNSUPPORTED_PINCODE',
          'message', 'We currently do not deliver to pincode ' || COALESCE(v_address.pincode, '') || '.'
        );
      END IF;

      -- Legacy PIN is active but coordinates are unverified -> prompt user to verify on map
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'ADDRESS_NOT_MAP_VERIFIED',
        'message', 'Please verify your delivery address on the map to confirm serviceability.'
      );
    END IF;
  END IF;

  -- 4. Delivery Slot Validation
  IF p_delivery_slot_id IS NOT NULL THEN
    SELECT * INTO v_slot
    FROM public.delivery_slots
    WHERE id = p_delivery_slot_id AND is_active = true;

    IF v_slot IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'DELIVERY_SLOT_UNAVAILABLE',
        'message', 'Selected delivery slot is inactive or unavailable.'
      );
    END IF;
    v_slot_valid := true;
  END IF;

  -- 5. Coupon Validation & Calculation
  IF v_target_coupon_code IS NOT NULL AND TRIM(v_target_coupon_code) <> '' THEN
    SELECT * INTO v_coupon
    FROM public.coupons
    WHERE UPPER(code) = UPPER(TRIM(v_target_coupon_code)) AND is_active = true;

    IF v_coupon IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'COUPON_INVALID',
        'message', 'Coupon code not found or inactive.'
      );
    END IF;

    IF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'COUPON_EXPIRED',
        'message', 'Coupon offer has not started yet.'
      );
    END IF;

    IF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'COUPON_EXPIRED',
        'message', 'Coupon offer has expired.'
      );
    END IF;

    IF v_subtotal < v_coupon.min_order_value THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'MINIMUM_ORDER_NOT_MET',
        'message', 'Minimum cart total of ₹' || v_coupon.min_order_value || ' required for this coupon.'
      );
    END IF;

    -- Usage limit check
    IF v_coupon.usage_limit IS NOT NULL THEN
      SELECT COUNT(*) INTO v_total_redemptions
      FROM public.coupon_redemptions
      WHERE coupon_id = v_coupon.id AND is_reversed = false;

      IF v_total_redemptions >= v_coupon.usage_limit THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'COUPON_USAGE_EXCEEDED',
          'message', 'Coupon maximum usage limit has been reached.'
        );
      END IF;
    END IF;

    -- Per-user limit check
    SELECT COUNT(*) INTO v_user_redemptions
    FROM public.coupon_redemptions
    WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false;

    IF v_user_redemptions >= v_coupon.usage_per_user THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'COUPON_USAGE_EXCEEDED',
        'message', 'You have already utilized this coupon offer.'
      );
    END IF;

    -- Target customer check
    IF NOT v_coupon.is_public THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.coupon_users
        WHERE coupon_id = v_coupon.id AND user_id = p_user_id
      ) THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'COUPON_INVALID',
          'message', 'This exclusive coupon is not applicable to your account.'
        );
      END IF;
    END IF;

    -- Category check
    IF EXISTS (SELECT 1 FROM public.coupon_categories WHERE coupon_id = v_coupon.id) THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.cart_items ci
        JOIN public.product_variants pv ON pv.id = ci.variant_id
        JOIN public.products p ON p.id = pv.product_id
        JOIN public.coupon_categories cc ON cc.category_id = p.category_id
        WHERE ci.cart_id = v_cart_id AND cc.coupon_id = v_coupon.id
      ) THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'COUPON_INVALID',
          'message', 'Coupon applies only to specific butcher categories not present in your cart.'
        );
      END IF;
    END IF;

    v_coupon_applied := true;
    v_applied_coupon_code := v_coupon.code;
    IF v_coupon.discount_type = 'percentage' THEN
      v_coupon_discount := ROUND((v_subtotal * v_coupon.discount_value / 100.0), 2);
      IF v_coupon.max_discount IS NOT NULL AND v_coupon_discount > v_coupon.max_discount THEN
        v_coupon_discount := v_coupon.max_discount;
      END IF;
    ELSE
      v_coupon_discount := LEAST(v_coupon.discount_value, v_subtotal);
    END IF;
    v_coupon_message := 'Coupon ' || v_coupon.code || ' applied successfully!';
  END IF;

  v_grand_total := GREATEST(0.00, ROUND(v_subtotal - v_coupon_discount + v_delivery_fee, 2));

  -- 6. Wallet Calculation
  SELECT balance, reserved_balance INTO v_wallet_balance, v_wallet_reserved
  FROM public.wallet_accounts
  WHERE user_id = p_user_id;

  IF v_wallet_balance IS NULL THEN
    v_wallet_balance := 0.00;
    v_wallet_reserved := 0.00;
  END IF;

  v_wallet_available := GREATEST(0.00, ROUND(v_wallet_balance - v_wallet_reserved, 2));

  IF p_use_wallet AND v_wallet_available > 0.00 THEN
    v_wallet_amount_applied := LEAST(v_wallet_available, v_grand_total);
    v_gateway_payable := GREATEST(0.00, ROUND(v_grand_total - v_wallet_amount_applied, 2));
  ELSE
    v_wallet_amount_applied := 0.00;
    v_gateway_payable := v_grand_total;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'cart_id', v_cart_id,
    'items', v_items,
    'item_count', v_item_count,
    'subtotal', v_subtotal,
    'item_discount', v_total_item_discount,
    'coupon_discount', v_coupon_discount,
    'coupon_code', v_applied_coupon_code,
    'coupon_applied', v_coupon_applied,
    'coupon_message', v_coupon_message,
    'delivery_fee', v_delivery_fee,
    'platform_fee', 0.00,
    'tax_amount', 0.00,
    'wallet_amount', v_wallet_amount_applied,
    'wallet_amount_applied', v_wallet_amount_applied,
    'wallet_balance', v_wallet_balance,
    'wallet_reserved', v_wallet_reserved,
    'wallet_available', v_wallet_available,
    'gateway_payable', v_gateway_payable,
    'grand_total', v_grand_total,
    'cod_payable_total', v_grand_total,
    'stock_valid', v_all_stock_valid,
    'serviceable', v_is_serviceable,
    'service_area_name', v_service_area_name,
    'min_order_for_free_delivery', v_min_order_for_free_delivery,
    'address_id', p_address_id,
    'delivery_slot_id', p_delivery_slot_id,
    'slot_valid', v_slot_valid,
    'is_wallet_only', (p_use_wallet AND v_gateway_payable = 0.00 AND v_grand_total > 0.00)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text, boolean) TO service_role;

-- 7. Updated rpc_create_cod_order_atomic with authoritative Agartala zone validation
CREATE OR REPLACE FUNCTION public.rpc_create_cod_order_atomic(
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
  v_existing_order jsonb;
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
BEGIN
  -- Step 1: Idempotency Check
  IF p_checkout_request_id IS NOT NULL THEN
    SELECT jsonb_build_object(
      'success', true,
      'is_idempotent_retry', true,
      'id', o.id,
      'order_number', o.order_number,
      'total', o.total,
      'subtotal', o.subtotal,
      'discount', o.discount,
      'delivery_fee', o.delivery_fee,
      'status', o.status,
      'payment_method', o.payment_method,
      'payment_status', o.payment_status,
      'delivery_address_snapshot', o.delivery_address_snapshot,
      'delivery_slot_snapshot', o.delivery_slot_snapshot,
      'created_at', o.created_at
    ) INTO v_existing_order
    FROM public.orders o
    WHERE o.user_id = p_user_id AND o.checkout_request_id = p_checkout_request_id;

    IF v_existing_order IS NOT NULL THEN
      RETURN v_existing_order;
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
    RAISE EXCEPTION 'EMPTY_CART: Cart has no items' USING ERRCODE = 'P0001';
  END IF;

  -- Step 3: Validate Address & Ownership
  SELECT * INTO v_address
  FROM public.addresses
  WHERE id = p_address_id AND user_id = p_user_id;

  IF v_address IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Selected address does not exist or belong to user' USING ERRCODE = 'P0002';
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
    'delivery_instructions', COALESCE(v_address.delivery_instructions, ''),
    'city', v_address.city,
    'state', v_address.state,
    'pincode', v_address.pincode,
    'latitude', v_address.latitude,
    'longitude', v_address.longitude
  );

  -- Step 5: Validate Delivery Slot & Snapshot
  SELECT * INTO v_slot
  FROM public.delivery_slots
  WHERE id = p_delivery_slot_id AND is_active = true;

  IF v_slot IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_SLOT_UNAVAILABLE: Selected delivery slot is inactive or not found' USING ERRCODE = 'P0004';
  END IF;

  v_slot_snapshot := jsonb_build_object(
    'id', v_slot.id,
    'name', v_slot.name,
    'start_time', v_slot.start_time::text,
    'end_time', v_slot.end_time::text
  );

  -- Step 6: Inventory Locking (SELECT ... FOR UPDATE)
  SELECT array_agg(variant_id) INTO v_variant_ids
  FROM public.cart_items
  WHERE cart_id = v_cart_id;

  PERFORM 1
  FROM public.inventory
  WHERE variant_id = ANY(v_variant_ids)
  FOR UPDATE;

  -- Step 7: Authoritative Stock & Pricing Revalidation
  FOR v_item IN
    SELECT
      ci.variant_id,
      ci.quantity,
      pv.product_id,
      pv.sku,
      pv.name AS variant_name,
      pv.weight,
      pv.price,
      pv.discounted_price,
      pv.is_active AS variant_active,
      p.name AS product_name,
      p.category_id,
      p.is_active AS product_active,
      COALESCE(inv.quantity_available, 0) AS quantity_available,
      COALESCE(inv.reserved_quantity, 0) AS reserved_quantity
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    LEFT JOIN public.inventory inv ON inv.variant_id = pv.id
    WHERE ci.cart_id = v_cart_id
  LOOP
    IF NOT v_item.product_active THEN
      RAISE EXCEPTION 'PRODUCT_UNAVAILABLE: Cut "%" is no longer available', v_item.product_name USING ERRCODE = 'P0005';
    END IF;

    IF NOT v_item.variant_active THEN
      RAISE EXCEPTION 'VARIANT_UNAVAILABLE: Variant "%" of "%" is unavailable', v_item.variant_name, v_item.product_name USING ERRCODE = 'P0005';
    END IF;

    IF (v_item.quantity_available - v_item.reserved_quantity) < v_item.quantity THEN
      RAISE EXCEPTION 'OUT_OF_STOCK: Insufficient stock for "%" (Requested %, available %)',
        v_item.product_name, v_item.quantity, GREATEST(0, v_item.quantity_available - v_item.reserved_quantity)
        USING ERRCODE = 'P0006';
    END IF;

    DECLARE
      v_effective_unit_price numeric(10,2);
      v_item_line_total numeric(10,2);
    BEGIN
      v_effective_unit_price := COALESCE(v_item.discounted_price, v_item.price);
      v_item_line_total := ROUND(v_effective_unit_price * v_item.quantity, 2);
      v_subtotal := v_subtotal + v_item_line_total;
      v_total_item_discount := v_total_item_discount + ROUND((v_item.price - v_effective_unit_price) * v_item.quantity, 2);
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

    IF v_coupon IS NULL THEN
      RAISE EXCEPTION 'COUPON_INVALID: Coupon code does not exist or has expired' USING ERRCODE = 'P0007';
    END IF;

    IF v_subtotal < v_coupon.min_order_value THEN
      RAISE EXCEPTION 'MINIMUM_ORDER_NOT_MET: Minimum order of ₹% required for coupon %', v_coupon.min_order_value, v_coupon.code USING ERRCODE = 'P0007';
    END IF;

    IF v_coupon.usage_limit IS NOT NULL THEN
      IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND is_reversed = false) >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: Global usage limit reached for coupon %', v_coupon.code USING ERRCODE = 'P0007';
      END IF;
    END IF;

    IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false) >= v_coupon.usage_per_user THEN
      RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: You have already redeemed coupon %', v_coupon.code USING ERRCODE = 'P0007';
    END IF;

    IF NOT v_coupon.is_public THEN
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

  -- Step 10: Generate Unique Order Number
  v_order_number := 'FM-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substring(gen_random_uuid()::text from 1 for 6));

  -- Step 11: Create Order Record
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
    'confirmed',
    v_grand_total,
    v_subtotal,
    v_coupon_discount,
    v_delivery_fee,
    'cod',
    'pending',
    p_address_id,
    p_delivery_slot_id,
    v_address_snapshot,
    v_slot_snapshot,
    p_customer_notes,
    p_checkout_request_id
  )
  RETURNING id INTO v_order_id;

  -- Step 12: Insert Order Items and Update Inventory
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

      UPDATE public.inventory
      SET quantity_available = quantity_available - v_item.quantity,
          updated_at = now()
      WHERE variant_id = v_item.variant_id;
    END;
  END LOOP;

  -- Step 13: Redeem Coupon
  IF v_coupon_id IS NOT NULL THEN
    INSERT INTO public.coupon_redemptions (
      coupon_id,
      user_id,
      order_id,
      discount_amount,
      is_reversed
    ) VALUES (
      v_coupon_id,
      p_user_id,
      v_order_id,
      v_coupon_discount,
      false
    );
  END IF;

  -- Step 14: Clear Cart Items
  DELETE FROM public.cart_items WHERE cart_id = v_cart_id;
  UPDATE public.carts SET applied_coupon_id = NULL, updated_at = now() WHERE id = v_cart_id;

  -- Step 15: Create Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes
  ) VALUES (
    v_order_id,
    'confirmed',
    'Order placed successfully via Cash on Delivery'
  );

  RETURN jsonb_build_object(
    'success', true,
    'is_idempotent_retry', false,
    'id', v_order_id,
    'order_number', v_order_number,
    'total', v_grand_total,
    'subtotal', v_subtotal,
    'discount', v_coupon_discount,
    'delivery_fee', v_delivery_fee,
    'status', 'confirmed',
    'payment_method', 'cod',
    'payment_status', 'pending',
    'delivery_address_snapshot', v_address_snapshot,
    'delivery_slot_snapshot', v_slot_snapshot,
    'created_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_create_cod_order_atomic(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_cod_order_atomic(uuid, uuid, uuid, uuid, text, text) TO service_role;

-- 8. Updated rpc_prepare_razorpay_order_atomic with authoritative Agartala zone validation
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
      IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND is_reversed = false) >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: Global usage limit reached for coupon %', v_coupon.code USING ERRCODE = 'P0007';
      END IF;
    END IF;

    IF (SELECT COUNT(*) FROM public.coupon_redemptions WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false) >= v_coupon.usage_per_user THEN
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

  -- Step 11: Create Order Record in payment_pending status
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
    'online',
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
    user_id,
    payment_method,
    amount,
    currency,
    status,
    provider,
    payment_attempt_no,
    expires_at
  ) VALUES (
    v_order_id,
    p_user_id,
    'online',
    v_grand_total,
    'INR',
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
