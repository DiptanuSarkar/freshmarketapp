-- =============================================================================
-- FreshMarket: Deterministic Seed Data (Session 2A)
-- All UUIDs are strictly valid hexadecimal characters [0-9a-f]
-- =============================================================================

-- 1. Seed Authentication Users (Simulating Supabase Auth)
-- Password for all test users: 'password123'
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  phone,
  encrypted_password,
  email_confirmed_at,
  phone_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) VALUES
  (
    '11111111-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'admin@freshmarket.com',
    '+919876543200',
    crypt('password123', gen_salt('bf')),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Store Administrator"}',
    now(),
    now()
  ),
  (
    '22222222-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'alice@freshmarket.com',
    '+919876543210',
    crypt('password123', gen_salt('bf')),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Alice Customer"}',
    now(),
    now()
  ),
  (
    '33333333-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'bob@freshmarket.com',
    '+919876543211',
    crypt('password123', gen_salt('bf')),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Bob Customer"}',
    now(),
    now()
  ),
  (
    '44444444-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'delivery@freshmarket.com',
    '+919876543212',
    crypt('password123', gen_salt('bf')),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dave Delivery Agent"}',
    now(),
    now()
  )
ON CONFLICT (id) DO NOTHING;

-- 2. Configure Non-exposed User Roles in private schema
-- Note: Trigger handle_new_user automatically inserts 'customer' role.
-- We upgrade admin and delivery agent roles here.
INSERT INTO private.user_roles (user_id, role)
VALUES
  ('11111111-0000-0000-0000-000000000001', 'admin'::public.app_role),
  ('44444444-0000-0000-0000-000000000001', 'delivery_agent'::public.app_role)
ON CONFLICT (user_id, role) DO NOTHING;

-- 3. Seed Service Areas
INSERT INTO public.service_areas (id, name, pincode, city, is_active, delivery_charge, min_order_for_free_delivery)
VALUES
  ('d1000000-0000-0000-0000-000000000001', 'Indiranagar', '560038', 'Bengaluru', true, 30.00, 499.00),
  ('d1000000-0000-0000-0000-000000000002', 'Koramangala', '560034', 'Bengaluru', true, 30.00, 499.00),
  ('d1000000-0000-0000-0000-000000000003', 'HSR Layout', '560102', 'Bengaluru', true, 25.00, 499.00)
ON CONFLICT (id) DO NOTHING;

-- 4. Seed Delivery Slots
INSERT INTO public.delivery_slots (id, name, start_time, end_time, max_orders, is_active)
VALUES
  ('e1000000-0000-0000-0000-000000000001', 'Morning Fresh (6 AM - 8 AM)', '06:00:00', '08:00:00', 50, true),
  ('e1000000-0000-0000-0000-000000000002', 'Mid-Day Lunch (11 AM - 1 PM)', '11:00:00', '13:00:00', 50, true),
  ('e1000000-0000-0000-0000-000000000003', 'Evening BBQ (5 PM - 7 PM)', '17:00:00', '19:00:00', 50, true)
ON CONFLICT (id) DO NOTHING;

-- 5. Seed Categories
INSERT INTO public.categories (id, slug, name, image_url, badge, description, display_order, is_active)
VALUES
  (
    'c1000000-0000-0000-0000-000000000001',
    'chicken',
    'Chicken',
    'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80',
    'Farm Fresh',
    'Antibiotic residue-free, tender farm-raised chicken cut fresh daily.',
    1,
    true
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'mutton',
    'Mutton',
    'https://images.unsplash.com/photo-1603048588665-791ca8aea617?auto=format&fit=crop&w=400&q=80',
    'Grass Fed',
    'Prime pasture-raised rich goat and lamb cuts, trimmed to perfection.',
    2,
    true
  ),
  (
    'c1000000-0000-0000-0000-000000000003',
    'fish',
    'Fish & Seafood',
    'https://images.unsplash.com/photo-1534939561126-855b8675edd7?auto=format&fit=crop&w=400&q=80',
    'Daily Catch',
    'Fresh coastal catch from day-boats, cleaned and descaled with care.',
    3,
    true
  ),
  (
    'c1000000-0000-0000-0000-000000000004',
    'pork',
    'Pork',
    'https://images.unsplash.com/photo-1602498456745-e9503b30470b?auto=format&fit=crop&w=400&q=80',
    'Premium',
    'Hygienically sourced tender pork chops, belly cuts, and ribs.',
    4,
    true
  ),
  (
    'c1000000-0000-0000-0000-000000000005',
    'grocery',
    'Grocery & Spices',
    'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=400&q=80',
    'Kitchen Staples',
    'Pure cooking oils, artisanal ground spices, eggs, and marinades.',
    5,
    true
  )
