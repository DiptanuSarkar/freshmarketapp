-- =============================================================================
-- Migration: 20261007000001_session4_secure_checkout_and_order_lifecycle.sql
-- Description: Session 4 Forward-Only Secure Checkout, COD Order Creation,
--   Inventory Reservation, and Cancellation Lifecycle
--   1. Add checkout_request_id and SKU snapshot column with indexes
--   2. Add is_reversed and reversed_at columns to coupon_redemptions
--   3. Authoritative server functions:
--      - rpc_calculate_checkout_quote
--      - rpc_create_cod_order_atomic
--      - rpc_cancel_order_atomic
--   4. Least-privilege function execution grants (service_role only)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SCHEMA EXTENSIONS FOR IDEMPOTENCY & AUDIT
-- -----------------------------------------------------------------------------

-- Add checkout_request_id for idempotency on orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS checkout_request_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_user_checkout_request_id_key'
  ) THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_user_checkout_request_id_key UNIQUE (user_id, checkout_request_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_checkout_request_id ON public.orders (checkout_request_id);

-- Add sku snapshot to order_items if not present
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS sku text;

-- Add auditable reversal fields to coupon_redemptions
ALTER TABLE public.coupon_redemptions ADD COLUMN IF NOT EXISTS is_reversed boolean NOT NULL DEFAULT false;
ALTER TABLE public.coupon_redemptions ADD COLUMN IF NOT EXISTS reversed_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_active ON public.coupon_redemptions (coupon_id, user_id, is_reversed);

-- -----------------------------------------------------------------------------
-- 2. SERVER-AUTHORITATIVE CHECKOUT QUOTE FUNCTION
-- -----------------------------------------------------------------------------
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

    IF v_address IS NOT NULL THEN
      SELECT * INTO v_service_area
      FROM public.service_areas
      WHERE pincode = v_address.pincode AND is_active = true;

      IF v_service_area IS NOT NULL THEN
        v_is_serviceable := true;
        v_service_area_name := v_service_area.name;
        v_min_order_for_free_delivery := v_service_area.min_order_for_free_delivery;

        IF v_subtotal >= v_service_area.min_order_for_free_delivery THEN
          v_delivery_fee := 0.00;
        ELSE
          v_delivery_fee := v_service_area.delivery_charge;
        END IF;
      END IF;
    END IF;
  END IF;

  -- 4. Delivery Slot Validation
  IF p_delivery_slot_id IS NOT NULL THEN
    SELECT * INTO v_slot
    FROM public.delivery_slots
    WHERE id = p_delivery_slot_id AND is_active = true;

    IF v_slot IS NOT NULL THEN
      v_slot_valid := true;
    END IF;
  END IF;

  -- 5. Coupon Validation & Calculation
  IF v_target_coupon_code IS NOT NULL AND TRIM(v_target_coupon_code) <> '' THEN
    SELECT * INTO v_coupon
    FROM public.coupons
    WHERE UPPER(code) = UPPER(TRIM(v_target_coupon_code)) AND is_active = true;

    IF v_coupon IS NULL THEN
      v_coupon_message := 'Coupon code not found or inactive.';
    ELSIF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN
      v_coupon_message := 'Coupon offer has not started yet.';
    ELSIF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN
      v_coupon_message := 'Coupon offer has expired.';
    ELSIF v_subtotal < v_coupon.min_order_value THEN
      v_coupon_message := 'Minimum cart total of ₹' || v_coupon.min_order_value || ' required for this coupon.';
    ELSE
      -- Check usage_limit
      IF v_coupon.usage_limit IS NOT NULL THEN
        SELECT COUNT(*) INTO v_total_redemptions
        FROM public.coupon_redemptions
        WHERE coupon_id = v_coupon.id AND is_reversed = false;

        IF v_total_redemptions >= v_coupon.usage_limit THEN
          v_coupon_message := 'Coupon maximum usage limit has been reached.';
        END IF;
      END IF;

      -- Check usage_per_user
      IF v_coupon_message IS NULL THEN
        SELECT COUNT(*) INTO v_user_redemptions
        FROM public.coupon_redemptions
        WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false;

        IF v_user_redemptions >= v_coupon.usage_per_user THEN
          v_coupon_message := 'You have already utilized this coupon offer.';
        END IF;
      END IF;

      -- Check targeted coupon restrictions
      IF v_coupon_message IS NULL AND NOT v_coupon.is_public THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.coupon_users
          WHERE coupon_id = v_coupon.id AND user_id = p_user_id
        ) THEN
          v_coupon_message := 'This exclusive coupon is not applicable to your account.';
        END IF;
      END IF;

      -- Check category restrictions
      IF v_coupon_message IS NULL AND EXISTS (SELECT 1 FROM public.coupon_categories WHERE coupon_id = v_coupon.id) THEN
        IF NOT EXISTS (
          SELECT 1
          FROM public.cart_items ci
          JOIN public.product_variants pv ON pv.id = ci.variant_id
          JOIN public.products p ON p.id = pv.product_id
          JOIN public.coupon_categories cc ON cc.category_id = p.category_id
          WHERE ci.cart_id = v_cart_id AND cc.coupon_id = v_coupon.id
        ) THEN
          v_coupon_message := 'Coupon applies only to specific butcher categories not present in your cart.';
        END IF;
      END IF;

      -- If valid, calculate discount
      IF v_coupon_message IS NULL THEN
        v_coupon_applied := true;
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
    END IF;
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
    'coupon_code', CASE WHEN v_coupon_applied THEN v_coupon.code ELSE NULL END,
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

