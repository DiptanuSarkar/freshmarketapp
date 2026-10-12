-- =============================================================================
-- Migration: 20261013031500_fix_pure_gateway_refund_split.sql
-- Description: Ensures gateway_amount fallback in rpc_prepare_order_cancellation_refund_atomic
--              and rpc_set_payment_gateway_order for pure gateway payments.
-- =============================================================================

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
      gateway_amount = CASE
        WHEN COALESCE(gateway_amount, 0.00) = 0.00 AND COALESCE(wallet_amount, 0.00) = 0.00 THEN amount
        ELSE gateway_amount
      END,
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

REVOKE ALL ON FUNCTION public.rpc_set_payment_gateway_order(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_set_payment_gateway_order(uuid, uuid, text) TO service_role;

-- -----------------------------------------------------------------------------
-- UPDATE rpc_prepare_order_cancellation_refund_atomic with gateway fallback
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

  -- Fallback: If gateway_amount was not populated (pure gateway payment where gateway_amount was 0),
  -- deduce gateway_amount from total payment amount minus wallet_amount
  IF v_gateway_amount = 0.00 AND v_wallet_amount < v_payment.amount THEN
    v_gateway_amount := v_payment.amount - v_wallet_amount;
  END IF;

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

REVOKE ALL ON FUNCTION public.rpc_prepare_order_cancellation_refund_atomic(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_order_cancellation_refund_atomic(uuid, uuid, text, text) TO service_role;
