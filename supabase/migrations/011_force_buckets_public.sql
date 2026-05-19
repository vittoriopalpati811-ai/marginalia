-- Marginalia — Migration 011: Force all storage buckets to public
-- Run in Supabase SQL Editor. Idempotent.
--
-- Problem: Migrations 007/008 used "ON CONFLICT DO NOTHING", so buckets that were
-- already created as private (by the Flutter client's _ensureBucket on first launch)
-- were never updated to public. This caused all getPublicUrl() calls to return
-- URLs that give 403 Forbidden — images silently fall back to gradient/initials.
--
-- Fix: Force-update the public flag on all buckets, create missing ones.

-- ─── 1. Force all existing buckets to public ─────────────────────────────────

UPDATE storage.buckets
SET public = true
WHERE id IN ('avatars', 'covers', 'jam-covers', 'post-images', 'comment-images');

-- ─── 2. Create any missing buckets (with ON CONFLICT DO UPDATE this time) ──────

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('avatars',        'avatars',        true),
  ('covers',         'covers',         true),
  ('jam-covers',     'jam-covers',     true),
  ('post-images',    'post-images',    true),
  ('comment-images', 'comment-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ─── 3. Ensure RLS is enabled on storage.objects ─────────────────────────────
-- (Should already be enabled, but make sure)

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- ─── 4. Re-create all storage RLS policies ────────────────────────────────────
-- Drop and re-create to ensure they exist and are correct.

-- Avatars
DROP POLICY IF EXISTS "Avatar public read"    ON storage.objects;
DROP POLICY IF EXISTS "Avatar owner upload"   ON storage.objects;
DROP POLICY IF EXISTS "Avatar owner update"   ON storage.objects;
DROP POLICY IF EXISTS "Avatar owner delete"   ON storage.objects;

CREATE POLICY "Avatar public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Avatar owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Avatar owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Avatar owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

-- Covers
DROP POLICY IF EXISTS "Cover public read"    ON storage.objects;
DROP POLICY IF EXISTS "Cover owner upload"   ON storage.objects;
DROP POLICY IF EXISTS "Cover owner update"   ON storage.objects;
DROP POLICY IF EXISTS "Cover owner delete"   ON storage.objects;

CREATE POLICY "Cover public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');

CREATE POLICY "Cover owner upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'covers'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Cover owner update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'covers'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

CREATE POLICY "Cover owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'covers'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

-- Jam covers (any authenticated user may manage)
DROP POLICY IF EXISTS "Jam cover public read"   ON storage.objects;
DROP POLICY IF EXISTS "Jam cover auth upload"   ON storage.objects;
DROP POLICY IF EXISTS "Jam cover auth update"   ON storage.objects;
DROP POLICY IF EXISTS "Jam cover auth delete"   ON storage.objects;

CREATE POLICY "Jam cover public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'jam-covers');

CREATE POLICY "Jam cover auth upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'jam-covers'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Jam cover auth update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'jam-covers'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Jam cover auth delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'jam-covers'
    AND auth.role() = 'authenticated'
  );

-- Post images (any authenticated user may upload)
DROP POLICY IF EXISTS "Post image public read"   ON storage.objects;
DROP POLICY IF EXISTS "Post image auth upload"   ON storage.objects;
DROP POLICY IF EXISTS "Post image auth delete"   ON storage.objects;

CREATE POLICY "Post image public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'post-images');

CREATE POLICY "Post image auth upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'post-images'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Post image auth delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'post-images'
    AND auth.role() = 'authenticated'
  );

-- Comment images (any authenticated user may upload)
DROP POLICY IF EXISTS "Comment image public read"   ON storage.objects;
DROP POLICY IF EXISTS "Comment image auth upload"   ON storage.objects;
DROP POLICY IF EXISTS "Comment image auth delete"   ON storage.objects;

CREATE POLICY "Comment image public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'comment-images');

CREATE POLICY "Comment image auth upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'comment-images'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "Comment image auth delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'comment-images'
    AND auth.role() = 'authenticated'
  );
