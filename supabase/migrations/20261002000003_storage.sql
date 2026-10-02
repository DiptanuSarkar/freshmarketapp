-- =============================================================================
-- FreshMarket: Storage Buckets & Policies (Session 2A)
-- =============================================================================

-- 1. Create Storage Buckets
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('product-images', 'product-images', true),
  ('category-images', 'category-images', true),
  ('banner-images', 'banner-images', true),
  ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- 2. Storage Policies

-- Public Read on public media buckets
CREATE POLICY "Public read product images" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'product-images');

CREATE POLICY "Public read category images" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'category-images');

CREATE POLICY "Public read banner images" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'banner-images');

CREATE POLICY "Public read avatars" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'avatars');

-- Admin full access to store assets
CREATE POLICY "Admin full manage storage" ON storage.objects
FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

-- Users can upload/update their own avatar in avatars bucket (avatars/{user_id}/*)
CREATE POLICY "Users manage own avatar" ON storage.objects
FOR ALL TO authenticated
USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
