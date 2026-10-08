-- =============================================================================
-- Migration: 20261005000001_session3_compatibility_and_security_patch.sql
-- Description: Session 3 Forward-only database compatibility and security fixes
--   1. Delivery assignment RLS tightening (Agent isolation + Admin full access)
--   2. Product variants SKU support with deterministic backfill & unique constraint
--   3. Order status enum compatibility extension (placed, preparing, packed)
--   4. Customer support contact_messages table with RLS
--   5. Address landmark, delivery_instructions, coordinate checks, & partial unique default index
--   6. Comprehensive query performance indexes
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ORDER STATUS ENUM EXTENSION (Section 2.3)
-- Safely add 'placed', 'preparing', 'packed' to order_status enum
-- -----------------------------------------------------------------------------
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'placed' BEFORE 'confirmed';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'preparing' AFTER 'confirmed';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'packed' AFTER 'preparing';

-- -----------------------------------------------------------------------------
-- 2. PRODUCT VARIANTS SKU (Section 2.2)
-- -----------------------------------------------------------------------------
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS sku text;

-- Deterministic backfill for existing seed variants
UPDATE public.product_variants
SET sku = CASE
  WHEN id = 'b1000000-0000-0000-0000-000000000001' THEN 'CHK-CURRY-500'
  WHEN id = 'b1000000-0000-0000-0000-000000000002' THEN 'CHK-CURRY-1000'
  WHEN id = 'b1000000-0000-0000-0000-000000000003' THEN 'CHK-BREAST-500'
  WHEN id = 'b1000000-0000-0000-0000-000000000004' THEN 'MUT-CURRY-500'
  WHEN id = 'b1000000-0000-0000-0000-000000000005' THEN 'FISH-SEER-500'
  WHEN id = 'b1000000-0000-0000-0000-000000000006' THEN 'EGG-12'
  ELSE 'SKU-' || UPPER(SUBSTRING(REPLACE(id::text, '-', ''), 1, 8))
END
WHERE sku IS NULL;

-- Enforce NOT NULL on sku
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;

-- Enforce unique constraint on sku
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'product_variants_sku_key'
  ) THEN
    ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_sku_key UNIQUE (sku);
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3. ADDRESS COMPATIBILITY & CONSTRAINTS (Section 2.5)
-- -----------------------------------------------------------------------------
ALTER TABLE public.addresses ADD COLUMN IF NOT EXISTS landmark text;
ALTER TABLE public.addresses ADD COLUMN IF NOT EXISTS delivery_instructions text;

-- Coordinate check constraints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_addresses_latitude'
  ) THEN
    ALTER TABLE public.addresses ADD CONSTRAINT chk_addresses_latitude
      CHECK (latitude IS NULL OR (latitude >= -90.0 AND latitude <= 90.0));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_addresses_longitude'
  ) THEN
    ALTER TABLE public.addresses ADD CONSTRAINT chk_addresses_longitude
      CHECK (longitude IS NULL OR (longitude >= -180.0 AND longitude <= 180.0));
  END IF;
END $$;

-- Enforce exactly one default address per user using partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS idx_addresses_user_default
  ON public.addresses (user_id)
  WHERE is_default = true;

-- -----------------------------------------------------------------------------
-- 4. CUSTOMER SUPPORT STORAGE (Section 2.4)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contact_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  email text,
  phone text,
  subject text,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'new',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_contact_messages_updated_at ON public.contact_messages;
CREATE TRIGGER trg_contact_messages_updated_at
  BEFORE UPDATE ON public.contact_messages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Enable RLS
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;

-- Grants
GRANT SELECT, INSERT ON public.contact_messages TO authenticated;
GRANT ALL ON public.contact_messages TO service_role;

-- Policies for contact_messages
DROP POLICY IF EXISTS contact_messages_insert_own ON public.contact_messages;
CREATE POLICY contact_messages_insert_own ON public.contact_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND user_id = auth.uid()
    AND status = 'new'
  );

DROP POLICY IF EXISTS contact_messages_select_own ON public.contact_messages;
CREATE POLICY contact_messages_select_own ON public.contact_messages
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR private.has_role('admin'::public.app_role)
  );

DROP POLICY IF EXISTS contact_messages_admin_all ON public.contact_messages;
CREATE POLICY contact_messages_admin_all ON public.contact_messages
  FOR ALL TO authenticated
  USING (private.has_role('admin'::public.app_role))
  WITH CHECK (private.has_role('admin'::public.app_role));

-- -----------------------------------------------------------------------------
-- 5. FIX DELIVERY ASSIGNMENT RLS (Section 2.1)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS delivery_assignments_select ON public.delivery_assignments;

CREATE POLICY delivery_assignments_select ON public.delivery_assignments
  FOR SELECT TO authenticated
  USING (
    private.has_role('admin'::public.app_role)
    OR (
      delivery_agent_id = auth.uid()
      AND private.has_role('delivery_agent'::public.app_role)
    )
  );

-- -----------------------------------------------------------------------------
-- 6. APPLICATION PERFORMANCE INDEXES (Section 2.6)
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_products_category_active ON public.products (category_id, is_active);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_active ON public.product_variants (product_id, is_active);
CREATE INDEX IF NOT EXISTS idx_product_images_product_order ON public.product_images (product_id, display_order);
CREATE INDEX IF NOT EXISTS idx_inventory_variant ON public.inventory (variant_id);
CREATE INDEX IF NOT EXISTS idx_wishlist_items_user ON public.wishlist_items (user_id);
CREATE INDEX IF NOT EXISTS idx_carts_user ON public.carts (user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_cart ON public.cart_items (cart_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_variant ON public.cart_items (variant_id);
CREATE INDEX IF NOT EXISTS idx_addresses_user ON public.addresses (user_id);
CREATE INDEX IF NOT EXISTS idx_coupons_active_dates ON public.coupons (is_active, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_coupon_users_user_coupon ON public.coupon_users (user_id, coupon_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_created ON public.orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders (status);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_history_order_created ON public.order_status_history (order_id, created_at);
CREATE INDEX IF NOT EXISTS idx_payments_order ON public.payments (order_id);
CREATE INDEX IF NOT EXISTS idx_refunds_order ON public.refunds (order_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_created ON public.wallet_transactions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON public.fcm_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_approved ON public.product_reviews (product_id, is_approved);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_agent_status ON public.delivery_assignments (delivery_agent_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_locations_order_recorded ON public.delivery_locations (order_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_home_section_items_section_order ON public.home_section_items (home_section_id, display_order);
CREATE INDEX IF NOT EXISTS idx_banners_active_order ON public.banners (is_active, display_order);
