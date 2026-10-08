BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(37);

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
-- Alice tries to modify protected profile columns directly (denied by column grant)
SELECT throws_ok(
  $$ UPDATE public.profiles SET email = 'hacked@freshmarket.com' WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 4a: Customer cannot alter protected profile email (42501)'
);

SELECT throws_ok(
  $$ UPDATE public.profiles SET is_active = false WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 4b: Customer cannot alter protected profile is_active (42501)'
);

SELECT throws_ok(
  $$ UPDATE public.profiles SET id = '00000000-0000-0000-0000-000000000000'::uuid WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 4c: Customer cannot alter protected profile id (42501)'
);

-- Safe fields can be updated
SELECT lives_ok(
  $$ UPDATE public.profiles SET full_name = 'Alice Updated Name' WHERE id = '22222222-0000-0000-0000-000000000001' $$,
  'Test 4d: Customer can update safe profile field full_name'
);

-- =============================================================================
-- Test 5: Product Review Security (Section F, L.5)
-- =============================================================================
-- 5a: Customer cannot supply is_verified_purchase in INSERT (column privilege denied)
SELECT throws_ok(
  $$ INSERT INTO public.product_reviews (product_id, user_id, rating, review_text, is_verified_purchase)
     VALUES ('a1000000-0000-0000-0000-000000000002', '22222222-0000-0000-0000-000000000001', 5, 'Fake review', true) $$,
  '42501',
  NULL,
  'Test 5a: Customer cannot supply is_verified_purchase on INSERT (42501)'
);

-- 5b & 5c: Alice submits a normal review; trigger & defaults enforce safety
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
  'Test 5b: Customer review insertion forces is_verified_purchase = false'
);

SELECT is(
  (SELECT is_approved FROM public.product_reviews WHERE product_id = 'a1000000-0000-0000-0000-000000000002' AND user_id = '22222222-0000-0000-0000-000000000001'),
  false,
  'Test 5c: Customer review insertion forces is_approved = false'
);

-- 5d: Customer updating review keeps is_approved = false
UPDATE public.product_reviews
SET review_text = 'Updated review text'
WHERE product_id = 'a1000000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT is_approved FROM public.product_reviews WHERE product_id = 'a1000000-0000-0000-0000-000000000002' AND user_id = '22222222-0000-0000-0000-000000000001'),
  false,
  'Test 5d: Customer review update resets/maintains is_approved = false'
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

-- Dave tries to directly UPDATE delivery_assignments table (prohibited: table is read-only)
SELECT throws_ok(
  $$ UPDATE public.delivery_assignments SET order_id = '00000001-0000-0000-0000-000000000002' WHERE id = 'da000000-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 6a: Delivery agent direct UPDATE throws 42501 (cannot retarget order_id)'
);

SELECT is(
  (SELECT order_id FROM public.delivery_assignments WHERE id = 'da000000-0000-0000-0000-000000000001'),
  '00000001-0000-0000-0000-000000000001'::uuid,
  'Test 6b: Delivery assignment order_id is unmodified'
);

SELECT throws_ok(
  $$ UPDATE public.delivery_assignments SET delivery_agent_id = '33333333-0000-0000-0000-000000000002' WHERE id = 'da000000-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 7a: Delivery agent direct UPDATE throws 42501 (cannot change delivery_agent_id)'
);

SELECT is(
  (SELECT delivery_agent_id FROM public.delivery_assignments WHERE id = 'da000000-0000-0000-0000-000000000001'),
  '44444444-0000-0000-0000-000000000001'::uuid,
  'Test 7b: Delivery assignment delivery_agent_id is unmodified'
);

