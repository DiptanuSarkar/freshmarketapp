-- =============================================================================
-- Migration: 20261007000003_fix_checkout_quote_unassigned_record_and_validations.sql
-- Description:
--   1. Hardens public.rpc_calculate_checkout_quote to prevent unassigned RECORD
--      runtime errors (ERROR 55000: record "v_coupon" is not assigned yet).
--   2. Adds strict validation error returns for:
--      - ADDRESS_NOT_FOUND (when provided address does not exist or belong to user)
--      - UNSUPPORTED_PINCODE (when address pincode has no active service area)
--      - DELIVERY_SLOT_UNAVAILABLE (when slot does not exist or is inactive)
--      - COUPON_INVALID / COUPON_EXPIRED / MINIMUM_ORDER_NOT_MET / COUPON_USAGE_EXCEEDED
--   3. Maintains least-privilege security definer grants (service_role only).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rpc_calculate_checkout_quote(
  p_user_id uuid,
  p_address_id uuid DEFAULT NULL,
  p_delivery_slot_id uuid DEFAULT NULL,
  p_coupon_code text DEFAULT NULL
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

  -- If no coupon code is explicitly passed, check cart's applied_coupon_id
  IF v_target_coupon_code IS NULL AND v_cart_applied_coupon_id IS NOT NULL THEN
    SELECT code INTO v_target_coupon_code
    FROM public.coupons
    WHERE id = v_cart_applied_coupon_id;
  END IF;

  -- 2. Inspect Cart Items with authoritative prices & stock
  FOR v_item IN
    SELECT
      ci.id AS cart_item_id,
      ci.quantity,
      pv.id AS variant_id,
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
      v_item_disc numeric(10,2);
      v_sellable_stock int;
      v_is_item_stock_ok boolean;
    BEGIN
      v_effective_unit_price := COALESCE(v_item.discounted_price, v_item.price);
      v_item_line_total := ROUND(v_effective_unit_price * v_item.quantity, 2);
      v_item_disc := ROUND((v_item.price - v_effective_unit_price) * v_item.quantity, 2);
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

  -- 3. Address & Serviceability Validation
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

    SELECT * INTO v_service_area
    FROM public.service_areas
    WHERE pincode = v_address.pincode AND is_active = true;

    IF v_service_area IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'UNSUPPORTED_PINCODE',
        'message', 'We currently do not deliver to pincode ' || v_address.pincode || '.'
      );
    END IF;

    v_is_serviceable := true;
    v_service_area_name := v_service_area.name;
    v_min_order_for_free_delivery := v_service_area.min_order_for_free_delivery;

    IF v_subtotal >= v_service_area.min_order_for_free_delivery THEN
      v_delivery_fee := 0.00;
    ELSE
      v_delivery_fee := v_service_area.delivery_charge;
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

    -- Check usage_limit
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

    -- Check usage_per_user
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

    -- Check targeted coupon restrictions
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

    -- Check category restrictions
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

    -- If valid, calculate discount
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
    'wallet_amount', 0.00,
    'grand_total', v_grand_total,
    'cod_payable_total', v_grand_total,
    'stock_valid', v_all_stock_valid,
    'serviceable', v_is_serviceable,
    'service_area_name', v_service_area_name,
    'min_order_for_free_delivery', v_min_order_for_free_delivery,
    'address_id', p_address_id,
    'delivery_slot_id', p_delivery_slot_id,
    'slot_valid', v_slot_valid
  );
END;
$$;

-- Security Grants: least-privilege, service_role only
REVOKE ALL ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text) TO service_role;
