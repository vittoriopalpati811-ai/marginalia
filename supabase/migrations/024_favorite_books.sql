-- ─── Migration 024 — Favourite books on profile ───────────────────────────────
--
-- Adds a jsonb column to profiles for the 6 hand-picked "libri del cuore".
-- Each element is { "title": "...", "author": "..." }.
-- Retrocompatible: existing rows default to an empty array.
--
-- Apply via Supabase SQL Editor:
--   https://supabase.com/dashboard/project/<your-project>/sql/new
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS favorite_books jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Allow users to update their own favorite_books (existing RLS already covers
-- rows owned by the authenticated user; this is just documentation).
-- No new policy needed — the existing "Users can update own profile" policy
-- on public.profiles already permits all column updates to own row.
