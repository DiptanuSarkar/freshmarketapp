-- =============================================================================
-- Migration: 20261010043308_session5b_wallet_mixed_refund_engine.sql
-- Description: Session 5B Database Engine:
--   1. Payment Method Enum: Safely add 'mixed'
--   2. Wallet Account Concurrency: reserved_balance and safety constraints
--   3. Wallet Ledger Hardening: Reasons, before/after balances, idempotency indexes
--   4. Payment & Order Breakdown: wallet_amount, gateway_amount, wallet_reserved_amount
--   5. Refund Data Model: Normalized refund_components, request_id, RLS
--   6. Webhook Events: gateway_refund_id support
--   7. Privileged RPCs:
--      - rpc_adjust_wallet_atomic (Service-role funding & adjustments)
--      - rpc_calculate_wallet_allocation (Trusted wallet allocation helper)
--      - rpc_calculate_checkout_quote (Updated with use_wallet support)
--      - rpc_reserve_wallet_for_order_atomic (Atomic wallet hold for mixed checkout)
--      - rpc_confirm_wallet_only_order_atomic (Atomic full-wallet order capture)
--      - rpc_confirm_mixed_payment_atomic (Atomic mixed wallet+gateway capture)
--      - rpc_fail_razorpay_initialization_atomic (Updated to release wallet hold)
--      - rpc_record_razorpay_payment_failure_atomic (Updated to release wallet hold)
--      - rpc_expire_pending_razorpay_orders (Updated to release wallet hold)
--      - rpc_prepare_razorpay_retry_atomic (Preserves wallet reservation on retry)
--      - rpc_cancel_order_atomic (Guards against unpaid cancellation on paid orders)
--      - rpc_prepare_order_cancellation_refund_atomic (Instant wallet credit + gateway refund)
--      - rpc_record_gateway_refund_submission_atomic (Records gateway refund submission)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ENUM EXTENSIONS
-- -----------------------------------------------------------------------------

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'payment_method' AND e.enumlabel = 'mixed'
  ) THEN
    ALTER TYPE public.payment_method ADD VALUE 'mixed';
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'payment_status' AND e.enumlabel = 'partially_refunded'
  ) THEN
    ALTER TYPE public.payment_status ADD VALUE 'partially_refunded';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. WALLET ACCOUNT CONCURRENCY & CONSTRAINTS
-- -----------------------------------------------------------------------------

ALTER TABLE public.wallet_accounts
ADD COLUMN IF NOT EXISTS reserved_balance numeric(10,2) NOT NULL DEFAULT 0.00;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallet_accounts_reserved_balance_non_negative'
  ) THEN
    ALTER TABLE public.wallet_accounts
    ADD CONSTRAINT chk_wallet_accounts_reserved_balance_non_negative
    CHECK (reserved_balance >= 0.00);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallet_accounts_reserved_le_balance'
  ) THEN
    ALTER TABLE public.wallet_accounts
    ADD CONSTRAINT chk_wallet_accounts_reserved_le_balance
    CHECK (reserved_balance <= balance);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3. WALLET LEDGER HARDENING
-- -----------------------------------------------------------------------------

