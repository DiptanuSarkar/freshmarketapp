-- =============================================================================
-- Migration: 20261007000004_session5a_razorpay_payment_engine.sql
-- Description: Session 5A Razorpay Test-Mode Payment Engine, Webhook Idempotency,
--   Payment Verification, Retry, and Expiry Engine.
--   1. Enum updates: 'payment_pending' in order_status, 'razorpay' in payment_method,
--      'authorized' in payment_status.
--   2. Payments table hardening: gateway error fields, attempts, expiry, timestamps.
--   3. Webhook idempotency table: public.payment_webhook_events with RLS.
--   4. Privileged Server-Authoritative RPCs:
--      - rpc_prepare_razorpay_order_atomic
--      - rpc_set_payment_gateway_order
--      - rpc_fail_razorpay_initialization_atomic
--      - rpc_confirm_razorpay_payment_atomic
--      - rpc_record_razorpay_payment_failure_atomic
--      - rpc_prepare_razorpay_retry_atomic
--      - rpc_expire_pending_razorpay_orders
--   5. Least-privilege function execution grants (service_role only).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUM UPDATES
-- -----------------------------------------------------------------------------

-- Add 'payment_pending' to order_status enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.order_status'::regtype
      AND enumlabel = 'payment_pending'
  ) THEN
    ALTER TYPE public.order_status ADD VALUE 'payment_pending';
  END IF;
END $$;

-- Add 'razorpay' to payment_method enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.payment_method'::regtype
      AND enumlabel = 'razorpay'
  ) THEN
    ALTER TYPE public.payment_method ADD VALUE 'razorpay';
  END IF;
END $$;

-- Add 'authorized' to payment_status enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.payment_status'::regtype
      AND enumlabel = 'authorized'
  ) THEN
    ALTER TYPE public.payment_status ADD VALUE 'authorized';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. PAYMENTS TABLE HARDENING
-- -----------------------------------------------------------------------------

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'razorpay';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_method text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_status text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_error_code text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_error_description text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_error_source text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_error_step text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS gateway_error_reason text;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_attempt_no integer NOT NULL DEFAULT 1;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS verified_at timestamptz;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS captured_at timestamptz;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS failed_at timestamptz;

-- Unique indexes on gateway identifiers when present
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_gateway_order_id
ON public.payments (gateway_order_id)
WHERE gateway_order_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_gateway_payment_id
ON public.payments (gateway_payment_id)
WHERE gateway_payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_status_expires_at
ON public.payments (status, expires_at);

-- -----------------------------------------------------------------------------
-- 3. WEBHOOK EVENT IDEMPOTENCY TABLE
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.payment_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL DEFAULT 'razorpay',
  event_key text NOT NULL UNIQUE,
  event_type text NOT NULL,
  gateway_order_id text,
  gateway_payment_id text,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processing_status text NOT NULL DEFAULT 'received',
  payload jsonb,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS: Customer clients have ZERO access; server-only via service_role
ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.payment_webhook_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;

-- -----------------------------------------------------------------------------
-- 4. RPC: PREPARE RAZORPAY ORDER (ATOMIC INVENTORY & ORDER RESERVATION)
-- -----------------------------------------------------------------------------

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

    IF v_existing_order IS NOT NULL THEN
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

  -- Step 10: Insert Order Record in 'payment_pending' status
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

  -- Note: Active cart items are NOT deleted during preparation.
  -- Cart is cleared atomically upon confirmed payment capture in rpc_confirm_razorpay_payment_atomic.

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

