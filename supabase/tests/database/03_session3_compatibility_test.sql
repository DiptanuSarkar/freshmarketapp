BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- -----------------------------------------------------------------------------
-- 1. Test Delivery Agent Assignment Isolation (Phase 2.1)
-- Delivery Agent A (Dave: 44444444-0000-0000-0000-000000000001)
-- Delivery Agent B (Dan: 44444444-0000-0000-0000-000000000002)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_agent_b uuid := '44444444-0000-0000-0000-000000000002'::uuid;
  v_dummy_order uuid := '55555555-0000-0000-0000-000000000001'::uuid;
  v_assign_a uuid := 'f1000000-0000-0000-0000-000000000001'::uuid;
  v_assign_b uuid := 'f1000000-0000-0000-0000-000000000002'::uuid;
BEGIN
  -- Insert Agent B user if not exists
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_agent_b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'agentb@freshmarket.com', crypt('password123', gen_salt('bf')), '{"provider":"email"}', '{"full_name":"Dan Delivery Agent B"}', now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO private.user_roles (user_id, role)
  VALUES (v_agent_b, 'delivery_agent'::public.app_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Ensure dummy order exists for assignment
  INSERT INTO public.orders (id, order_number, user_id, address_id, delivery_slot_id, subtotal, delivery_fee, total_payable, status)
  VALUES (v_dummy_order, 'ORD-TEST-001', '22222222-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 100.00, 30.00, 130.00, 'placed'::public.order_status)
  ON CONFLICT (id) DO NOTHING;

  -- Insert assignment for Agent A
  INSERT INTO public.delivery_assignments (id, order_id, delivery_agent_id, status)
  VALUES (v_assign_a, v_dummy_order, '44444444-0000-0000-0000-000000000001', 'assigned')
  ON CONFLICT (id) DO NOTHING;

  -- Insert assignment for Agent B
  INSERT INTO public.delivery_assignments (id, order_id, delivery_agent_id, status)
  VALUES (v_assign_b, v_dummy_order, v_agent_b, 'assigned')
  ON CONFLICT (id) DO NOTHING;
END $$;

-- Switch to Agent A
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "44444444-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.delivery_assignments WHERE id = 'f1000000-0000-0000-0000-000000000001'),
  1,
  'Delivery Agent A can SELECT their own assignment'
);

SELECT is(
  (SELECT count(*)::int FROM public.delivery_assignments WHERE id = 'f1000000-0000-0000-0000-000000000002'),
  0,
  'Delivery Agent A CANNOT SELECT Delivery Agent B assignment (isolated)'
);

-- Regular Customer (Alice) Context
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.delivery_assignments),
  0,
  'Regular customer CANNOT SELECT delivery_assignments'
);

-- -----------------------------------------------------------------------------
-- 2. Test Product Variants SKU (Phase 2.2)
-- -----------------------------------------------------------------------------
SET LOCAL ROLE postgres;

SELECT is(
  (SELECT count(*)::int FROM public.product_variants WHERE sku IS NULL),
  0,
  'All product variants have non-null SKU'
);

SELECT is(
  (SELECT count(DISTINCT sku)::int FROM public.product_variants),
  (SELECT count(*)::int FROM public.product_variants),
  'All product variant SKUs are unique'
);

-- -----------------------------------------------------------------------------
-- 3. Test Address Coordinates & Default Constraint (Phase 2.5)
-- -----------------------------------------------------------------------------
-- Invalid latitude check
SELECT throws_ok(
  $$ INSERT INTO public.addresses (user_id, label, recipient_name, phone, address_line1, city, state, pincode, latitude, longitude)
     VALUES ('22222222-0000-0000-0000-000000000001', 'Test', 'Alice', '+919876543210', 'Line 1', 'BLR', 'KA', '560038', 95.0, 77.0) $$,
  '23514',
  NULL,
  'Invalid latitude (> 90) fails check constraint (23514)'
);

-- Invalid longitude check
SELECT throws_ok(
  $$ INSERT INTO public.addresses (user_id, label, recipient_name, phone, address_line1, city, state, pincode, latitude, longitude)
     VALUES ('22222222-0000-0000-0000-000000000001', 'Test', 'Alice', '+919876543210', 'Line 1', 'BLR', 'KA', '560038', 12.0, 195.0) $$,
  '23514',
  NULL,
  'Invalid longitude (> 180) fails check constraint (23514)'
);

-- Partial unique index on is_default
SELECT throws_ok(
  $$ INSERT INTO public.addresses (user_id, label, recipient_name, phone, address_line1, city, state, pincode, is_default)
     VALUES ('22222222-0000-0000-0000-000000000001', 'Test 2', 'Alice', '+919876543210', 'Line 2', 'BLR', 'KA', '560038', true) $$,
  '23505',
  NULL,
  'Second default address for same user is rejected by partial unique index (23505)'
);

-- -----------------------------------------------------------------------------
-- 4. Test Customer Support Storage (Phase 2.4)
-- -----------------------------------------------------------------------------
-- Alice inserts contact message
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT lives_ok(
  $$ INSERT INTO public.contact_messages (user_id, name, email, message)
     VALUES ('22222222-0000-0000-0000-000000000001', 'Alice', 'alice@freshmarket.com', 'Great service!') $$,
  'Alice can submit support contact message'
);

-- Alice tries to submit message as Bob
SELECT throws_ok(
  $$ INSERT INTO public.contact_messages (user_id, name, email, message)
     VALUES ('33333333-0000-0000-0000-000000000002', 'Bob', 'bob@freshmarket.com', 'Impersonated') $$,
  '42501',
  NULL,
  'Alice cannot submit support contact message for Bob'
);

-- Bob cannot read Alice message
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "33333333-0000-0000-0000-000000000002", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.contact_messages WHERE user_id = '22222222-0000-0000-0000-000000000001'),
  0,
  'Bob cannot SELECT Alice contact message (customer isolation)'
);

-- -----------------------------------------------------------------------------
-- 5. Public Reads On Catalog Intact
-- -----------------------------------------------------------------------------
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims" = '{"role": "anon"}';

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.products WHERE is_active = true),
  '>=',
  1,
  'Anon can SELECT active products'
);

ROLLBACK;
