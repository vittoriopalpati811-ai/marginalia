-- Marginalia — Migration 012: FK from posts.highlight_id → highlights.id
-- Run in Supabase SQL Editor. Idempotent (drops and re-creates the constraint).
--
-- Problem: posts.highlight_id was declared as plain `uuid` with no FK constraint.
-- PostgREST cannot infer the join for `.select('*, highlights(...)')` without a FK.
-- The join throws a 400/500 error that is swallowed by the `catch (_)` in
-- fetchPosts(), returning [] and making all posts invisible in the feed.
--
-- Fix: add the FK and ensure image_url column exists.

-- ─── 1. Add FK: posts.highlight_id → highlights.id ──────────────────────────

ALTER TABLE public.posts
  DROP CONSTRAINT IF EXISTS posts_highlight_id_fkey;

ALTER TABLE public.posts
  ADD CONSTRAINT posts_highlight_id_fkey
    FOREIGN KEY (highlight_id)
    REFERENCES public.highlights(id)
    ON DELETE SET NULL;

-- ─── 2. Ensure image_url column exists (idempotent from 009) ────────────────

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS image_url text;

-- ─── 3. Ensure buckets are public (idempotent repeat of 011 for safety) ─────

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('avatars',        'avatars',        true),
  ('covers',         'covers',         true),
  ('post-images',    'post-images',    true),
  ('comment-images', 'comment-images', true),
  ('jam-covers',     'jam-covers',     true)
ON CONFLICT (id) DO UPDATE SET public = true;