ALTER TABLE public.wallet_transactions
ADD COLUMN IF NOT EXISTS reason text,
ADD COLUMN IF NOT EXISTS balance_before numeric(10,2),
ADD COLUMN IF NOT EXISTS balance_after numeric(10,2),
ADD COLUMN IF NOT EXISTS order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS payment_id uuid REFERENCES public.payments(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS refund_id uuid REFERENCES public.refunds(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS idempotency_key text,
ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'completed';

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_tx_idempotency_key
ON public.wallet_transactions (idempotency_key)
WHERE idempotency_key IS NOT NULL;

DROP INDEX IF EXISTS public.idx_wallet_tx_order_payment;
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_tx_order_payment
ON public.wallet_transactions (order_id, reason)
WHERE reason = 'order_payment';

DROP INDEX IF EXISTS public.idx_wallet_tx_refund;
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_tx_refund
ON public.wallet_transactions (refund_id, reason)
WHERE reason = 'refund';

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created
ON public.wallet_transactions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_order_id
ON public.wallet_transactions (order_id)
WHERE order_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wallet_tx_refund_id
ON public.wallet_transactions (refund_id)
WHERE refund_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 4. PAYMENT & ORDER BREAKDOWN FIELDS
-- -----------------------------------------------------------------------------

ALTER TABLE public.payments
ADD COLUMN IF NOT EXISTS wallet_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (wallet_amount >= 0.00),
ADD COLUMN IF NOT EXISTS wallet_reserved_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (wallet_reserved_amount >= 0.00),
ADD COLUMN IF NOT EXISTS gateway_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (gateway_amount >= 0.00);

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS wallet_amount_used numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (wallet_amount_used >= 0.00),
ADD COLUMN IF NOT EXISTS gateway_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (gateway_amount >= 0.00);

-- -----------------------------------------------------------------------------
-- 5. REFUND DATA MODEL & NORMALIZED COMPONENTS
-- -----------------------------------------------------------------------------

ALTER TABLE public.refunds
ADD COLUMN IF NOT EXISTS request_id text,
ADD COLUMN IF NOT EXISTS requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'freshmarket',
ADD COLUMN IF NOT EXISTS requested_at timestamptz NOT NULL DEFAULT now(),
ADD COLUMN IF NOT EXISTS processed_at timestamptz,
ADD COLUMN IF NOT EXISTS failed_at timestamptz,
ADD COLUMN IF NOT EXISTS error_code text,
ADD COLUMN IF NOT EXISTS error_message text,
ADD COLUMN IF NOT EXISTS wallet_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (wallet_amount >= 0.00),
ADD COLUMN IF NOT EXISTS gateway_amount numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (gateway_amount >= 0.00);

CREATE UNIQUE INDEX IF NOT EXISTS idx_refunds_request_id
ON public.refunds (request_id)
WHERE request_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_refunds_order_id
ON public.refunds (order_id);

CREATE INDEX IF NOT EXISTS idx_refunds_status
ON public.refunds (status);

CREATE TABLE IF NOT EXISTS public.refund_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
  method text NOT NULL CHECK (method IN ('wallet', 'razorpay')),
  amount numeric(10,2) NOT NULL CHECK (amount > 0.00),
  status text NOT NULL DEFAULT 'initiated' CHECK (status IN ('initiated', 'processing', 'processed', 'failed')),
  gateway_refund_id text,
  provider_status text,
  processed_at timestamptz,
  failed_at timestamptz,
  error_code text,
  error_message text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_refund_components_refund_method
ON public.refund_components (refund_id, method);

CREATE UNIQUE INDEX IF NOT EXISTS idx_refund_components_gateway_id
ON public.refund_components (gateway_refund_id)
WHERE gateway_refund_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_refund_components_refund_id
ON public.refund_components (refund_id);

CREATE INDEX IF NOT EXISTS idx_refund_components_status
ON public.refund_components (status);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_refund_components_updated_at') THEN
    CREATE TRIGGER trg_refund_components_updated_at
    BEFORE UPDATE ON public.refund_components
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

ALTER TABLE public.refund_components ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'refund_components' AND policyname = 'refund_components_select_own') THEN
    CREATE POLICY refund_components_select_own ON public.refund_components
    FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.refunds r
        JOIN public.orders o ON o.id = r.order_id
        WHERE r.id = refund_components.refund_id
        AND o.user_id = auth.uid()
      )
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'refund_components' AND policyname = 'refund_components_admin_all') THEN
    CREATE POLICY refund_components_admin_all ON public.refund_components
    FOR ALL TO authenticated
    USING (private.has_role('admin'::public.app_role))
    WITH CHECK (private.has_role('admin'::public.app_role));
  END IF;
END $$;

REVOKE INSERT, UPDATE, DELETE ON public.refund_components FROM authenticated, anon, PUBLIC;
GRANT SELECT ON public.refund_components TO authenticated;
GRANT ALL ON public.refund_components TO service_role;

-- -----------------------------------------------------------------------------
-- 6. PAYMENT WEBHOOK EVENTS EXTENSION
-- -----------------------------------------------------------------------------

ALTER TABLE public.payment_webhook_events
ADD COLUMN IF NOT EXISTS gateway_refund_id text;

