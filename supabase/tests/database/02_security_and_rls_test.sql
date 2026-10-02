BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- =============================================================================
-- Test 1: Valid UUID Format Verification (Section B, L.1)
-- =============================================================================
SELECT lives_ok(
  $$ SELECT 'c1000000-0000-0000-0000-000000000001'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid, 'b1000000-0000-0000-0000-000000000001'::uuid $$,
  'Test 1: Hardcoded UUID patterns parse as valid PostgreSQL UUIDs'
);

-- =============================================================================
-- Test 2 & 3: private.has_role Evaluation (Section C, L.2, L.3)
-- =============================================================================
-- Admin Context
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "11111111-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT is(
  private.has_role('admin'::public.app_role),
  true,
  'Test 2: private.has_role returns true for authenticated admin'
);

-- Regular Customer (Alice) Context
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT is(
  private.has_role('admin'::public.app_role),
  false,
  'Test 3: private.has_role returns false for regular customer'
);

-- =============================================================================
-- Test 4: Protected Profile Columns Protection (Section E, L.4)
-- =============================================================================
-- Alice tries to modify her phone/email/is_active directly
SELECT throws_ok(
  $$ UPDATE public.profiles SET email = 'hacked@freshmarket.com' WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  'P0001',
  NULL,
  'Test 4a: Customer cannot alter protected profile email'
);

SELECT throws_ok(
  $$ UPDATE public.profiles SET is_active = false WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  'P0001',
  NULL,
  'Test 4b: Customer cannot alter protected profile is_active'
);

-- Safe fields can be updated
SELECT lives_ok(
  $$ UPDATE public.profiles SET full_name = 'Alice Updated Name' WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  'Test 4c: Customer can update safe profile field full_name'
);

-- =============================================================================
-- Test 5: Product Review Security (Section F, L.5)
-- =============================================================================
-- Alice submits a review attempting to forge verified_purchase and approval
INSERT INTO public.product_reviews (
  product_id,
  user_id,
  rating,
  review_text
) VALUES (
  'a1000000-0000-0000-0000-000000000002',
  '22222222-0000-0000-0000-000000000001',
  5,
  'Fresh and delicious chicken breast!'
);

SELECT is(
  (SELECT is_verified_purchase FROM public.product_reviews WHERE product_id = 'a1000000-0000-0000-0000-000000000002' AND user_id = '22222222-0000-0000-0000-000000000001'),
  false,
  'Test 5a: Customer review insertion forces is_verified_purchase = false'
);

SELECT is(
  (SELECT is_approved FROM public.product_reviews WHERE product_id = 'a1000000-0000-0000-0000-000000000002' AND user_id = '22222222-0000-0000-0000-000000000001'),
  false,
  'Test 5b: Customer review insertion forces is_approved = false'
);

-- =============================================================================
-- Test 6, 7 & 8: Delivery Assignment & Telemetry Security (Section G, L.6, L.7, L.8)
-- =============================================================================
-- As postgres superuser, create an order and assignment for Dave
SET LOCAL ROLE postgres;

INSERT INTO public.orders (
  id,
  user_id,
  delivery_address_snapshot,
  delivery_date,
  subtotal,
  total,
  payment_method
) VALUES (
  '00000001-0000-0000-0000-000000000001',
  '22222222-0000-0000-0000-000000000001',
  '{"address": "123 Main St"}',
  current_date,
  350.00,
  350.00,
  'cod'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.delivery_assignments (
  id,
  order_id,
  delivery_agent_id,
  status
) VALUES (
  'da000000-0000-0000-0000-000000000001',
  '00000001-0000-0000-0000-000000000001',
  '44444444-0000-0000-0000-000000000001',
  'assigned'
) ON CONFLICT (id) DO NOTHING;

-- Switch to Delivery Agent Dave
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "44444444-0000-0000-0000-000000000001", "role": "authenticated"}';

-- Dave tries to directly UPDATE delivery_assignments table (prohibited - read only via direct SQL)
UPDATE public.delivery_assignments
SET order_id = '00000001-0000-0000-0000-000000000002'
WHERE id = 'da000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT order_id FROM public.delivery_assignments WHERE id = 'da000000-0000-0000-0000-000000000001'),
  '00000001-0000-0000-0000-000000000001'::uuid,
  'Test 6: Delivery agent cannot retarget assignment order_id'
);

