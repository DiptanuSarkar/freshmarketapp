-- =============================================================================
-- FreshMarket: RLS Policies, Hardened Grants, and Security Controls (Session 2A)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Private Role Helper Schema Permissions (Section C)
-- -----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.has_role(public.app_role) FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_role(public.app_role) TO authenticated;

-- Admin access to user_roles table within private schema
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.user_roles TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. Explicit Least-Privilege Table Grants (Section D, J)
-- -----------------------------------------------------------------------------
-- Revoke all default broad privileges on public schema
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, anon, authenticated;

-- Public Storefront: SELECT only for anon and authenticated
GRANT SELECT ON public.categories TO anon, authenticated;
GRANT SELECT ON public.products TO anon, authenticated;
GRANT SELECT ON public.product_variants TO anon, authenticated;
GRANT SELECT ON public.product_images TO anon, authenticated;
GRANT SELECT ON public.inventory TO anon, authenticated;
GRANT SELECT ON public.service_areas TO anon, authenticated;
GRANT SELECT ON public.delivery_slots TO anon, authenticated;
GRANT SELECT ON public.coupons TO anon, authenticated;
GRANT SELECT ON public.coupon_categories TO anon, authenticated;
GRANT SELECT ON public.product_reviews TO anon, authenticated;
GRANT SELECT ON public.banners TO anon, authenticated;
GRANT SELECT ON public.home_sections TO anon, authenticated;
GRANT SELECT ON public.home_section_items TO anon, authenticated;
GRANT SELECT ON public.app_settings TO anon, authenticated;

-- Customer Operations: Selective Authenticated Grants
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (full_name, avatar_url, date_of_birth) ON public.profiles TO authenticated;

GRANT SELECT, INSERT, UPDATE ON public.customer_preferences TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.addresses TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.wishlist_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.carts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cart_items TO authenticated;

-- Authoritative customer data: SELECT ONLY (no direct INSERT/UPDATE/DELETE)
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.order_items TO authenticated;
GRANT SELECT ON public.order_status_history TO authenticated;
GRANT SELECT ON public.payments TO authenticated;
GRANT SELECT ON public.refunds TO authenticated;
GRANT SELECT ON public.wallet_accounts TO authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
GRANT SELECT ON public.notifications TO authenticated;
GRANT SELECT ON public.coupon_users TO authenticated;
GRANT SELECT ON public.coupon_redemptions TO authenticated;

-- FCM Tokens: Customer-owned CRUD
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fcm_tokens TO authenticated;

-- Product Reviews: Controlled Customer Grants (Section F)
GRANT INSERT (user_id, product_id, rating, review_text) ON public.product_reviews TO authenticated;
GRANT UPDATE (rating, review_text) ON public.product_reviews TO authenticated;

-- Delivery Workflow Grants (Section G)
GRANT SELECT ON public.delivery_assignments TO authenticated;
GRANT SELECT, INSERT ON public.delivery_locations TO authenticated;

-- Service Role Full Permissions for backend and authoritative operations
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO service_role;
GRANT ALL ON SCHEMA public TO service_role;
GRANT ALL ON SCHEMA private TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA private TO service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA private TO service_role;

-- Sequence Usage: Remove customer sequence access (Section J)
-- Only service_role has sequence access; authenticated is explicitly denied
REVOKE ALL ON SEQUENCE public.order_number_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.order_number_seq TO service_role;

