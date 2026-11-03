-- Migration 20261102000002_add_products_rating_columns.sql
-- Adds cached aggregate rating and review_count columns to public.products
-- and fixes unused variable warning in rpc_calculate_wallet_allocation

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS rating numeric(3,2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS review_count int DEFAULT 0;

-- Backfill from approved reviews
UPDATE public.products p
SET rating = COALESCE((SELECT ROUND(AVG(pr.rating)::numeric, 2) FROM public.product_reviews pr WHERE pr.product_id = p.id AND pr.is_approved = true), 0.0),
    review_count = COALESCE((SELECT COUNT(*)::int FROM public.product_reviews pr WHERE pr.product_id = p.id AND pr.is_approved = true), 0);

-- Update rpc_calculate_wallet_allocation to eliminate unused variable warning
CREATE OR REPLACE FUNCTION public.rpc_calculate_wallet_allocation(
  p_user_id uuid,
  p_order_total numeric,
  p_use_wallet boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_available numeric(10,2) := 0.0;
  v_wallet_deduction numeric(10,2) := 0.0;
  v_gateway_payable numeric(10,2) := 0.0;
  v_is_wallet_only boolean := false;
BEGIN
  IF p_order_total <= 0 THEN
    RETURN jsonb_build_object(
      'wallet_deduction', 0.0,
      'gateway_payable', 0.0,
      'is_wallet_only', false,
      'available_balance', 0.0
    );
  END IF;

  IF p_use_wallet THEN
    SELECT (balance - reserved_balance) INTO v_available
    FROM public.wallet_accounts
    WHERE user_id = p_user_id;

    v_available := GREATEST(0.0, COALESCE(v_available, 0.0));

    IF v_available >= p_order_total THEN
      v_wallet_deduction := p_order_total;
      v_gateway_payable := 0.0;
      v_is_wallet_only := true;
    ELSE
      v_wallet_deduction := v_available;
      v_gateway_payable := p_order_total - v_available;
      v_is_wallet_only := false;
    END IF;
  ELSE
    v_wallet_deduction := 0.0;
    v_gateway_payable := p_order_total;
    v_is_wallet_only := false;
  END IF;

  RETURN jsonb_build_object(
    'wallet_deduction', v_wallet_deduction,
    'gateway_payable', v_gateway_payable,
    'is_wallet_only', v_is_wallet_only,
    'available_balance', v_available
  );
END;
$$;