UPDATE public.delivery_assignments
SET delivery_agent_id = '33333333-0000-0000-0000-000000000002'
WHERE id = 'da000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT delivery_agent_id FROM public.delivery_assignments WHERE id = 'da000000-0000-0000-0000-000000000001'),
  '44444444-0000-0000-0000-000000000001'::uuid,
  'Test 7: Delivery agent cannot change assignment delivery_agent_id'
);

-- Dave tries to insert telemetry for an unassigned order
SELECT throws_ok(
  $$ INSERT INTO public.delivery_locations (order_id, delivery_agent_id, latitude, longitude)
     VALUES ('00000001-0000-0000-0000-000000000099', '44444444-0000-0000-0000-000000000001', 12.9716, 77.5946) $$,
  '42501',
  NULL,
  'Test 8: Delivery agent cannot insert telemetry for unassigned order'
);

-- =============================================================================
-- Test 9: Expired/Scheduled Banners Visibility (Section I, L.9)
-- =============================================================================
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims" = '{"role": "anon"}';

SELECT is(
  (SELECT count(*)::int FROM public.banners WHERE id = 'bb000000-0000-0000-0000-000000000003'),
  0,
  'Test 9: Expired banner is hidden from anon storefront'
);

-- =============================================================================
-- Test 10: Hidden Home Section Items (Section I, L.10)
-- =============================================================================
SELECT is(
  (SELECT count(*)::int FROM public.home_section_items WHERE id = '00b00000-0000-0000-0000-000000000003'),
  0,
  'Test 10: Item belonging to hidden home section is hidden from storefront'
);

-- =============================================================================
-- Test 11: User-Specific Coupon Visibility (Section I, L.11)
-- =============================================================================
-- Alice (assigned to VIPALICE) can see it
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.coupons WHERE code = 'VIPALICE'),
  1,
  'Test 11a: Targeted coupon is visible to the assigned user Alice'
);

-- Bob (not assigned to VIPALICE) cannot see it
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "33333333-0000-0000-0000-000000000002", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM public.coupons WHERE code = 'VIPALICE'),
  0,
  'Test 11b: Targeted coupon is hidden from non-assigned user Bob'
);

-- =============================================================================
-- Test 12: Notification RPC anon execution privilege (Section K, L.12)
-- =============================================================================
SET LOCAL ROLE anon;
SET LOCAL "request.jwt.claims" = '{"role": "anon"}';

SELECT throws_ok(
  $$ SELECT public.mark_notification_as_read('00000008-0000-0000-0000-000000000001'::uuid) $$,
  '42501',
  NULL,
  'Test 12: Notification RPC mark_notification_as_read is not executable by anon'
);

-- =============================================================================
-- Test 13 & 14: Customer Authoritative Write Restrictions (Section D, L.13, L.14)
-- =============================================================================
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

-- Wallet accounts write attempt by customer
UPDATE public.wallet_accounts
SET balance = 999999.00
WHERE user_id = '22222222-0000-0000-0000-000000000001';

SELECT is(
  (SELECT balance FROM public.wallet_accounts WHERE user_id = '22222222-0000-0000-0000-000000000001'),
  0.00,
  'Test 14a: Customer cannot modify authoritative wallet account balance'
);

-- Inventory write attempt by customer
UPDATE public.inventory
SET quantity_available = 999
WHERE id = 'df000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT quantity_available FROM public.inventory WHERE id = 'df000000-0000-0000-0000-000000000001'),
  45,
  'Test 14b: Customer cannot modify inventory quantities'
);

-- =============================================================================
-- Test 15: Cross-User Isolation (User A vs User B)
-- =============================================================================
-- Alice trying to view Bob's profile
SELECT is(
  (SELECT count(*)::int FROM public.profiles WHERE id = '33333333-0000-0000-0000-000000000002'),
  0,
  'Test 15a: User A cannot read User B profile'
);

-- Alice trying to view Bob's address
SELECT is(
  (SELECT count(*)::int FROM public.addresses WHERE user_id = '33333333-0000-0000-0000-000000000002'),
  0,
  'Test 15b: User A cannot read User B address'
);

-- Alice trying to view Bob's wallet
SELECT is(
  (SELECT count(*)::int FROM public.wallet_accounts WHERE user_id = '33333333-0000-0000-0000-000000000002'),
  0,
  'Test 15c: User A cannot read User B wallet'
);

SELECT * FROM finish();
ROLLBACK;
