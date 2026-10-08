-- =============================================================================
-- Migration: 20261007000002_payment_status_cancelled_consistency.sql
-- Description: Session 4V Payment Status 'cancelled' Consistency Fix
--   1. Add 'cancelled' to public.payment_status enum
--   2. Add cancelled_at column to public.orders if not exists
--   3. Update rpc_cancel_order_atomic to canonically set payment status to 'cancelled'
--   4. Ensure strict privilege revocation from PUBLIC, anon, authenticated
-- =============================================================================

-- Step 1: Add 'cancelled' value to public.payment_status enum
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumtypid = 'public.payment_status'::regtype
      AND enumlabel = 'cancelled'
  ) THEN
    ALTER TYPE public.payment_status ADD VALUE 'cancelled';
  END IF;
END $$;

-- Step 2: Add cancelled_at column to orders if not exists
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

-- Step 3: Replace rpc_cancel_order_atomic with canonical 'cancelled' payment state
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

  -- 3. Check Cancellation Eligibility (Only 'placed' or 'confirmed')
  IF v_order.status NOT IN ('placed', 'confirmed') THEN
    RAISE EXCEPTION 'ORDER_NOT_CANCELLABLE: Orders in "%" stage cannot be cancelled by customer', v_order.status USING ERRCODE = 'P0012';
  END IF;

  -- 4. Lock & Release Inventory Reservations atomically
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

  -- 6. Update COD Payment Record to Canonical 'cancelled' State
  UPDATE public.payments
  SET status = 'cancelled',
      updated_at = now()
  WHERE order_id = p_order_id AND status = 'pending';

  -- 7. Update Order Status and Payment Status
  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = 'cancelled',
      cancelled_reason = p_reason,
      cancelled_at = now(),
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
    'payment_status', 'cancelled',
    'cancelled_reason', p_reason
  );
END;
$$;

-- Step 4: Strict Least-Privilege Grants
REVOKE ALL ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_order_atomic(uuid, uuid, text) TO service_role;