ON CONFLICT (id) DO NOTHING;

-- 6. Seed Products
INSERT INTO public.products (
  id,
  category_id,
  name,
  slug,
  short_description,
  description,
  storage_instructions,
  cooking_suggestions,
  is_halal,
  is_active
) VALUES
  (
    'a1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000001',
    'Fresh Farm Chicken Curry Cut (Skinless)',
    'chicken-curry-cut-skinless',
    'Tender bone-in chicken cut into even pieces, ideal for home-style curries.',
    'Carefully trimmed fresh chicken with perfect balance of bone and meat. Raised without hormones or prophylactic antibiotics on certified biosecure poultry farms.',
    'Keep chilled between 0-4°C. Consume within 48 hours of delivery.',
    'Ideal for homestyle Indian curry, biryani, or slow simmered gravies.',
    true,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000001',
    'Premium Chicken Breast Boneless',
    'premium-chicken-breast-boneless',
    'Pure lean fillet strips, high protein and trimmed clean of excess fat.',
    'Prime tender chicken fillets cut uniformly. Excellent choice for health-conscious meals and quick cooking recipes.',
    'Store in freezer (-18°C) or refrigerator (0-4°C).',
    'Great for grilling, baking, stir-frying, or pan-searing with herbs.',
    true,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000002',
    'Rich Goat Curry Cut',
    'rich-goat-curry-cut',
    'Succulent bone-in chunks of grass-fed goat meat for flavorful gravies.',
    'Pasture-fed young goat meat offering rich taste and succulent mouthfeel. Trimmed by expert butchers.',
    'Keep refrigerated at 0-4°C.',
    'Best pressure-cooked or simmered slowly with whole spices.',
    true,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000003',
    'Fresh Seer Fish Steaks (Surmai)',
    'fresh-seer-fish-steaks',
    'Firm, delicately flavored ocean fish steaks with center round bone.',
    'Fresh morning catch cleaned, descaled, and sliced into neat steaks.',
    'Store on ice or at 0-2°C. Cook on the same day for best texture.',
    'Perfect for tawa fry, coastal fish curry, or rava crusted shallow fry.',
    true,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000005',
    'Farm Fresh Eggs (Pack of 12)',
    'farm-fresh-eggs-12',
    'Nutrient-dense natural brown farm eggs with vibrant golden yolk.',
    'Gathered fresh daily from healthy free-foraging hens.',
    'Store in a cool dry pantry or refrigerator.',
    'Boil, scramble, pouch, or bake to perfection.',
    true,
    true
  )
ON CONFLICT (id) DO NOTHING;

-- 7. Seed Product Variants
INSERT INTO public.product_variants (
  id,
  product_id,
  name,
  sku,
  weight,
  price,
  discounted_price,
  gross_weight,
  net_weight,
  pieces_count,
  serves,
  is_default,
  is_active
) VALUES
  (
    'b1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    '500g Pack',
    'CHK-CURRY-500',
    '500g',
    180.00,
    155.00,
    '520g',
    '500g',
    '12-14 pcs',
    '2-3 people',
    true,
    true
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    '1kg Value Pack',
    'CHK-CURRY-1000',
    '1000g',
    350.00,
    299.00,
    '1040g',
    '1000g',
    '24-28 pcs',
    '4-6 people',
    false,
    true
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    '500g Fillet',
    'CHK-BREAST-500',
    '500g',
    240.00,
    210.00,
    '510g',
    '500g',
    '2-3 fillets',
    '2 people',
    true,
    true
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000003',
    '500g Curry Cut',
    'MUT-CURRY-500',
    '500g',
    490.00,
    460.00,
    '520g',
    '500g',
    '10-12 pcs',
    '2-3 people',
    true,
    true
  ),
  (
    'b1000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000004',
    '500g Steaks',
    'FSH-SEER-500',
    '500g',
    550.00,
    499.00,
    '520g',
    '500g',
    '4-6 steaks',
    '2-3 people',
    true,
    true
  ),
  (
    'b1000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000005',
    'Pack of 12',
    'EGG-BROWN-12',
    '12 pcs',
    120.00,
    105.00,
    '750g',
    '700g',
    '12 eggs',
    'Family',
    true,
    true
  )