-- Dave tries to insert telemetry for an unassigned order
SELECT throws_ok(
  $$ INSERT INTO public.delivery_locations (order_id, delivery_agent_id, latitude, longitude)
     VALUES ('00000001-0000-0000-0000-000000000099', '44444444-0000-0000-0000-000000000001', 12.9716, 77.5946) $$,
  '42501',
  NULL,
  'Test 8: Delivery agent cannot insert telemetry for unassigned order (42501)'
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

SELECT is(
  (SELECT count(*)::int FROM public.coupon_categories WHERE coupon_id = 'f1000000-0000-0000-0000-000000000003'),
  0,
  'Test 11c: Targeted coupon category link is hidden from non-assigned user Bob'
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
  'Test 12a: Notification RPC mark_notification_as_read is not executable by anon (42501)'
);

SELECT throws_ok(
  $$ SELECT public.mark_all_notifications_as_read() $$,
  '42501',
  NULL,
  'Test 12b: Notification RPC mark_all_notifications_as_read is not executable by anon (42501)'
);

-- =============================================================================
-- Test 13: Customer Sequence Access Denied (Section J)
-- =============================================================================
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "22222222-0000-0000-0000-000000000001", "role": "authenticated"}';

SELECT throws_ok(
  $$ SELECT nextval('public.order_number_seq'::regclass) $$,
  '42501',
  NULL,
  'Test 13: Customer cannot directly access order_number_seq sequence (42501)'
);

-- =============================================================================
-- Test 14: Customer Authoritative Write Restrictions (Section D, L.13, L.14)
-- =============================================================================
-- Wallet accounts write attempt by customer
SELECT throws_ok(
  $$ UPDATE public.wallet_accounts SET balance = 999999.00 WHERE user_id = '22222222-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 14a: Customer cannot modify authoritative wallet account balance (42501)'
);

-- Inventory write attempt by customer
SELECT throws_ok(
  $$ UPDATE public.inventory SET quantity_available = 999 WHERE id = 'df000000-0000-0000-0000-000000000001' $$,
  '42501',
  NULL,
  'Test 14b: Customer cannot modify inventory quantities (42501)'
);

-- Orders direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.orders (id, user_id, delivery_address_snapshot, delivery_date, subtotal, total, payment_method)
     VALUES ('00000002-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '{}', current_date, 100, 100, 'cod') $$,
  '42501',
  NULL,
  'Test 14c: Customer cannot directly insert orders (42501)'
);

-- Order items direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.order_items (order_id, variant_id, product_name, variant_name, weight, price, quantity, total_price)
     VALUES ('00000001-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Chicken', '500g', '500g', 100, 1, 100) $$,
  '42501',
  NULL,
  'Test 14d: Customer cannot directly insert order items (42501)'
);

-- Payments direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.payments (order_id, payment_method, amount, status)
     VALUES ('00000001-0000-0000-0000-000000000001', 'cod', 100, 'completed') $$,
  '42501',
  NULL,
  'Test 14e: Customer cannot directly insert payments (42501)'
);

-- Refunds direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.refunds (order_id, amount, reason, refund_method)
     VALUES ('00000001-0000-0000-0000-000000000001', 100, 'Bad quality', 'wallet') $$,
  '42501',
  NULL,
  'Test 14f: Customer cannot directly insert refunds (42501)'
);

-- Stock movements direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.stock_movements (variant_id, quantity_changed, movement_type)
     VALUES ('b1000000-0000-0000-0000-000000000001', 10, 'adjustment') $$,
  '42501',
  NULL,
  'Test 14g: Customer cannot write stock movements (42501)'
);

-- Coupon redemptions direct insert by customer
SELECT throws_ok(
  $$ INSERT INTO public.coupon_redemptions (coupon_id, user_id, order_id, discount_applied)
     VALUES ('f1000000-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '00000001-0000-0000-0000-000000000001', 50) $$,
  '42501',
  NULL,
  'Test 14h: Customer cannot write coupon redemptions (42501)'
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

-- Alice trying to view Bob's cart
SELECT is(
  (SELECT count(*)::int FROM public.carts WHERE user_id = '33333333-0000-0000-0000-000000000002'),
  0,
  'Test 15d: User A cannot read User B cart'
);

-- Alice trying to view Bob's order
SELECT is(
  (SELECT count(*)::int FROM public.orders WHERE user_id = '33333333-0000-0000-0000-000000000002'),
  0,
  'Test 15e: User A cannot read User B order'
);

SELECT * FROM finish();
ROLLBACK;
