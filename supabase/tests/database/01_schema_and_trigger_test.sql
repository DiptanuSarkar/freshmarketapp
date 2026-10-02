BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- 1. Verify Public Seed Data Actually Exists (Section L - non-zero assertion)
SELECT cmp_ok(
  (SELECT count(*)::int FROM public.categories),
  '>=',
  5,
  'Public seed data: at least 5 categories must exist'
);

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.products),
  '>=',
  5,
  'Public seed data: at least 5 products must exist'
);

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.product_variants),
  '>=',
  6,
  'Public seed data: at least 6 product variants must exist'
);

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.service_areas),
  '>=',
  3,
  'Public seed data: at least 3 service areas must exist'
);

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.delivery_slots),
  '>=',
  3,
  'Public seed data: at least 3 delivery slots must exist'
);

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.coupons),
  '>=',
  3,
  'Public seed data: at least 3 coupons must exist'
);

-- 2. Verify Auth User Trigger for Real (Section N)
-- Create a new auth user dynamically to test the trigger
DO $$
DECLARE
  v_test_uid uuid := '99999999-0000-0000-0000-000000000001'::uuid;
BEGIN
  -- Insert into auth.users to fire handle_new_user trigger
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) VALUES (
    v_test_uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'charlie_trigger_test@freshmarket.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email"}',
    '{"full_name":"Charlie Trigger Test"}',
    now(),
    now()
  );
END $$;

-- Verify Profile was created automatically
SELECT is(
  (SELECT count(*)::int FROM public.profiles WHERE id = '99999999-0000-0000-0000-000000000001'),
  1,
  'Auth trigger: automatically created profile'
);

SELECT is(
  (SELECT full_name FROM public.profiles WHERE id = '99999999-0000-0000-0000-000000000001'),
  'Charlie Trigger Test',
  'Auth trigger: correctly set full_name in profile'
);

-- Verify Customer Role was assigned in private schema
SELECT is(
  (SELECT count(*)::int FROM private.user_roles WHERE user_id = '99999999-0000-0000-0000-000000000001' AND role = 'customer'::public.app_role),
  1,
  'Auth trigger: automatically assigned customer role in private.user_roles'
);

-- Verify Customer Preferences were created
SELECT is(
  (SELECT count(*)::int FROM public.customer_preferences WHERE user_id = '99999999-0000-0000-0000-000000000001'),
  1,
  'Auth trigger: automatically created customer preferences'
);

-- Verify Wallet Account was created with balance = 0.00
SELECT is(
  (SELECT count(*)::int FROM public.wallet_accounts WHERE user_id = '99999999-0000-0000-0000-000000000001'),
  1,
  'Auth trigger: automatically created wallet account'
);

SELECT is(
  (SELECT balance FROM public.wallet_accounts WHERE user_id = '99999999-0000-0000-0000-000000000001'),
  0.00,
  'Auth trigger: verified initial wallet balance is exactly 0.00'
);

-- Verify Shopping Cart was created
SELECT is(
  (SELECT count(*)::int FROM public.carts WHERE user_id = '99999999-0000-0000-0000-000000000001'),
  1,
  'Auth trigger: automatically created initial shopping cart'
);

-- 3. Verify FCM Token Uniqueness Model (Section H)
DO $$
BEGIN
  -- Insert active token for user 1
  INSERT INTO public.fcm_tokens (user_id, token, device_type, is_active)
  VALUES ('22222222-0000-0000-0000-000000000001', 'device_token_xyz_123', 'android', true);

  -- Insert same active token for user 2 (should trigger transfer/deactivation of previous)
  INSERT INTO public.fcm_tokens (user_id, token, device_type, is_active)
  VALUES ('33333333-0000-0000-0000-000000000002', 'device_token_xyz_123', 'ios', true);
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.fcm_tokens WHERE token = 'device_token_xyz_123' AND is_active = true),
  1,
  'FCM token uniqueness: exactly one user owns the active device token'
);

SELECT is(
  (SELECT user_id FROM public.fcm_tokens WHERE token = 'device_token_xyz_123' AND is_active = true),
  '33333333-0000-0000-0000-000000000002'::uuid,
  'FCM token uniqueness: token transferred to current authenticated user'
);

SELECT * FROM finish();
ROLLBACK;