CREATE INDEX IF NOT EXISTS idx_payment_webhook_gateway_refund_id
ON public.payment_webhook_events (gateway_refund_id)
WHERE gateway_refund_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 7. RPC: ADJUST WALLET ATOMIC (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_adjust_wallet_atomic(
  p_user_id uuid,
  p_amount numeric,
  p_reason text,
  p_description text,
  p_idempotency_key text,
  p_reference_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet record;
  v_balance_before numeric(10,2);
  v_balance_after numeric(10,2);
  v_type public.wallet_tx_type;
  v_tx_id uuid;
  v_existing_tx record;
BEGIN
  IF p_amount = 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: Adjustment amount cannot be zero' USING ERRCODE = 'P0001';
  END IF;

  -- 1. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing_tx
    FROM public.wallet_transactions
    WHERE idempotency_key = p_idempotency_key;

    IF FOUND THEN
      SELECT * INTO v_wallet FROM public.wallet_accounts WHERE user_id = p_user_id;
      RETURN jsonb_build_object(
        'success', true,
        'already_processed', true,
        'balance', v_wallet.balance,
        'reserved_balance', v_wallet.reserved_balance,
        'transaction_id', v_existing_tx.id
      );
    END IF;
  END IF;

  -- 2. Lock or Initialize Wallet Account
  SELECT * INTO v_wallet
  FROM public.wallet_accounts
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet IS NULL THEN
    INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
    VALUES (p_user_id, 0.00, 0.00, 'INR')
    RETURNING * INTO v_wallet;
  END IF;

  v_balance_before := v_wallet.balance;
  v_balance_after := ROUND(v_balance_before + p_amount, 2);

  -- 3. Balance Invariant Checks
  IF v_balance_after < 0.00 THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Wallet balance cannot become negative (balance: %, adjust: %)', v_balance_before, p_amount USING ERRCODE = 'P0020';
  END IF;

  IF v_balance_after < v_wallet.reserved_balance THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Posted balance cannot fall below active reserved balance (reserved: %)', v_wallet.reserved_balance USING ERRCODE = 'P0021';
  END IF;

  -- 4. Update Wallet Account
  UPDATE public.wallet_accounts
  SET balance = v_balance_after,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 5. Insert Immutable Ledger Transaction
  v_type := CASE WHEN p_amount > 0 THEN 'credit'::public.wallet_tx_type ELSE 'debit'::public.wallet_tx_type END;

  INSERT INTO public.wallet_transactions (
    user_id,
    amount,
    type,
    description,
    reference_id,
    reason,
    balance_before,
    balance_after,
    closing_balance,
    idempotency_key,
    status
  ) VALUES (
    p_user_id,
    ABS(p_amount),
    v_type,
    p_description,
    p_reference_id,
    p_reason,
    v_balance_before,
    v_balance_after,
    v_balance_after,
    p_idempotency_key,
    'completed'
  ) RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object(
    'success', true,
    'balance_before', v_balance_before,
    'balance_after', v_balance_after,
    'reserved_balance', v_wallet.reserved_balance,
    'available_balance', ROUND(v_balance_after - v_wallet.reserved_balance, 2),
    'transaction_id', v_tx_id
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. RPC: CALCULATE WALLET ALLOCATION (READ-ONLY PREVIEW)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_calculate_wallet_allocation(
  p_user_id uuid,
  p_order_total numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet record;
  v_balance numeric(10,2) := 0.00;
  v_reserved numeric(10,2) := 0.00;
  v_available numeric(10,2) := 0.00;
  v_applicable numeric(10,2) := 0.00;
  v_gateway_payable numeric(10,2) := 0.00;
  v_target_total numeric(10,2);
BEGIN
  v_target_total := GREATEST(0.00, ROUND(p_order_total, 2));

  SELECT balance, reserved_balance INTO v_balance, v_reserved
  FROM public.wallet_accounts
  WHERE user_id = p_user_id;

  IF v_balance IS NULL THEN
    v_balance := 0.00;
    v_reserved := 0.00;
  END IF;

  v_available := GREATEST(0.00, ROUND(v_balance - v_reserved, 2));
  v_applicable := LEAST(v_available, v_target_total);
  v_gateway_payable := GREATEST(0.00, ROUND(v_target_total - v_applicable, 2));

  RETURN jsonb_build_object(
    'wallet_balance', v_balance,
    'wallet_reserved', v_reserved,
    'wallet_available', v_available,
    'wallet_amount_applicable', v_applicable,
    'remaining_gateway_amount', v_gateway_payable,
    'is_wallet_only', (v_gateway_payable = 0.00 AND v_applicable > 0.00)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 9. RPC: CALCULATE CHECKOUT QUOTE (EXTENDED WITH WALLET SUPPORT)
-- -----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text);

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

-- -----------------------------------------------------------------------------
-- 10. RPC: RESERVE WALLET FOR ORDER ATOMIC (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_reserve_wallet_for_order_atomic(
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
  v_wallet record;
  v_available numeric(10,2);
  v_reserve_amount numeric(10,2);
  v_gateway_amount numeric(10,2);
  v_payment_method public.payment_method;
BEGIN
  -- 1. Lock Order
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist or unauthorized' USING ERRCODE = 'P0011';
  END IF;

  IF v_order.status NOT IN ('pending', 'payment_pending') THEN
    RAISE EXCEPTION 'ORDER_NOT_ELIGIBLE: Order in status "%" cannot reserve wallet funds', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 2. Lock Payment
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: Payment record missing for order' USING ERRCODE = 'P0011';
  END IF;

  -- 3. Idempotency Check: Already reserved for this payment
  IF v_payment.wallet_reserved_amount > 0.00 THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_reserved', true,
      'order_id', v_order.id,
      'payment_id', v_payment.id,
      'total', v_order.total,
      'wallet_amount', v_payment.wallet_amount,
      'gateway_amount', v_payment.gateway_amount,
      'gateway_paise', (ROUND(v_payment.gateway_amount * 100))::bigint,
      'payment_method', v_payment.payment_method,
      'is_wallet_only', (v_payment.gateway_amount = 0.00)
    );
  END IF;

  -- 4. Lock Wallet Account
  SELECT * INTO v_wallet
  FROM public.wallet_accounts
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet IS NULL THEN
    INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
    VALUES (p_user_id, 0.00, 0.00, 'INR')
    RETURNING * INTO v_wallet;
  END IF;

  v_available := GREATEST(0.00, ROUND(v_wallet.balance - v_wallet.reserved_balance, 2));

  IF v_available <= 0.00 THEN
    -- Wallet has 0 available; full gateway payment continues
    v_reserve_amount := 0.00;
    v_gateway_amount := v_order.total;
    v_payment_method := 'razorpay'::public.payment_method;
  ELSE
    v_reserve_amount := LEAST(v_available, v_order.total);
    v_gateway_amount := GREATEST(0.00, ROUND(v_order.total - v_reserve_amount, 2));
    v_payment_method := CASE
      WHEN v_gateway_amount = 0.00 THEN 'wallet'::public.payment_method
      ELSE 'mixed'::public.payment_method
    END;

    -- Update reserved balance atomically
    UPDATE public.wallet_accounts
    SET reserved_balance = reserved_balance + v_reserve_amount,
        updated_at = now()
    WHERE user_id = p_user_id;
  END IF;

  -- Update Payment Breakdown
  UPDATE public.payments
  SET wallet_amount = v_reserve_amount,
      wallet_reserved_amount = v_reserve_amount,
      gateway_amount = v_gateway_amount,
      payment_method = v_payment_method,
      updated_at = now()
  WHERE id = v_payment.id;

  -- Update Order Snapshot
  UPDATE public.orders
  SET wallet_amount_used = v_reserve_amount,
      gateway_amount = v_gateway_amount,
      payment_method = v_payment_method,
      updated_at = now()
  WHERE id = v_order.id;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'payment_id', v_payment.id,
    'total', v_order.total,
    'wallet_amount', v_reserve_amount,
    'gateway_amount', v_gateway_amount,
    'gateway_paise', (ROUND(v_gateway_amount * 100))::bigint,
    'payment_method', v_payment_method,
    'is_wallet_only', (v_gateway_amount = 0.00)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 11. RPC: CONFIRM WALLET-ONLY ORDER ATOMIC (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_confirm_wallet_only_order_atomic(
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
  v_wallet record;
  v_cart_id uuid;
  v_wallet_deduct numeric(10,2);
  v_reserved_deduct numeric(10,2);
BEGIN
  -- 1. Lock Order
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist or unauthorized' USING ERRCODE = 'P0011';
  END IF;

  -- Idempotency: Already confirmed
  IF v_order.status = 'confirmed' AND v_order.payment_status = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_confirmed', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'confirmed',
      'payment_status', 'completed',
      'payment_method', 'wallet'
    );
  END IF;

  -- 2. Lock Payment
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: Payment record missing' USING ERRCODE = 'P0011';
  END IF;

  -- 3. Lock Wallet Account
  SELECT * INTO v_wallet
  FROM public.wallet_accounts
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND: Wallet account does not exist' USING ERRCODE = 'P0011';
  END IF;

  v_wallet_deduct := v_order.total;
  v_reserved_deduct := v_payment.wallet_reserved_amount;

  IF v_wallet.balance < v_wallet_deduct THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Wallet balance (₹%) insufficient for order total (₹%)', v_wallet.balance, v_wallet_deduct USING ERRCODE = 'P0020';
  END IF;

  -- 4. Deduct Posted Balance & Release Reservation atomically
  UPDATE public.wallet_accounts
  SET balance = balance - v_wallet_deduct,
      reserved_balance = GREATEST(0.00, reserved_balance - v_reserved_deduct),
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 5. Insert Wallet Debit Transaction
  INSERT INTO public.wallet_transactions (
    user_id,
    amount,
    type,
    description,
    reference_id,
    reason,
    balance_before,
    balance_after,
    closing_balance,
    order_id,
    payment_id,
    idempotency_key,
    status
  ) VALUES (
    p_user_id,
    v_wallet_deduct,
    'debit'::public.wallet_tx_type,
    'Payment for Order ' || v_order.order_number,
    v_order.order_number,
    'order_payment',
    v_wallet.balance,
    v_wallet.balance - v_wallet_deduct,
    v_wallet.balance - v_wallet_deduct,
    p_order_id,
    v_payment.id,
    'order_debit_' || v_order.id,
    'completed'
  )
  ON CONFLICT (order_id, reason) WHERE reason = 'order_payment' DO NOTHING;

  -- 6. Update Payment Record
  UPDATE public.payments
  SET status = 'completed',
      captured_at = now(),
      wallet_amount = v_wallet_deduct,
      wallet_reserved_amount = 0.00,
      gateway_amount = 0.00,
      payment_method = 'wallet'::public.payment_method,
      updated_at = now()
  WHERE id = v_payment.id;

  -- 7. Update Order Record
  UPDATE public.orders
  SET status = 'confirmed',
      payment_status = 'completed',
      wallet_amount_used = v_wallet_deduct,
      gateway_amount = 0.00,
      payment_method = 'wallet'::public.payment_method,
      updated_at = now()
  WHERE id = p_order_id;

  -- 8. Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'confirmed',
    'Payment confirmed via FreshMarket Wallet',
    p_user_id
  );

  -- 9. Clear Customer Cart Atomically
  SELECT id INTO v_cart_id
  FROM public.carts
  WHERE user_id = p_user_id;

  IF v_cart_id IS NOT NULL THEN
    DELETE FROM public.cart_items WHERE cart_id = v_cart_id;
    UPDATE public.carts
    SET applied_coupon_id = NULL,
        updated_at = now()
    WHERE id = v_cart_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_order.id,
    'order_number', v_order.order_number,
    'payment_id', v_payment.id,
    'status', 'confirmed',
    'payment_status', 'completed',
    'payment_method', 'wallet',
    'wallet_amount_debited', v_wallet_deduct,
    'remaining_wallet_balance', ROUND(v_wallet.balance - v_wallet_deduct, 2)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 12. RPC: CONFIRM MIXED PAYMENT ATOMIC (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_confirm_mixed_payment_atomic(
  p_order_id uuid,
  p_gateway_payment_id text,
  p_gateway_order_id text,
  p_gateway_signature text DEFAULT NULL,
  p_gateway_method text DEFAULT NULL,
  p_gateway_status text DEFAULT 'captured',
  p_amount_paise bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_payment record;
  v_wallet record;
  v_cart_id uuid;
  v_wallet_deduct numeric(10,2);
  v_reserved_deduct numeric(10,2);
  v_expected_paise bigint;
BEGIN
  -- 1. Lock Order
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist' USING ERRCODE = 'P0011';
  END IF;

  -- 2. Lock Payment
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND: Payment record does not exist' USING ERRCODE = 'P0011';
  END IF;

  -- Idempotency Check: Already completed
  IF v_payment.status = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_confirmed', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'confirmed',
      'payment_status', 'completed',
      'gateway_payment_id', v_payment.gateway_payment_id,
      'gateway_order_id', v_payment.gateway_order_id,
      'payment_method', 'mixed'
    );
  END IF;

  -- Validate Gateway Order ID if stored
  IF v_payment.gateway_order_id IS NOT NULL AND v_payment.gateway_order_id <> p_gateway_order_id THEN
    RAISE EXCEPTION 'GATEWAY_ORDER_MISMATCH: Order ID % does not match expected %', p_gateway_order_id, v_payment.gateway_order_id USING ERRCODE = 'P0014';
  END IF;

  -- Validate gateway amount paise
  v_expected_paise := (ROUND(v_payment.gateway_amount * 100))::bigint;
  IF p_amount_paise IS NOT NULL AND p_amount_paise <> v_expected_paise THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: Received % paise but expected % paise', p_amount_paise, v_expected_paise USING ERRCODE = 'P0015';
  END IF;

  -- 3. Lock Wallet Account
  SELECT * INTO v_wallet
  FROM public.wallet_accounts
  WHERE user_id = v_order.user_id
  FOR UPDATE;

  IF v_wallet IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND: Wallet account does not exist' USING ERRCODE = 'P0011';
  END IF;

  v_wallet_deduct := v_payment.wallet_amount;
  v_reserved_deduct := v_payment.wallet_reserved_amount;

  IF v_wallet.balance < v_wallet_deduct THEN
    RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Posted wallet balance insufficient for hold' USING ERRCODE = 'P0020';
  END IF;

  -- 4. Debit Posted Balance & Release Reservation
  UPDATE public.wallet_accounts
  SET balance = balance - v_wallet_deduct,
      reserved_balance = GREATEST(0.00, reserved_balance - v_reserved_deduct),
      updated_at = now()
  WHERE user_id = v_order.user_id;

  -- 5. Insert Wallet Debit Transaction
  INSERT INTO public.wallet_transactions (
    user_id,
    amount,
    type,
    description,
    reference_id,
    reason,
    balance_before,
    balance_after,
    closing_balance,
    order_id,
    payment_id,
    idempotency_key,
    status
  ) VALUES (
    v_order.user_id,
    v_wallet_deduct,
    'debit'::public.wallet_tx_type,
    'Wallet portion for Order ' || v_order.order_number,
    v_order.order_number,
    'order_payment',
    v_wallet.balance,
    v_wallet.balance - v_wallet_deduct,
    v_wallet.balance - v_wallet_deduct,
    p_order_id,
    v_payment.id,
    'order_debit_' || v_order.id,
    'completed'
  )
  ON CONFLICT (order_id, reason) WHERE reason = 'order_payment' DO NOTHING;

  -- 6. Update Payment Record
  UPDATE public.payments
  SET status = 'completed',
      gateway_payment_id = p_gateway_payment_id,
      gateway_order_id = p_gateway_order_id,
      gateway_signature = COALESCE(p_gateway_signature, gateway_signature),
      gateway_method = COALESCE(p_gateway_method, gateway_method),
      gateway_status = p_gateway_status,
      captured_at = now(),
      verified_at = now(),
      wallet_reserved_amount = 0.00,
      updated_at = now()
  WHERE id = v_payment.id;

  -- 7. Update Order Record
  UPDATE public.orders
  SET status = 'confirmed',
      payment_status = 'completed',
      updated_at = now()
  WHERE id = p_order_id;

  -- 8. Order Status History
  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'confirmed',
    'Mixed Payment confirmed (Wallet ₹' || v_wallet_deduct || ' + Razorpay ₹' || v_payment.gateway_amount || ')',
    v_order.user_id
  );

  -- 9. Clear Customer Cart Atomically
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

  RETURN jsonb_build_object(
    'success', true,
    'id', v_order.id,
    'order_number', v_order.order_number,
    'payment_id', v_payment.id,
    'status', 'confirmed',
    'payment_status', 'completed',
    'payment_method', 'mixed',
    'wallet_amount', v_wallet_deduct,
    'gateway_amount', v_payment.gateway_amount,
    'gateway_payment_id', p_gateway_payment_id
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 13. UPDATE COMPENSATION & EXPIRY RPCS TO RELEASE WALLET HOLDS
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
  v_payment record;
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

  -- 3. Release Wallet Hold if any
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id AND status = 'pending'
  FOR UPDATE;

  IF FOUND AND COALESCE(v_payment.wallet_reserved_amount, 0.00) > 0.00 THEN
    UPDATE public.wallet_accounts
    SET reserved_balance = GREATEST(0.00, reserved_balance - v_payment.wallet_reserved_amount),
        updated_at = now()
    WHERE user_id = v_order.user_id;

    UPDATE public.payments
    SET wallet_reserved_amount = 0.00,
        updated_at = now()
    WHERE id = v_payment.id;
  END IF;

  -- 4. Update Payment Record to failed
  UPDATE public.payments
  SET status = 'failed',
      failed_at = now(),
      gateway_error_description = p_reason,
      updated_at = now()
  WHERE order_id = p_order_id AND status = 'pending';

  -- 5. Update Order Record to cancelled
  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = 'failed',
      cancelled_reason = p_reason,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  -- 6. Record Order Status History
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
  v_order record;
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

  IF v_payment.status = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_completed', true,
      'payment_id', v_payment.id
    );
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;

  -- Release wallet hold if this attempt failed
  IF FOUND AND COALESCE(v_payment.wallet_reserved_amount, 0.00) > 0.00 THEN
    UPDATE public.wallet_accounts
    SET reserved_balance = GREATEST(0.00, reserved_balance - v_payment.wallet_reserved_amount),
        updated_at = now()
    WHERE user_id = v_order.user_id;

    UPDATE public.payments
    SET wallet_reserved_amount = 0.00,
        updated_at = now()
    WHERE id = v_payment.id;
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
  v_gateway_due numeric(10,2);
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

  IF v_order.created_at < (now() - interval '30 minutes') THEN
    RAISE EXCEPTION 'ORDER_EXPIRED: Payment window has expired. Please place a new order.' USING ERRCODE = 'P0013';
  END IF;

  v_new_attempt := COALESCE(v_payment.payment_attempt_no, 1) + 1;
  v_new_expires_at := now() + interval '15 minutes';
  v_gateway_due := COALESCE(v_payment.gateway_amount, v_order.total);

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
    'gateway_amount', v_gateway_due,
    'wallet_amount', v_payment.wallet_amount,
    'amount_paise', (ROUND(v_gateway_due * 100))::bigint,
    'currency', 'INR',
    'attempt_no', v_new_attempt,
    'expires_at', v_new_expires_at,
    'delivery_address_snapshot', v_order.delivery_address_snapshot,
    'delivery_slot_snapshot', v_order.delivery_slot_snapshot
  );
END;
$$;

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
  v_payment record;
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

    -- 3. Release Wallet Hold if any
    SELECT * INTO v_payment
    FROM public.payments
    WHERE order_id = v_order.id AND status = 'pending'
    FOR UPDATE;

    IF FOUND AND COALESCE(v_payment.wallet_reserved_amount, 0.00) > 0.00 THEN
      UPDATE public.wallet_accounts
      SET reserved_balance = GREATEST(0.00, reserved_balance - v_payment.wallet_reserved_amount),
          updated_at = now()
      WHERE user_id = v_order.user_id;

      UPDATE public.payments
      SET wallet_reserved_amount = 0.00,
          updated_at = now()
      WHERE id = v_payment.id;
    END IF;

    -- 4. Cancel Payment
    UPDATE public.payments
    SET status = 'cancelled',
        updated_at = now()
    WHERE order_id = v_order.id AND status = 'pending';

    -- 5. Cancel Order
    UPDATE public.orders
    SET status = 'cancelled',
        payment_status = 'cancelled',
        cancelled_reason = 'Payment window expired (15 minutes)',
        cancelled_at = now(),
        updated_at = now()
    WHERE id = v_order.id;

    -- 6. Insert Order Status History
    INSERT INTO public.order_status_history (
      order_id,
      status,
      notes,
      created_by
    ) VALUES (
      v_order.id,
      'cancelled',
      'Order cancelled due to online payment expiry',
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
-- 14. PATCH RPC_CANCEL_ORDER_ATOMIC (PAID ORDER CANCELLATION GUARD)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_cancel_order_atomic(
  p_user_id uuid,
  p_order_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_payment record;
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

  -- 2. Idempotency: If already cancelled, return cleanly without duplicating work
  IF v_order.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_cancelled', true,
      'id', v_order.id,
      'order_number', v_order.order_number,
      'status', 'cancelled',
      'payment_status', 'cancelled',
      'cancelled_reason', v_order.cancelled_reason
    );
  END IF;

  -- 3. Check Cancellation Eligibility
  IF v_order.status NOT IN ('placed', 'confirmed', 'pending', 'payment_pending') THEN
    RAISE EXCEPTION 'ORDER_NOT_CANCELLABLE: Orders in "%" stage cannot be cancelled by customer', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- Check latest payment record
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  -- 4. GUARD: Completed Paid orders MUST NOT use the unpaid cancellation path
  IF (v_order.payment_status = 'completed') OR (v_payment.id IS NOT NULL AND v_payment.status = 'completed') THEN
    RAISE EXCEPTION 'PAID_ORDER_REFUND_REQUIRED: Completed orders with successful payments cannot be cancelled via unpaid cancellation path. Use refund-aware cancellation flow.' USING ERRCODE = 'P0015';
  END IF;

  -- 5. Lock & Release Inventory Reservations atomically
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

  -- 6. Reverse Coupon Redemption
  UPDATE public.coupon_redemptions
  SET is_reversed = true,
      reversed_at = now()
  WHERE order_id = p_order_id AND is_reversed = false;

  -- 7. Release Wallet Hold if any
  IF v_payment.id IS NOT NULL AND COALESCE(v_payment.wallet_reserved_amount, 0.00) > 0.00 THEN
    UPDATE public.wallet_accounts
    SET reserved_balance = GREATEST(0.00, reserved_balance - v_payment.wallet_reserved_amount),
        updated_at = now()
    WHERE user_id = p_user_id;

    UPDATE public.payments
    SET wallet_reserved_amount = 0.00,
        updated_at = now()
    WHERE id = v_payment.id;
  END IF;

  -- 8. Update Payment Record to Canonical 'cancelled' State
  UPDATE public.payments
  SET status = 'cancelled',
      updated_at = now()
  WHERE order_id = p_order_id AND status = 'pending';

  -- 9. Update Order Status and Payment Status
  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = 'cancelled',
      cancelled_reason = p_reason,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  -- 10. Record Order Status History
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
    'payment_status', 'cancelled',
    'cancelled_reason', p_reason
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 15. RPC: PREPARE ORDER CANCELLATION REFUND ATOMIC (REFUND-AWARE CANCELLATION)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_prepare_order_cancellation_refund_atomic(
  p_user_id uuid,
  p_order_id uuid,
  p_reason text,
  p_refund_request_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order record;
  v_payment record;
  v_item record;
  v_existing_refund record;
  v_wallet record;
  v_refund_id uuid;
  v_wallet_amount numeric(10,2) := 0.00;
  v_gateway_amount numeric(10,2) := 0.00;
  v_total_refund numeric(10,2) := 0.00;
  v_initial_refund_status text;
BEGIN
  -- 1. Lock Order
  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order does not exist or unauthorized' USING ERRCODE = 'P0011';
  END IF;

  -- 2. Idempotency Check: Already processed with this refund request
  SELECT * INTO v_existing_refund
  FROM public.refunds
  WHERE order_id = p_order_id AND (request_id = p_refund_request_id OR status IN ('initiated', 'processing', 'processed'));

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_refunded', true,
      'refund_id', v_existing_refund.id,
      'order_id', p_order_id,
      'order_number', v_order.order_number,
      'total_amount', v_existing_refund.amount,
      'wallet_refund_amount', v_existing_refund.wallet_amount,
      'gateway_refund_amount', v_existing_refund.gateway_amount,
      'gateway_payment_id', (SELECT gateway_payment_id FROM public.payments WHERE id = v_existing_refund.payment_id),
      'status', v_existing_refund.status,
      'requires_gateway_refund', (v_existing_refund.gateway_amount > 0.00)
    );
  END IF;

  -- 3. Verify Order Eligibility (Must be cancellable)
  IF v_order.status NOT IN ('placed', 'confirmed') THEN
    RAISE EXCEPTION 'ORDER_NOT_CANCELLABLE: Orders in stage "%" cannot be cancelled', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 4. Lock Completed Payment
  SELECT * INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id AND status = 'completed'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_payment IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_COMPLETED: Order does not have a completed payment record to refund' USING ERRCODE = 'P0013';
  END IF;

  -- 5. Release Inventory Reservations
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

  -- 6. Reverse Coupon
  UPDATE public.coupon_redemptions
  SET is_reversed = true,
      reversed_at = now()
  WHERE order_id = p_order_id AND is_reversed = false;

  -- 7. Update Order to Cancelled
  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = 'refunded',
      cancelled_reason = p_reason,
      cancelled_at = now(),
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_by
  ) VALUES (
    p_order_id,
    'cancelled',
    COALESCE(p_reason, 'Customer cancelled paid order; refund initiated'),
    p_user_id
  );

  -- 8. Compute Authoritative Refund Splits
  v_wallet_amount := COALESCE(v_payment.wallet_amount, 0.00);
  v_gateway_amount := COALESCE(v_payment.gateway_amount, 0.00);
  v_total_refund := v_order.total;
  v_initial_refund_status := CASE WHEN v_gateway_amount > 0.00 THEN 'processing' ELSE 'processed' END;

  -- 9. Insert Parent Refund Record
  INSERT INTO public.refunds (
    order_id,
    payment_id,
    amount,
    reason,
    status,
    refund_method,
    request_id,
    requested_by,
    wallet_amount,
    gateway_amount,
    processed_at
  ) VALUES (
    p_order_id,
    v_payment.id,
    v_total_refund,
    COALESCE(p_reason, 'Customer cancellation'),
    v_initial_refund_status,
    v_order.payment_method::text,
    p_refund_request_id,
    p_user_id,
    v_wallet_amount,
    v_gateway_amount,
    CASE WHEN v_gateway_amount = 0.00 THEN now() ELSE NULL END
  ) RETURNING id INTO v_refund_id;

  -- 10. Process Instant Wallet Refund Credit (if wallet portion > 0)
  IF v_wallet_amount > 0.00 THEN
    SELECT * INTO v_wallet
    FROM public.wallet_accounts
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_wallet IS NULL THEN
      INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
      VALUES (p_user_id, 0.00, 0.00, 'INR')
      RETURNING * INTO v_wallet;
    END IF;

    UPDATE public.wallet_accounts
    SET balance = balance + v_wallet_amount,
        updated_at = now()
    WHERE user_id = p_user_id;

    INSERT INTO public.wallet_transactions (
      user_id,
      amount,
      type,
      description,
      reference_id,
      reason,
      balance_before,
      balance_after,
      closing_balance,
      order_id,
      payment_id,
      refund_id,
      idempotency_key,
      status
    ) VALUES (
      p_user_id,
      v_wallet_amount,
      'credit'::public.wallet_tx_type,
      'Refund credit for Order ' || v_order.order_number,
      v_order.order_number,
      'refund',
      v_wallet.balance,
      v_wallet.balance + v_wallet_amount,
      v_wallet.balance + v_wallet_amount,
      p_order_id,
      v_payment.id,
      v_refund_id,
      'refund_credit_' || v_refund_id || '_wallet',
      'completed'
    ) ON CONFLICT (refund_id, reason) WHERE reason = 'refund' DO NOTHING;

    INSERT INTO public.refund_components (
      refund_id,
      method,
      amount,
      status,
      processed_at,
      metadata
    ) VALUES (
      v_refund_id,
      'wallet',
      v_wallet_amount,
      'processed',
      now(),
      jsonb_build_object('source', 'instant_wallet_credit')
    );
  END IF;

  -- 11. Create Gateway (Razorpay) Refund Component (if gateway portion > 0)
  IF v_gateway_amount > 0.00 THEN
    INSERT INTO public.refund_components (
      refund_id,
      method,
      amount,
      status,
      metadata
    ) VALUES (
      v_refund_id,
      'razorpay',
      v_gateway_amount,
      'processing',
      jsonb_build_object('gateway_payment_id', v_payment.gateway_payment_id)
    );
  ELSE
    -- If wallet-only, mark payment fully refunded immediately
    UPDATE public.payments
    SET status = 'refunded',
        updated_at = now()
    WHERE id = v_payment.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'refund_id', v_refund_id,
    'order_id', p_order_id,
    'order_number', v_order.order_number,
    'total_amount', v_total_refund,
    'wallet_refund_amount', v_wallet_amount,
    'gateway_refund_amount', v_gateway_amount,
    'gateway_payment_id', v_payment.gateway_payment_id,
    'status', v_initial_refund_status,
    'requires_gateway_refund', (v_gateway_amount > 0.00)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 16. RPC: RECORD GATEWAY REFUND SUBMISSION ATOMIC (SERVICE_ROLE ONLY)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_record_gateway_refund_submission_atomic(
  p_refund_id uuid,
  p_gateway_refund_id text,
  p_provider_status text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_refund record;
  v_component_status text;
  v_all_processed boolean;
BEGIN
  SELECT * INTO v_refund
  FROM public.refunds
  WHERE id = p_refund_id
  FOR UPDATE;

  IF v_refund IS NULL THEN
    RAISE EXCEPTION 'REFUND_NOT_FOUND: Refund record % not found', p_refund_id USING ERRCODE = 'P0011';
  END IF;

  v_component_status := CASE
    WHEN p_error_code IS NOT NULL THEN 'failed'
    WHEN p_provider_status = 'processed' THEN 'processed'
    ELSE 'processing'
  END;

  UPDATE public.refund_components
  SET gateway_refund_id = COALESCE(p_gateway_refund_id, gateway_refund_id),
      provider_status = p_provider_status,
      status = v_component_status,
      processed_at = CASE WHEN v_component_status = 'processed' THEN now() ELSE processed_at END,
      failed_at = CASE WHEN v_component_status = 'failed' THEN now() ELSE NULL END,
      error_code = p_error_code,
      error_message = p_error_message,
      updated_at = now()
  WHERE refund_id = p_refund_id AND method = 'razorpay';

  -- Check if all components for this refund are now processed
  SELECT (COUNT(*) = COUNT(*) FILTER (WHERE status = 'processed'))
  INTO v_all_processed
  FROM public.refund_components
  WHERE refund_id = p_refund_id;

  IF v_all_processed THEN
    UPDATE public.refunds
    SET status = 'processed',
        processed_at = now(),
        updated_at = now()
    WHERE id = p_refund_id;

    UPDATE public.payments
    SET status = 'refunded',
        updated_at = now()
    WHERE id = v_refund.payment_id;
  ELSIF v_component_status = 'failed' THEN
    UPDATE public.refunds
    SET status = 'failed',
        failed_at = now(),
        error_code = p_error_code,
        error_message = p_error_message,
        updated_at = now()
    WHERE id = p_refund_id AND status <> 'processed';
  ELSE
    UPDATE public.refunds
    SET status = 'processing',
        updated_at = now()
    WHERE id = p_refund_id AND status <> 'processed';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'refund_id', p_refund_id,
    'gateway_refund_id', p_gateway_refund_id,
    'status', v_component_status,
    'all_processed', v_all_processed
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 17. STRICT LEAST-PRIVILEGE FUNCTION GRANTS
-- -----------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.rpc_adjust_wallet_atomic(uuid, numeric, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_adjust_wallet_atomic(uuid, numeric, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_calculate_wallet_allocation(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_wallet_allocation(uuid, numeric) TO service_role, authenticated;

REVOKE ALL ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_checkout_quote(uuid, uuid, uuid, text, boolean) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_reserve_wallet_for_order_atomic(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reserve_wallet_for_order_atomic(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_confirm_wallet_only_order_atomic(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_confirm_wallet_only_order_atomic(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_confirm_mixed_payment_atomic(uuid, text, text, text, text, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_confirm_mixed_payment_atomic(uuid, text, text, text, text, text, bigint) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_fail_razorpay_initialization_atomic(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_fail_razorpay_initialization_atomic(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_record_razorpay_payment_failure_atomic(uuid, text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_razorpay_payment_failure_atomic(uuid, text, text, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_prepare_razorpay_retry_atomic(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_razorpay_retry_atomic(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_expire_pending_razorpay_orders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_expire_pending_razorpay_orders() TO service_role;

REVOKE ALL ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_prepare_order_cancellation_refund_atomic(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_order_cancellation_refund_atomic(uuid, uuid, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_record_gateway_refund_submission_atomic(uuid, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_gateway_refund_submission_atomic(uuid, text, text, text, text) TO service_role;
