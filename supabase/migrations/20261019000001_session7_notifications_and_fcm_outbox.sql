-- =============================================================================
-- Migration: 20261019000001_session7_notifications_and_fcm_outbox.sql
-- Description:
-- 1. Enhances fcm_tokens with last_seen_at and creates token registration/deactivation RPCs
-- 2. Creates durable notification_push_jobs and notification_push_deliveries outbox tables
-- 3. Implements atomic, idempotent rpc_create_customer_notification_atomic (service_role only)
-- 4. Implements atomic rpc_claim_pending_push_jobs with FOR UPDATE SKIP LOCKED
-- 5. Implements server-side trigger on order_status_history for admin/system status push automation
-- =============================================================================

-- 1. Enhance fcm_tokens schema
ALTER TABLE public.fcm_tokens
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz DEFAULT now();

-- 2. Authenticated RPC: Register / Transfer FCM Device Token
CREATE OR REPLACE FUNCTION public.rpc_register_fcm_token(
  p_token text,
  p_device_type text DEFAULT 'android'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RAISE EXCEPTION 'FCM token cannot be empty.' USING ERRCODE = '22023';
  END IF;

  -- Deactivate this token if previously registered to any other user
  UPDATE public.fcm_tokens
  SET is_active = false,
      updated_at = now()
  WHERE token = p_token
    AND user_id <> v_user_id
    AND is_active = true;

  -- Upsert token record for the current authenticated user
  IF EXISTS (
    SELECT 1 FROM public.fcm_tokens
    WHERE user_id = v_user_id AND token = p_token
  ) THEN
    UPDATE public.fcm_tokens
    SET is_active = true,
        device_type = COALESCE(p_device_type, device_type, 'android'),
        updated_at = now(),
        last_seen_at = now()
    WHERE user_id = v_user_id AND token = p_token;
  ELSE
    INSERT INTO public.fcm_tokens (
      user_id,
      token,
      device_type,
      is_active,
      created_at,
      updated_at,
      last_seen_at
    ) VALUES (
      v_user_id,
      p_token,
      COALESCE(p_device_type, 'android'),
      true,
      now(),
      now(),
      now()
    );
  END IF;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_register_fcm_token(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_register_fcm_token(text, text) TO authenticated, service_role;

-- 3. Authenticated RPC: Unregister FCM Device Token on Logout
CREATE OR REPLACE FUNCTION public.rpc_unregister_fcm_token(
  p_token text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    -- If already logged out from auth perspective, allow graceful exit
    RETURN false;
  END IF;

  UPDATE public.fcm_tokens
  SET is_active = false,
      updated_at = now()
  WHERE token = p_token
    AND user_id = v_user_id
    AND is_active = true;

  RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_unregister_fcm_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_unregister_fcm_token(text) TO authenticated, service_role;

-- 4. Create Durable Notification Push Outbox Tables
CREATE TABLE IF NOT EXISTS public.notification_push_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
  attempt_count int NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error_code text,
  last_error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_jobs_status_next
  ON public.notification_push_jobs (status, next_attempt_at)
  WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS idx_push_jobs_user
  ON public.notification_push_jobs (user_id);

CREATE TABLE IF NOT EXISTS public.notification_push_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.notifications(id) ON DELETE CASCADE,
  job_id uuid REFERENCES public.notification_push_jobs(id) ON DELETE CASCADE,
  fcm_token_id uuid REFERENCES public.fcm_tokens(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'invalid_token')),
  provider_message_id text,
  attempts int NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  UNIQUE (notification_id, fcm_token_id)
);

CREATE INDEX IF NOT EXISTS idx_push_deliveries_job
  ON public.notification_push_deliveries (job_id);

-- Enable RLS on push tables (Admin and service_role only)
ALTER TABLE public.notification_push_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_push_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS push_jobs_admin_all ON public.notification_push_jobs;
CREATE POLICY push_jobs_admin_all ON public.notification_push_jobs
  FOR ALL TO authenticated
  USING (private.has_role('admin'::public.app_role))
  WITH CHECK (private.has_role('admin'::public.app_role));

DROP POLICY IF EXISTS push_deliveries_admin_all ON public.notification_push_deliveries;
CREATE POLICY push_deliveries_admin_all ON public.notification_push_deliveries
  FOR ALL TO authenticated
  USING (private.has_role('admin'::public.app_role))
  WITH CHECK (private.has_role('admin'::public.app_role));

-- 5. Central Server Notification Creation RPC (Idempotent by event_key)
CREATE OR REPLACE FUNCTION public.rpc_create_customer_notification_atomic(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text,
  p_data jsonb,
  p_event_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_notification_id uuid;
  v_job_id uuid;
  v_existing_job RECORD;
BEGIN
  -- 1. Check for existing event key to ensure idempotency across races
  SELECT id, notification_id INTO v_existing_job
  FROM public.notification_push_jobs
  WHERE event_key = p_event_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'notification_id', v_existing_job.notification_id,
      'job_id', v_existing_job.id
    );
  END IF;

  -- 2. Insert authoritative in-app notification row
  INSERT INTO public.notifications (
    user_id,
    title,
    body,
    type,
    data,
    is_read,
    created_at
  ) VALUES (
    p_user_id,
    p_title,
    p_body,
    COALESCE(p_type, 'info'),
    COALESCE(p_data, '{}'::jsonb),
    false,
    now()
  )
  RETURNING id INTO v_notification_id;

  -- 3. Insert push outbox job
  INSERT INTO public.notification_push_jobs (
    notification_id,
    user_id,
    event_key,
    status,
    attempt_count,
    next_attempt_at,
    created_at,
    updated_at
  ) VALUES (
    v_notification_id,
    p_user_id,
    p_event_key,
    'pending',
    0,
    now(),
    now(),
    now()
  )
  ON CONFLICT (event_key) DO UPDATE
    SET updated_at = now()
  RETURNING id INTO v_job_id;

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'notification_id', v_notification_id,
    'job_id', v_job_id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_create_customer_notification_atomic FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_customer_notification_atomic TO service_role;

-- 6. Atomic Claim of Pending Push Jobs with SKIP LOCKED
CREATE OR REPLACE FUNCTION public.rpc_claim_pending_push_jobs(p_limit int DEFAULT 20)
RETURNS TABLE (
  job_id uuid,
  notification_id uuid,
  user_id uuid,
  event_key text,
  attempt_count int,
  title text,
  body text,
  notif_type text,
  data jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    SELECT j.id
    FROM public.notification_push_jobs j
    WHERE j.status = 'pending'
      AND j.next_attempt_at <= now()
    ORDER BY j.next_attempt_at ASC
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  ),
  updated AS (
    UPDATE public.notification_push_jobs j
    SET status = 'processing',
        updated_at = now()
    FROM claimed
    WHERE j.id = claimed.id
    RETURNING j.id, j.notification_id, j.user_id, j.event_key, j.attempt_count
  )
  SELECT
    u.id AS job_id,
    u.notification_id,
    u.user_id,
    u.event_key,
    u.attempt_count,
    n.title,
    n.body,
    n.type AS notif_type,
    n.data
  FROM updated u
  JOIN public.notifications n ON n.id = u.notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_claim_pending_push_jobs FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_claim_pending_push_jobs TO service_role;

-- 7. Trigger on order_status_history for Universal Server-Side Push Automation (Phase 28)
CREATE OR REPLACE FUNCTION public.trg_order_status_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_order_number text;
  v_title text;
  v_body text;
  v_type text;
  v_event_key text;
BEGIN
  -- Only process customer-facing lifecycle statuses
  IF NEW.status NOT IN ('confirmed', 'preparing', 'packed', 'out_for_delivery', 'delivered', 'cancelled') THEN
    RETURN NEW;
  END IF;

  SELECT user_id, order_number INTO v_user_id, v_order_number
  FROM public.orders
  WHERE id = NEW.order_id;

  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_type := 'order_' || NEW.status;
  v_event_key := 'order:' || NEW.order_id::text || ':' || NEW.status;

  CASE NEW.status
    WHEN 'confirmed' THEN
      v_title := 'Order Confirmed';
      v_body := 'Your order #' || v_order_number || ' has been confirmed.';
    WHEN 'preparing' THEN
      v_title := 'Order Being Prepared';
      v_body := 'Your order #' || v_order_number || ' is being freshly prepared.';
    WHEN 'packed' THEN
      v_title := 'Order Packed';
      v_body := 'Your order #' || v_order_number || ' has been safely packed.';
    WHEN 'out_for_delivery' THEN
      v_title := 'Out for Delivery';
      v_body := 'Your order #' || v_order_number || ' is out for delivery with our delivery partner.';
    WHEN 'delivered' THEN
      v_title := 'Order Delivered';
      v_body := 'Your order #' || v_order_number || ' has been delivered. Enjoy fresh!';
    WHEN 'cancelled' THEN
      v_title := 'Order Cancelled';
      v_body := 'Your order #' || v_order_number || ' has been cancelled.';
    ELSE
      v_title := 'Order Update';
      v_body := 'Your order #' || v_order_number || ' status is now ' || NEW.status || '.';
  END CASE;

  PERFORM public.rpc_create_customer_notification_atomic(
    v_user_id,
    v_title,
    v_body,
    v_type,
    jsonb_build_object(
      'order_id', NEW.order_id,
      'order_number', v_order_number,
      'status', NEW.status
    ),
    v_event_key
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_status_notification_enqueue ON public.order_status_history;
CREATE TRIGGER trg_order_status_notification_enqueue
  AFTER INSERT ON public.order_status_history
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_order_status_notification();
