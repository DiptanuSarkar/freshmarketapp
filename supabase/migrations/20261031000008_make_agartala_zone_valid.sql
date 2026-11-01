-- =============================================================================
-- Migration: 20261031000008_make_agartala_zone_valid.sql
-- Description: Ensures delivery_zones geometry is strictly valid by healing self-intersections
-- =============================================================================

UPDATE public.delivery_zones
SET boundary = extensions.ST_Multi(extensions.ST_CollectionExtract(extensions.ST_MakeValid(boundary), 3)),
    updated_at = now()
WHERE code = 'agartala_city'
  AND NOT extensions.ST_IsValid(boundary);