-- -----------------------------------------------------------------------------
-- 3. Harden Function Privileges (Section K)
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_profile_fields() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sanitize_product_review() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_fcm_token_registration() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.mark_notification_as_read(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_notification_as_read(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.mark_all_notifications_as_read() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_as_read() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.update_delivery_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_delivery_status(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. Enable Row Level Security (RLS) on All Tables
-- -----------------------------------------------------------------------------
ALTER TABLE private.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.home_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.home_section_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 5. Row Level Security Policies
-- -----------------------------------------------------------------------------

-- private.user_roles
CREATE POLICY user_roles_admin_all ON private.user_roles
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

CREATE POLICY user_roles_read_own ON private.user_roles
FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- profiles
CREATE POLICY profiles_select_own ON public.profiles
FOR SELECT TO authenticated
USING (id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY profiles_update_own ON public.profiles
FOR UPDATE TO authenticated
USING (id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (id = auth.uid() OR private.has_role('admin'::public.app_role));

-- customer_preferences
CREATE POLICY preferences_select_own ON public.customer_preferences
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY preferences_update_own ON public.customer_preferences
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY preferences_insert_own ON public.customer_preferences
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

-- addresses
CREATE POLICY addresses_user_isolation ON public.addresses
FOR ALL TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

-- categories
CREATE POLICY categories_select_public ON public.categories
FOR SELECT TO anon, authenticated
USING (is_active = true OR private.has_role('admin'::public.app_role));

CREATE POLICY categories_admin_all ON public.categories
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- products
CREATE POLICY products_select_public ON public.products
FOR SELECT TO anon, authenticated
USING (is_active = true OR private.has_role('admin'::public.app_role));

CREATE POLICY products_admin_all ON public.products
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- product_variants
CREATE POLICY variants_select_public ON public.product_variants
FOR SELECT TO anon, authenticated
USING (
  (
    is_active = true
    AND EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_variants.product_id AND p.is_active = true)
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY variants_admin_all ON public.product_variants
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- product_images (Section I)
CREATE POLICY product_images_select_public ON public.product_images
FOR SELECT TO anon, authenticated
USING (
  EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_images.product_id AND p.is_active = true)
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY product_images_admin_all ON public.product_images
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- inventory (Read-only public; Admin modify)
CREATE POLICY inventory_select_public ON public.inventory
FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY inventory_admin_all ON public.inventory
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- stock_movements (Admin only)
CREATE POLICY stock_movements_admin_all ON public.stock_movements
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- service_areas
CREATE POLICY service_areas_select_public ON public.service_areas
FOR SELECT TO anon, authenticated
USING (is_active = true OR private.has_role('admin'::public.app_role));

CREATE POLICY service_areas_admin_all ON public.service_areas
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- delivery_slots
CREATE POLICY delivery_slots_select_public ON public.delivery_slots
FOR SELECT TO anon, authenticated
USING (is_active = true OR private.has_role('admin'::public.app_role));

CREATE POLICY delivery_slots_admin_all ON public.delivery_slots
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- coupons (Section I)
CREATE POLICY coupons_select ON public.coupons
FOR SELECT TO anon, authenticated
USING (
  (
    is_active = true
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at IS NULL OR ends_at >= now())
    AND (
      is_public = true
      OR (
        auth.uid() IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.coupon_users cu
          WHERE cu.coupon_id = coupons.id
            AND cu.user_id = auth.uid()
        )
      )
    )
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY coupons_admin_all ON public.coupons
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- coupon_categories (Section I: prevent leaking private/targeted coupon configurations)
CREATE POLICY coupon_categories_select ON public.coupon_categories
FOR SELECT TO anon, authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.coupons c
    WHERE c.id = coupon_categories.coupon_id
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY coupon_categories_admin_all ON public.coupon_categories
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- coupon_users
CREATE POLICY coupon_users_select_own ON public.coupon_users
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY coupon_users_admin_all ON public.coupon_users
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- coupon_redemptions (Section D)
CREATE POLICY coupon_redemptions_select_own ON public.coupon_redemptions
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY coupon_redemptions_admin_all ON public.coupon_redemptions
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- banners (Section I)
CREATE POLICY banners_select_public ON public.banners
FOR SELECT TO anon, authenticated
USING (
  (
    is_active = true
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at IS NULL OR ends_at >= now())
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY banners_admin_all ON public.banners
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- home_sections (Section I)
CREATE POLICY home_sections_select_public ON public.home_sections
FOR SELECT TO anon, authenticated
USING (is_visible = true OR private.has_role('admin'::public.app_role));

CREATE POLICY home_sections_admin_all ON public.home_sections
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- home_section_items (Section I)
CREATE POLICY home_section_items_select_public ON public.home_section_items
FOR SELECT TO anon, authenticated
USING (
  (
    EXISTS (
      SELECT 1 FROM public.home_sections hs
      WHERE hs.id = home_section_items.home_section_id
        AND hs.is_visible = true
    )
    AND (
      home_section_items.product_id IS NULL OR EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = home_section_items.product_id AND p.is_active = true
      )
    )
    AND (
      home_section_items.category_id IS NULL OR EXISTS (
        SELECT 1 FROM public.categories c
        WHERE c.id = home_section_items.category_id AND c.is_active = true
      )
    )
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY home_section_items_admin_all ON public.home_section_items
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- wishlist_items
CREATE POLICY wishlist_isolation ON public.wishlist_items
FOR ALL TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

-- carts
CREATE POLICY carts_isolation ON public.carts
FOR ALL TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

-- cart_items
CREATE POLICY cart_items_isolation ON public.cart_items
FOR ALL TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.carts c WHERE c.id = cart_items.cart_id AND c.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM public.carts c WHERE c.id = cart_items.cart_id AND c.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
);

-- orders (Read-only for customers; Admin/service_role manages mutation)
CREATE POLICY orders_select_own ON public.orders
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY orders_admin_all ON public.orders
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- order_items
CREATE POLICY order_items_select_own ON public.order_items
FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_items.order_id AND o.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY order_items_admin_all ON public.order_items
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- order_status_history
CREATE POLICY order_status_history_select_own ON public.order_status_history
FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_status_history.order_id AND o.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY order_status_history_admin_all ON public.order_status_history
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- payments
CREATE POLICY payments_select_own ON public.payments
FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = payments.order_id AND o.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY payments_admin_all ON public.payments
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- refunds
CREATE POLICY refunds_select_own ON public.refunds
FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.orders o WHERE o.id = refunds.order_id AND o.user_id = auth.uid())
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY refunds_admin_all ON public.refunds
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- wallet_accounts
CREATE POLICY wallet_accounts_select_own ON public.wallet_accounts
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY wallet_accounts_admin_all ON public.wallet_accounts
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- wallet_transactions
CREATE POLICY wallet_transactions_select_own ON public.wallet_transactions
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY wallet_transactions_admin_all ON public.wallet_transactions
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- notifications
CREATE POLICY notifications_select_own ON public.notifications
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY notifications_admin_all ON public.notifications
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- fcm_tokens (Section H)
CREATE POLICY fcm_tokens_user_isolation ON public.fcm_tokens
FOR ALL TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

-- product_reviews (Section F)
CREATE POLICY product_reviews_select_public ON public.product_reviews
FOR SELECT TO anon, authenticated
USING (
  is_approved = true
  OR user_id = auth.uid()
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY product_reviews_insert_own ON public.product_reviews
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY product_reviews_update_own ON public.product_reviews
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR private.has_role('admin'::public.app_role))
WITH CHECK (user_id = auth.uid() OR private.has_role('admin'::public.app_role));

CREATE POLICY product_reviews_admin_all ON public.product_reviews
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- delivery_assignments (Section G: Read-only for agent, updates via RPC)
CREATE POLICY delivery_assignments_select ON public.delivery_assignments
FOR SELECT TO authenticated
USING (
  delivery_agent_id = auth.uid()
  OR private.has_role('admin'::public.app_role)
  OR private.has_role('delivery_agent'::public.app_role)
);

CREATE POLICY delivery_assignments_admin_all ON public.delivery_assignments
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- delivery_locations (Section G: Enforces assignment ownership and status)
CREATE POLICY delivery_locations_select ON public.delivery_locations
FOR SELECT TO authenticated
USING (
  delivery_agent_id = auth.uid()
  OR private.has_role('admin'::public.app_role)
  OR EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = delivery_locations.order_id
      AND o.user_id = auth.uid()
  )
);

CREATE POLICY delivery_locations_insert ON public.delivery_locations
FOR INSERT TO authenticated
WITH CHECK (
  (
    delivery_agent_id = auth.uid()
    AND (
      delivery_locations.order_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.delivery_assignments da
        WHERE da.order_id = delivery_locations.order_id
          AND da.delivery_agent_id = auth.uid()
          AND da.status IN ('accepted', 'out_for_delivery')
      )
    )
  )
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY delivery_locations_admin_all ON public.delivery_locations
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- app_settings
CREATE POLICY app_settings_select_public ON public.app_settings
FOR SELECT TO anon, authenticated
USING (is_public = true OR private.has_role('admin'::public.app_role));

CREATE POLICY app_settings_admin_all ON public.app_settings
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));
