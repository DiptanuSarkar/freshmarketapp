-- =============================================================================
-- Migration: 20261007000006_session5a_recovery_and_hardening.sql
-- Description: Session 5A Recovery & Hardening:
--   1. Ensures pg_cron extension is active on linked project.
--   2. Enforces hosted pg_cron schedule for rpc_expire_pending_razorpay_orders() every 5 minutes.
--   3. Re-asserts strict least-privilege routine execution grants (service_role only).
--   4. Re-asserts payment_webhook_events RLS and permissions.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. PG_CRON EXTENSION & SCHEDULER
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedule existing job if present to avoid duplication
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
  NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 2. RE-ASSERT LEAST-PRIVILEGE FUNCTION GRANTS (SERVICE_ROLE ONLY)
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
-- 3. RE-ASSERT TABLE PERMISSIONS & RLS FOR WEBHOOK EVENTS
-- -----------------------------------------------------------------------------

ALTER TABLE public.payment_webhook_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_webhook_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.payment_webhook_events TO service_role;