ON CONFLICT (id) DO NOTHING;

-- 8. Seed Product Images
INSERT INTO public.product_images (id, product_id, image_url, display_order, is_primary)
VALUES
  ('ba000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=600&q=80', 1, true),
  ('ba000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'https://images.unsplash.com/photo-1604503468506-a8da13d82791?auto=format&fit=crop&w=600&q=80', 1, true),
  ('ba000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000003', 'https://images.unsplash.com/photo-1603048588665-791ca8aea617?auto=format&fit=crop&w=600&q=80', 1, true),
  ('ba000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000004', 'https://images.unsplash.com/photo-1534939561126-855b8675edd7?auto=format&fit=crop&w=600&q=80', 1, true),
  ('ba000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000005', 'https://images.unsplash.com/photo-1516467508483-a7212febe31a?auto=format&fit=crop&w=600&q=80', 1, true)
ON CONFLICT (id) DO NOTHING;

-- 9. Seed Inventory
INSERT INTO public.inventory (id, variant_id, quantity_available, reserved_quantity, low_stock_threshold)
VALUES
  ('df000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 45, 2, 5),
  ('df000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000002', 20, 0, 5),
  ('df000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000003', 30, 1, 5),
  ('df000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000004', 15, 0, 4),
  ('df000000-0000-0000-0000-000000000005', 'b1000000-0000-0000-0000-000000000005', 25, 0, 5),
  ('df000000-0000-0000-0000-000000000006', 'b1000000-0000-0000-0000-000000000006', 60, 5, 10)
ON CONFLICT (id) DO NOTHING;

-- 10. Seed Coupons (Section I: Public and User-Specific)
INSERT INTO public.coupons (
  id,
  code,
  title,
  description,
  discount_type,
  discount_value,
  min_order_value,
  max_discount,
  starts_at,
  ends_at,
  is_public,
  is_active
) VALUES
  (
    'f1000000-0000-0000-0000-000000000001',
    'FRESH20',
    '20% Off Farm Fresh Cuts',
    'Flat 20% discount on all chicken and mutton cuts above ₹499.',
    'percentage',
    20.00,
    499.00,
    150.00,
    now() - interval '1 day',
    now() + interval '30 days',
    true,
    true
  ),
  (
    'f1000000-0000-0000-0000-000000000002',
    'MEAT50',
    '₹50 Off Welcome Treat',
    'Flat ₹50 savings on any first order above ₹299.',
    'flat',
    50.00,
    299.00,
    50.00,
    now() - interval '1 day',
    now() + interval '60 days',
    true,
    true
  ),
  (
    'f1000000-0000-0000-0000-000000000003',
    'VIPALICE',
    'Exclusive VIP Discount for Alice',
    'Special ₹100 reward coupon exclusively for Alice.',
    'flat',
    100.00,
    500.00,
    100.00,
    now() - interval '1 day',
    now() + interval '30 days',
    false,
    true
  )
ON CONFLICT (id) DO NOTHING;

-- Attach user coupon for Alice
INSERT INTO public.coupon_users (coupon_id, user_id)
VALUES ('f1000000-0000-0000-0000-000000000003', '22222222-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;

-- 11. Seed Banners (Section I: Active, Scheduled, Expired)
INSERT INTO public.banners (
  id,
  title,
  subtitle,
  image_url,
  badge_text,
  target_category_slug,
  display_order,
  starts_at,
  ends_at,
  is_active
) VALUES
  (
    'bb000000-0000-0000-0000-000000000001',
    'Weekend Barbeque Special',
    'Flat 20% OFF on Prime Mutton & Chicken Cuts',
    'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=800&q=80',
    'LIMITED OFFER',
    'chicken',
    1,
    now() - interval '2 days',
    now() + interval '5 days',
    true
  ),
  (
    'bb000000-0000-0000-0000-000000000002',
    'Fresh Catch of the Morning',
    'Direct from harbor to your kitchen within 120 mins',
    'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?auto=format&fit=crop&w=800&q=80',
    'FRESH ARRIVAL',
    'fish',
    2,
    now() - interval '1 day',
    now() + interval '10 days',
    true
  ),
  (
    'bb000000-0000-0000-0000-000000000003',
    'Expired Festive Promo',
    'This promotion has already passed',
    'https://images.unsplash.com/photo-1506368249639-73a05d6f6488?auto=format&fit=crop&w=800&q=80',
    'EXPIRED',
    'grocery',
    3,
    now() - interval '20 days',
    now() - interval '2 days',
    true
  )
ON CONFLICT (id) DO NOTHING;

-- 12. Seed Home Sections & Items (Section I)
INSERT INTO public.home_sections (id, title, subtitle, section_type, display_order, is_visible)
VALUES
  (
    '00a00000-0000-0000-0000-000000000001',
    'Featured Banner Carousel',
    'Top seasonal highlights',
    'banner_carousel',
    1,
    true
  ),
  (
    '00a00000-0000-0000-0000-000000000002',
    'Daily Farm Best-Sellers',
    'Customer favorites cut fresh today',
    'horizontal_products',
    2,
    true
  ),
  (
    '00a00000-0000-0000-0000-000000000003',
    'Hidden Admin Test Section',
    'Should not be visible to public or regular customers',
    'horizontal_products',
    3,
    false
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.home_section_items (id, home_section_id, product_id, category_id, display_order)
VALUES
  (
    '00b00000-0000-0000-0000-000000000001',
    '00a00000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    NULL,
    1
  ),
  (
    '00b00000-0000-0000-0000-000000000002',
    '00a00000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000002',
    NULL,
    2
  ),
  (
    '00b00000-0000-0000-0000-000000000003',
    '00a00000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000003',
    NULL,
    1
  )
ON CONFLICT (id) DO NOTHING;

-- 13. Seed App Settings
INSERT INTO public.app_settings (key, value, description, is_public)
VALUES
  (
    'store_info',
    '{"name":"FreshMarket","tagline":"Farm-Fresh Meat & Groceries","phone":"+91 80 4567 8900","email":"support@freshmarket.com"}',
    'Public storefront information',
    true
  ),
  (
    'delivery_policy',
    '{"free_delivery_threshold":499.00,"standard_fee":30.00,"express_fee":50.00}',
    'Delivery fee policies',
    true
  ),
  (
    'payment_gateway_config',
    '{"provider":"razorpay","mode":"test"}',
    'Payment gateway client configuration',
    true
  )
ON CONFLICT (key) DO NOTHING;

-- 14. Seed Customer Address for Alice
INSERT INTO public.addresses (
  id,
  user_id,
  label,
  recipient_name,
  phone,
  address_line1,
  city,
  state,
  pincode,
  is_default
) VALUES (
  'ad000000-0000-0000-0000-000000000001',
  '22222222-0000-0000-0000-000000000001',
  'Home',
  'Alice Customer',
  '+919876543210',
  '123 4th Cross, 100 Feet Rd, Indiranagar',
  'Bengaluru',
  'Karnataka',
  '560038',
  true
) ON CONFLICT (id) DO NOTHING;

-- 15. Seed Approved Product Review
INSERT INTO public.product_reviews (
  id,
  product_id,
  user_id,
  rating,
  review_text,
  is_verified_purchase,
  is_approved
) VALUES (
  'de000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',
  '22222222-0000-0000-0000-000000000001',
  5,
  'Outstanding freshness! The curry cut was clean, tender, and cooked wonderfully.',
  true,
  true
) ON CONFLICT (id) DO NOTHING;