-- -----------------------------------------------------------------------------
-- 5. RPC: SET PAYMENT GATEWAY ORDER ID
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_set_payment_gateway_order(
  p_order_id uuid,
  p_payment_id uuid,
  p_gateway_order_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.payments
  SET gateway_order_id = p_gateway_order_id,
      updated_at = now()
  WHERE id = p_payment_id AND order_id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: Payment or order does not exist' USING ERRCODE = 'P0011';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'payment_id', p_payment_id,
    'gateway_order_id', p_gateway_order_id
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 6. RPC: FAIL RAZORPAY INITIALIZATION COMPENSATION (RELEASE RESERVATIONS)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_fail_razorpay_initialization_atomic(
  p_order_id uuid,
  p_reason text DEFAULT 'Razorpay order initialization failed'
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
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist' USING ERRCODE = 'P0011';
  END IF;

  -- Idempotency: If already cancelled or failed, return cleanly
  IF v_order.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_cancelled', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'cancelled'
    );
  END IF;

  -- Only unconfirmed payment_pending orders can be compensated
  IF v_order.status <> 'payment_pending' THEN
    RAISE EXCEPTION 'ORDER_NOT_COMPENSABLE: Order status "%" cannot be compensated', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 1. Release Inventory Reservations
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

  -- 2. Reverse Coupon Redemption
  UPDATE public.coupon_redemptions
  SET is_reversed = true,
      reversed_at = now()
  WHERE order_id = p_order_id AND is_reversed = false;

  -- 3. Update Payment Record to failed
  UPDATE public.payments
  SET status = 'failed',
      failed_at = now(),
      gateway_error_description = p_reason,
      updated_at = now()
  WHERE order_id = p_order_id AND status = 'pending';

  -- 4. Update Order Record to cancelled
  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = 'failed',
      cancelled_reason = p_reason,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  -- 5. Record Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'cancelled',
    p_reason,
    v_order.user_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'id', p_order_id,
    'status', 'cancelled',
    'payment_status', 'failed',
    'reason', p_reason
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. RPC: CONFIRM RAZORPAY PAYMENT (ATOMIC GATEWAY PAYMENT CAPTURE)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_confirm_razorpay_payment_atomic(
  p_order_id uuid,
  p_gateway_payment_id text,
  p_gateway_order_id text,
  p_gateway_signature text DEFAULT NULL,
  p_gateway_method text DEFAULT NULL,
  p_gateway_status text DEFAULT 'captured'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_payment record;
  v_cart_id uuid;
BEGIN
  -- 1. Lock Order
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist' USING ERRCODE = 'P0011';
  END IF;

  -- 2. Idempotency Check: If order is already confirmed and payment completed
  IF v_order.status = 'confirmed' AND v_order.payment_status = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_confirmed', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'confirmed',
      'payment_status', 'completed'
    );
  END IF;

  -- Order must be in payment_pending status to transition to confirmed
  IF v_order.status NOT IN ('payment_pending', 'placed') THEN
    RAISE EXCEPTION 'ORDER_INVALID_STATE: Order is in status "%" and cannot be confirmed', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 3. Lock & Verify Payment
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: No payment record found for order' USING ERRCODE = 'P0011';
  END IF;

  -- 4. Update Payment Record to completed
  UPDATE public.payments
  SET status = 'completed',
      gateway_payment_id = p_gateway_payment_id,
      gateway_order_id = COALESCE(p_gateway_order_id, gateway_order_id),
      gateway_signature = COALESCE(p_gateway_signature, gateway_signature),
      gateway_method = COALESCE(p_gateway_method, gateway_method),
      gateway_status = p_gateway_status,
      verified_at = now(),
      captured_at = now(),
      updated_at = now()
  WHERE id = v_payment.id;

  -- 5. Update Order Record to confirmed
  UPDATE public.orders
  SET status = 'confirmed',
      payment_status = 'completed',
      updated_at = now()
  WHERE id = p_order_id;

  -- 6. Insert Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'confirmed',
    'Payment confirmed and captured via Razorpay (' || p_gateway_payment_id || ')',
    v_order.user_id
  );

  -- 7. Clear Customer Cart Atomically
  SELECT id INTO v_cart_id
  FROM public.carts
  WHERE user_id = v_order.user_id;

  IF v_cart_id IS NOT NULL THEN
    DELETE FROM public.cart_items WHERE cart_id = v_cart_id;
    UPDATE public.carts
    SET applied_coupon_id = NULL,
        updated_at = now()
    WHERE id = v_cart_id;
  END IF;

  -- Inventory reservations remain locked for fulfilment (not released)

  RETURN jsonb_build_object(
    'success', true,
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', 'confirmed',
    'payment_status', 'completed',
    'gateway_payment_id', p_gateway_payment_id,
    'gateway_order_id', p_gateway_order_id
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. RPC: RECORD PAYMENT FAILURE (CLIENT OR GATEWAY WEBHOOK)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_record_razorpay_payment_failure_atomic(
  p_order_id uuid,
  p_gateway_payment_id text DEFAULT NULL,
  p_error_code text DEFAULT NULL,
  p_error_description text DEFAULT NULL,
  p_error_source text DEFAULT NULL,
  p_error_step text DEFAULT NULL,
  p_error_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payment record;
BEGIN
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: No payment record found' USING ERRCODE = 'P0011';
  END IF;

  -- If payment is already completed, do not revert to failed
  IF v_payment.status = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_completed', true,
      'payment_id', v_payment.id
    );
  END IF;

  UPDATE public.payments
  SET gateway_payment_id = COALESCE(p_gateway_payment_id, gateway_payment_id),
      gateway_error_code = p_error_code,
      gateway_error_description = p_error_description,
      gateway_error_source = p_error_source,
      gateway_error_step = p_error_step,
      gateway_error_reason = p_error_reason,
      status = 'failed',
      failed_at = now(),
      updated_at = now()
  WHERE id = v_payment.id;

  RETURN jsonb_build_object(
    'success', true,
    'payment_id', v_payment.id,
    'status', 'failed'
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 9. RPC: PREPARE RAZORPAY RETRY ATTEMPT
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_prepare_razorpay_retry_atomic(
  p_user_id uuid,
  p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_payment record;
  v_new_attempt int;
  v_new_expires_at timestamptz;
BEGIN
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order not found or unauthorized' USING ERRCODE = 'P0011';
  END IF;

  IF v_order.status <> 'payment_pending' THEN
    RAISE EXCEPTION 'ORDER_NOT_RETRYABLE: Order in status "%" is not eligible for payment retry', v_order.status USING ERRCODE = 'P0012';
  END IF;

  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: Payment record not found' USING ERRCODE = 'P0011';
  END IF;

  -- Check if order window is already permanently expired (> 30 mins)
  IF v_order.created_at < (now() - interval '30 minutes') THEN
    RAISE EXCEPTION 'ORDER_EXPIRED: Payment window has expired. Please place a new order.' USING ERRCODE = 'P0013';
  END IF;

  v_new_attempt := COALESCE(v_payment.payment_attempt_no, 1) + 1;
  v_new_expires_at := now() + interval '15 minutes';

  -- Update payment for new attempt
  UPDATE public.payments
  SET payment_attempt_no = v_new_attempt,
      status = 'pending',
      expires_at = v_new_expires_at,
      gateway_error_code = NULL,
      gateway_error_description = NULL,
      updated_at = now()
  WHERE id = v_payment.id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_order.id,
    'order_number', v_order.order_number,
    'payment_id', v_payment.id,
    'total', v_order.total,
    'amount_paise', (ROUND(v_order.total * 100))::bigint,
    'currency', 'INR',
    'attempt_no', v_new_attempt,
    'expires_at', v_new_expires_at,
    'delivery_address_snapshot', v_order.delivery_address_snapshot,
    'delivery_slot_snapshot', v_order.delivery_slot_snapshot
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 10. RPC: EXPIRE PENDING RAZORPAY ORDERS (BACKGROUND CLEANUP)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_expire_pending_razorpay_orders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_expired_count int := 0;
  v_order record;
  v_item record;
BEGIN
  FOR v_order IN
    SELECT o.id, o.user_id, o.order_number
    FROM public.orders o
    WHERE o.status = 'payment_pending'
      AND o.created_at < (now() - interval '15 minutes')
    FOR UPDATE SKIP LOCKED
  LOOP
    -- 1. Release Inventory Reservations
    FOR v_item IN
      SELECT variant_id, quantity
      FROM public.order_items
      WHERE order_id = v_order.id
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
        v_order.id
      );
    END LOOP;

    -- 2. Reverse Coupon Redemption
    UPDATE public.coupon_redemptions
    SET is_reversed = true,
        reversed_at = now()
    WHERE order_id = v_order.id AND is_reversed = false;

    -- 3. Cancel Payment
    UPDATE public.payments
    SET status = 'cancelled',
        updated_at = now()
    WHERE order_id = v_order.id AND status = 'pending';

    -- 4. Cancel Order
    UPDATE public.orders
    SET status = 'cancelled',
        payment_status = 'cancelled',
        cancelled_reason = 'Payment window expired (15 minutes)',
        cancelled_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    -- 5. Record Order Status History
    INSERT INTO public.order_status_history (
      order_id,
      status,
      notes,
      created_by
    ) VALUES (
      v_order.id,
      'cancelled',
      'Order cancelled automatically due to payment expiry (15 mins)',
      v_order.user_id
    );

    v_expired_count := v_expired_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'expired_count', v_expired_count,
    'executed_at', now()
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 11. LEAST-PRIVILEGE FUNCTION GRANTS (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_razorpay_order_atomic(uuid, uuid, uuid, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_set_payment_gateway_order(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_set_payment_gateway_order(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_fail_razorpay_initialization_atomic(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_fail_razorpay_initialization_atomic(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_confirm_razorpay_payment_atomic(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_confirm_razorpay_payment_atomic(uuid, text, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_record_razorpay_payment_failure_atomic(uuid, text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_razorpay_payment_failure_atomic(uuid, text, text, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_prepare_razorpay_retry_atomic(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_razorpay_retry_atomic(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_expire_pending_razorpay_orders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_expire_pending_razorpay_orders() TO service_role;

-- -----------------------------------------------------------------------------
-- 12. PG_CRON SCHEDULE (HOSTED SUPABASE CRON IF AVAILABLE)
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unsched existing job if present to maintain idempotency
    BEGIN
      PERFORM cron.unschedule('expire-pending-razorpay-orders');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    -- Schedule cleanup every 5 minutes
    PERFORM cron.schedule(
      'expire-pending-razorpay-orders',
      '*/5 * * * *',
      'SELECT public.rpc_expire_pending_razorpay_orders();'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Fallback if pg_cron is not enabled on this plan/project
  NULL;
END $$;
