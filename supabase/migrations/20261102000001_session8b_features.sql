-- =============================================================================
-- Migration: 20261102000001_session8b_features.sql
-- Description: Session 8B — Transactional Email Outbox, App Support Settings,
-- and Verified-Purchase Reviews & Ratings RPCs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. DURABLE TRANSACTIONAL EMAIL OUTBOX
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.transactional_email_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_key text NOT NULL,
  event_type text NOT NULL,
  recipient_email text NOT NULL,
  template_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
  attempt_count int NOT NULL DEFAULT 0,
  max_attempts int NOT NULL DEFAULT 5,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  provider_message_id text,
  last_error_code text,
  last_error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT transactional_email_jobs_event_key_key UNIQUE (event_key)
);

CREATE INDEX IF NOT EXISTS idx_email_jobs_pending
ON public.transactional_email_jobs (status, next_attempt_at)
WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS idx_email_jobs_user_id
ON public.transactional_email_jobs (user_id);

ALTER TABLE public.transactional_email_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transactional_email_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.transactional_email_jobs TO service_role;

-- 1.1 rpc_enqueue_transactional_email
CREATE OR REPLACE FUNCTION public.rpc_enqueue_transactional_email(
  p_user_id uuid,
  p_event_key text,
  p_event_type text,
  p_recipient_email text,
  p_template_key text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job_id uuid;
  v_existing record;
BEGIN
  SELECT id, status INTO v_existing
  FROM public.transactional_email_jobs
  WHERE event_key = p_event_key;

  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'job_id', v_existing.id,
      'is_duplicate', true,
      'status', v_existing.status
    );
  END IF;

  INSERT INTO public.transactional_email_jobs (
    user_id,
    event_key,
    event_type,
    recipient_email,
    template_key,
    payload,
    status,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_event_key,
    p_event_type,
    p_recipient_email,
    p_template_key,
    COALESCE(p_payload, '{}'::jsonb),
    'pending',
    now(),
    now()
  )
  RETURNING id INTO v_job_id;

  RETURN jsonb_build_object(
    'success', true,
    'job_id', v_job_id,
    'is_duplicate', false,
    'status', 'pending'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_enqueue_transactional_email(uuid, text, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_enqueue_transactional_email(uuid, text, text, text, text, jsonb) TO service_role;

-- 1.2 rpc_claim_pending_email_jobs
CREATE OR REPLACE FUNCTION public.rpc_claim_pending_email_jobs(
  p_limit int DEFAULT 10
)
RETURNS TABLE (
  job_id uuid,
  user_id uuid,
  event_key text,
  event_type text,
  recipient_email text,
  template_key text,
  payload jsonb,
  attempt_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  WITH claimable AS (
    SELECT id
    FROM public.transactional_email_jobs
    WHERE status = 'pending'
      AND next_attempt_at <= now()
    ORDER BY next_attempt_at ASC
    LIMIT LEAST(GREATEST(p_limit, 1), 50)
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.transactional_email_jobs j
  SET status = 'processing',
      attempt_count = j.attempt_count + 1,
      updated_at = now()
  FROM claimable
  WHERE j.id = claimable.id
  RETURNING j.id, j.user_id, j.event_key, j.event_type, j.recipient_email, j.template_key, j.payload, j.attempt_count;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_claim_pending_email_jobs(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_claim_pending_email_jobs(int) TO service_role;

-- 1.3 rpc_record_email_job_result
CREATE OR REPLACE FUNCTION public.rpc_record_email_job_result(
  p_job_id uuid,
  p_status text,
  p_provider_msg_id text DEFAULT NULL,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL,
  p_is_transient boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job record;
  v_next_attempt timestamptz;
BEGIN
  SELECT * INTO v_job
  FROM public.transactional_email_jobs
  WHERE id = p_job_id;

  IF v_job.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'JOB_NOT_FOUND');
  END IF;

  IF p_status = 'sent' THEN
    UPDATE public.transactional_email_jobs
    SET status = 'sent',
        provider_message_id = p_provider_msg_id,
        sent_at = now(),
        updated_at = now()
    WHERE id = p_job_id;
    RETURN jsonb_build_object('success', true, 'status', 'sent');
  END IF;

  IF p_is_transient AND v_job.attempt_count < v_job.max_attempts THEN
    v_next_attempt := now() + (interval '1 minute' * POWER(2, LEAST(v_job.attempt_count, 6)));
    UPDATE public.transactional_email_jobs
    SET status = 'pending',
        next_attempt_at = v_next_attempt,
        last_error_code = p_error_code,
        last_error_message = p_error_message,
        updated_at = now()
    WHERE id = p_job_id;
    RETURN jsonb_build_object('success', true, 'status', 'pending', 'retry_at', v_next_attempt);
  ELSE
    UPDATE public.transactional_email_jobs
    SET status = 'failed',
        last_error_code = p_error_code,
        last_error_message = p_error_message,
        updated_at = now()
    WHERE id = p_job_id;
    RETURN jsonb_build_object('success', true, 'status', 'failed');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_record_email_job_result(uuid, text, text, text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_email_job_result(uuid, text, text, text, text, boolean) TO service_role;


-- -----------------------------------------------------------------------------
-- 2. APP SUPPORT CONFIGURATION IN public.app_settings
-- -----------------------------------------------------------------------------

INSERT INTO public.app_settings (key, value, description, is_public, updated_at)
VALUES (
  'support_config',
  jsonb_build_object(
    'whatsapp_number', '918787630683',
    'support_phone', '+91 8787630683',
    'support_email', 'care@freshmarket.in',
    'business_hours', '6:00 AM - 10:00 PM (Daily)',
    'help_desk_title', 'FreshMarket Customer Care'
  ),
  'Authoritative customer support channels and helpline configuration',
  true,
  now()
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  is_public = true,
  updated_at = now();

CREATE OR REPLACE FUNCTION public.rpc_get_support_config()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT value
  FROM public.app_settings
  WHERE key = 'support_config' AND is_public = true
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_support_config() TO anon, authenticated;


-- -----------------------------------------------------------------------------
-- 3. VERIFIED-PURCHASE PRODUCT REVIEWS & RATINGS
-- -----------------------------------------------------------------------------

ALTER TABLE public.product_reviews ADD COLUMN IF NOT EXISTS title text;

-- 3.1 rpc_check_review_eligibility
CREATE OR REPLACE FUNCTION public.rpc_check_review_eligibility(
  p_product_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_has_purchased boolean := false;
  v_already_reviewed boolean := false;
  v_existing_review jsonb := NULL;
  v_eligible_order_id uuid := NULL;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'eligible', false,
      'has_purchased', false,
      'already_reviewed', false,
      'reason', 'AUTHENTICATION_REQUIRED'
    );
  END IF;

  SELECT jsonb_build_object(
    'id', pr.id,
    'rating', pr.rating,
    'title', pr.title,
    'review_text', pr.review_text,
    'is_verified_purchase', pr.is_verified_purchase,
    'created_at', pr.created_at,
    'updated_at', pr.updated_at
  ) INTO v_existing_review
  FROM public.product_reviews pr
  WHERE pr.product_id = p_product_id AND pr.user_id = v_user_id;

  IF v_existing_review IS NOT NULL THEN
    v_already_reviewed := true;
  END IF;

  SELECT o.id INTO v_eligible_order_id
  FROM public.orders o
  JOIN public.order_items oi ON oi.order_id = o.id
  JOIN public.product_variants pv ON pv.id = oi.variant_id
  WHERE o.user_id = v_user_id
    AND pv.product_id = p_product_id
    AND o.status IN ('delivered', 'confirmed', 'placed')
  ORDER BY o.created_at DESC
  LIMIT 1;

  IF v_eligible_order_id IS NOT NULL THEN
    v_has_purchased := true;
  END IF;

  RETURN jsonb_build_object(
    'eligible', v_has_purchased,
    'has_purchased', v_has_purchased,
    'already_reviewed', v_already_reviewed,
    'order_id', v_eligible_order_id,
    'existing_review', v_existing_review
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_check_review_eligibility(uuid) TO authenticated;

-- 3.2 rpc_submit_product_review
CREATE OR REPLACE FUNCTION public.rpc_submit_product_review(
  p_product_id uuid,
  p_rating int,
  p_title text DEFAULT NULL,
  p_review_text text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_eligible_order_id uuid;
  v_review_id uuid;
  v_is_verified boolean := false;
  v_avg_rating numeric(3,1) := 0.0;
  v_count int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in to submit a review' USING ERRCODE = 'P0001';
  END IF;

  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'INVALID_RATING: Rating must be an integer between 1 and 5' USING ERRCODE = 'P0002';
  END IF;

  SELECT o.id INTO v_eligible_order_id
  FROM public.orders o
  JOIN public.order_items oi ON oi.order_id = o.id
  JOIN public.product_variants pv ON pv.id = oi.variant_id
  WHERE o.user_id = v_user_id
    AND pv.product_id = p_product_id
    AND o.status IN ('delivered', 'confirmed', 'placed')
  ORDER BY o.created_at DESC
  LIMIT 1;

  IF v_eligible_order_id IS NULL THEN
    RAISE EXCEPTION 'UNVERIFIED_PURCHASE: You may only review products from eligible orders' USING ERRCODE = 'P0003';
  END IF;

  v_is_verified := true;

  INSERT INTO public.product_reviews (
    product_id,
    user_id,
    order_id,
    rating,
    title,
    review_text,
    is_verified_purchase,
    is_approved,
    created_at,
    updated_at
  ) VALUES (
    p_product_id,
    v_user_id,
    v_eligible_order_id,
    p_rating,
    p_title,
    p_review_text,
    v_is_verified,
    true,
    now(),
    now()
  )
  ON CONFLICT (product_id, user_id) DO UPDATE SET
    rating = EXCLUDED.rating,
    title = EXCLUDED.title,
    review_text = EXCLUDED.review_text,
    is_verified_purchase = true,
    is_approved = true,
    updated_at = now()
  RETURNING id INTO v_review_id;

  SELECT 
    COALESCE(ROUND(AVG(rating)::numeric, 1), 0.0),
    COUNT(*)::int
  INTO v_avg_rating, v_count
  FROM public.product_reviews
  WHERE product_id = p_product_id AND is_approved = true;

  UPDATE public.products
  SET rating = v_avg_rating,
      review_count = v_count,
      updated_at = now()
  WHERE id = p_product_id;

  RETURN jsonb_build_object(
    'success', true,
    'review_id', v_review_id,
    'rating', p_rating,
    'title', p_title,
    'review_text', p_review_text,
    'is_verified_purchase', v_is_verified,
    'product_average_rating', v_avg_rating,
    'product_review_count', v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_submit_product_review(uuid, int, text, text) TO authenticated;

-- 3.3 rpc_delete_product_review
CREATE OR REPLACE FUNCTION public.rpc_delete_product_review(
  p_review_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_product_id uuid;
  v_avg_rating numeric(3,1) := 0.0;
  v_count int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  SELECT product_id INTO v_product_id
  FROM public.product_reviews
  WHERE id = p_review_id AND user_id = v_user_id;

  IF v_product_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'REVIEW_NOT_FOUND_OR_NOT_OWNER');
  END IF;

  DELETE FROM public.product_reviews
  WHERE id = p_review_id AND user_id = v_user_id;

  SELECT 
    COALESCE(ROUND(AVG(rating)::numeric, 1), 0.0),
    COUNT(*)::int
  INTO v_avg_rating, v_count
  FROM public.product_reviews
  WHERE product_id = v_product_id AND is_approved = true;

  UPDATE public.products
  SET rating = v_avg_rating,
      review_count = v_count,
      updated_at = now()
  WHERE id = v_product_id;

  RETURN jsonb_build_object(
    'success', true,
    'product_id', v_product_id,
    'product_average_rating', v_avg_rating,
    'product_review_count', v_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_delete_product_review(uuid) TO authenticated;

-- 3.4 rpc_get_product_rating_summary
CREATE OR REPLACE FUNCTION public.rpc_get_product_rating_summary(
  p_product_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
DECLARE
  v_avg numeric(3,1) := 0.0;
  v_total int := 0;
  v_distribution jsonb;
BEGIN
  SELECT 
    COALESCE(ROUND(AVG(rating)::numeric, 1), 0.0),
    COUNT(*)::int,
    jsonb_build_object(
      '5', COUNT(*) FILTER (WHERE rating = 5),
      '4', COUNT(*) FILTER (WHERE rating = 4),
      '3', COUNT(*) FILTER (WHERE rating = 3),
      '2', COUNT(*) FILTER (WHERE rating = 2),
      '1', COUNT(*) FILTER (WHERE rating = 1)
    )
  INTO v_avg, v_total, v_distribution
  FROM public.product_reviews
  WHERE product_id = p_product_id AND is_approved = true;

  RETURN jsonb_build_object(
    'average_rating', v_avg,
    'review_count', v_total,
    'rating_distribution', COALESCE(v_distribution, jsonb_build_object('1',0,'2',0,'3',0,'4',0,'5',0))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_product_rating_summary(uuid) TO anon, authenticated;

-- 3.5 rpc_advance_dev_order_status_for_test (service_role only)
CREATE OR REPLACE FUNCTION public.rpc_advance_dev_order_status_for_test(
  p_order_id uuid,
  p_new_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.orders
  SET status = p_new_status::public.order_status,
      updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO public.order_status_history (
    order_id,
    status,
    notes,
    created_at
  ) VALUES (
    p_order_id,
    p_new_status::public.order_status,
    'Test suite transition to ' || p_new_status,
    now()
  );

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id, 'status', p_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_advance_dev_order_status_for_test(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_advance_dev_order_status_for_test(uuid, text) TO service_role;