-- -----------------------------------------------------------------------------
-- 3. SERVER-AUTHORITATIVE ATOMIC COD ORDER CREATION FUNCTION
-- -----------------------------------------------------------------------------
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
BEGIN
  -- Step 1: Idempotency Check (Duplicate request returns existing order)
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

  -- Step 3: Validate Address & Snapshot
  SELECT * INTO v_address
  FROM public.addresses
  WHERE id = p_address_id AND user_id = p_user_id;

  IF v_address IS NULL THEN
    RAISE EXCEPTION 'ADDRESS_NOT_FOUND: Selected address does not exist or belong to user' USING ERRCODE = 'P0002';
  END IF;

  IF v_address.pincode IS NULL OR TRIM(v_address.pincode) = '' THEN
    RAISE EXCEPTION 'ADDRESS_INVALID: Address is missing PIN code' USING ERRCODE = 'P0002';
  END IF;

  -- Step 4: Validate Service Area & Delivery Fee
  SELECT * INTO v_service_area
  FROM public.service_areas
  WHERE pincode = v_address.pincode AND is_active = true;

  IF v_service_area IS NULL THEN
    RAISE EXCEPTION 'AREA_NOT_SERVICEABLE: FreshMarket does not deliver to PIN %', v_address.pincode USING ERRCODE = 'P0003';
  END IF;

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
    'pincode', v_address.pincode
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

    -- Strict sellable inventory check
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

    -- Per-user usage limit check
    DECLARE
      v_user_redemptions int;
    BEGIN
      SELECT COUNT(*) INTO v_user_redemptions
      FROM public.coupon_redemptions
      WHERE coupon_id = v_coupon.id AND user_id = p_user_id AND is_reversed = false;

      IF v_user_redemptions >= v_coupon.usage_per_user THEN
        RAISE EXCEPTION 'COUPON_USAGE_EXCEEDED: You have already used this coupon' USING ERRCODE = 'P0010';
      END IF;
    END;

    -- Category restrictions
    IF EXISTS (SELECT 1 FROM public.coupon_categories WHERE coupon_id = v_coupon.id) THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.cart_items ci
        JOIN public.product_variants pv ON pv.id = ci.variant_id
        JOIN public.products p ON p.id = pv.product_id
        JOIN public.coupon_categories cc ON cc.category_id = p.category_id
        WHERE ci.cart_id = v_cart_id AND cc.coupon_id = v_coupon.id
      ) THEN
        RAISE EXCEPTION 'COUPON_INVALID: Coupon does not apply to any items in cart' USING ERRCODE = 'P0007';
      END IF;
    END IF;

    -- Calculate coupon discount
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

  -- Step 10: Insert Order Record
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
    'placed',
    v_subtotal,
    v_coupon_discount,
    v_delivery_fee,
    0.00,
    v_grand_total,
    'cod',
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

      -- Snapshot item into order_items
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

  -- Step 12: Record Coupon Redemption (if coupon applied)
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
    'placed',
    'Order placed successfully with Cash on Delivery (COD)',
    p_user_id
  );

  -- Step 14: Payment Record (COD Pending)
  INSERT INTO public.payments (
    order_id,
    payment_method,
    amount,
    status
  ) VALUES (
    v_order_id,
    'cod',
    v_grand_total,
    'pending'
  );

  -- Step 15: Clear Successful Cart
  DELETE FROM public.cart_items WHERE cart_id = v_cart_id;
  UPDATE public.carts
  SET applied_coupon_id = NULL,
      updated_at = now()
  WHERE id = v_cart_id;

  -- Step 16: Return Complete Order Payload
  RETURN jsonb_build_object(
    'success', true,
    'id', v_order_id,
    'order_number', v_order_number,
    'total', v_grand_total,
    'subtotal', v_subtotal,
    'discount', v_coupon_discount,
    'delivery_fee', v_delivery_fee,
    'status', 'placed',
    'payment_method', 'COD',
    'payment_status', 'pending',
    'delivery_address_snapshot', v_address_snapshot,
    'delivery_slot_snapshot', v_slot_snapshot,
    'created_at', now()
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. SERVER-AUTHORITATIVE ORDER CANCELLATION FUNCTION
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_cancel_order_atomic(
  p_user_id uuid,
  p_order_id uuid,
  p_reason text DEFAULT 'Customer requested cancellation'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_item record;
BEGIN
  -- 1. Verify order belongs to customer
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist or does not belong to user' USING ERRCODE = 'P0011';
  END IF;

  -- 2. Idempotency: If already cancelled, return cleanly
  IF v_order.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_cancelled', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'cancelled',
      'cancelled_reason', v_order.cancelled_reason
    );
  END IF;

  -- 3. Check Cancellation Eligibility (Only 'placed' or 'confirmed')
  IF v_order.status NOT IN ('placed', 'confirmed') THEN
    RAISE EXCEPTION 'ORDER_NOT_CANCELLABLE: Orders in "%" stage cannot be cancelled by customer', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 4. Lock & Release Inventory Reservations
  FOR v_item IN
    SELECT variant_id, quantity
    FROM public.order_items
    WHERE order_id = p_order_id
  LOOP
    UPDATE public.inventory
    SET reserved_quantity = GREATEST(0, reserved_quantity - v_item.quantity),
        updated_at = now()
    WHERE variant_id = v_item.variant_id;

    INSERT INTO public.stock_movements (
      variant_id,
      quantity_changed,
      movement_type,
      reference_id
    ) VALUES (
      v_item.variant_id,
      -v_item.quantity,
      'reservation_release',
      p_order_id
    );
  END LOOP;

  -- 5. Reverse Coupon Redemption (preserve audit history, allow reuse)
  UPDATE public.coupon_redemptions
  SET is_reversed = true,
      reversed_at = now()
  WHERE order_id = p_order_id AND is_reversed = false;

  -- 6. Update COD Payment Record
  UPDATE public.payments
  SET status = 'failed',
      updated_at = now()
  WHERE order_id = p_order_id AND status = 'pending';

  -- 7. Update Order Status
  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_reason = p_reason,
      updated_at = now()
  WHERE id = p_order_id;

  -- 8. Record Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'cancelled',
    COALESCE(p_reason, 'Order cancelled by customer'),
    p_user_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', 'cancelled',
    'cancelled_reason', p_reason
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. LEAST-PRIVILEGE SECURITY GRANTS (SERVICE ROLE ONLY)
-- -----------------------------------------------------------------------------
-- Ensure anon and authenticated roles have zero direct execution rights on these RPCs.
-- Only the trusted Supabase Edge Function (running with service_role) can execute them.
REVOKE ALL ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_create_cod_order_atomic(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_cod_order_atomic(uuid, uuid, uuid, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) TO service_role;
