-- ─── Migration 035 — Social book reviews ──────────────────────────────────────
--
-- Readers can write a short "recensione" (1–5 star rating + a free-text
-- "perché") for any book they have highlights of. Reviews are SOCIAL:
-- anyone can read them (the profile's "Recensioni" tab is public), but only
-- the author can create, edit, or delete their own.
--
-- A review may optionally carry one attached highlight (denormalised as
-- plain text so it survives even if the source highlight is later deleted
-- or re-imported with a new id).
--
-- Apply via Supabase SQL Editor:
--   https://supabase.com/dashboard/project/<your-project>/sql/new
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.reviews (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references auth.users(id) on delete cascade not null,
  book_title     text not null,
  book_author    text not null default '',
  rating         int  not null check (rating between 1 and 5),
  body           text not null default '',
  highlight_text text,
  created_at     timestamptz not null default now()
);

-- Newest-first listing per user (profile "Recensioni" tab).
create index if not exists reviews_user_created_idx
  on public.reviews (user_id, created_at desc);

-- ─── Row Level Security ───────────────────────────────────────────────────────
-- Reviews are social: SELECT is open to everyone. Mutations are restricted to
-- the authoring user.

alter table public.reviews enable row level security;

-- Anyone (including anon) can read reviews — they're a public, social signal.
drop policy if exists "Reviews are publicly readable" on public.reviews;
create policy "Reviews are publicly readable"
  on public.reviews for select
  using (true);

-- Only the author can insert their own reviews.
drop policy if exists "Users insert own reviews" on public.reviews;
create policy "Users insert own reviews"
  on public.reviews for insert
  with check (auth.uid() = user_id);

-- Only the author can edit their own reviews.
drop policy if exists "Users update own reviews" on public.reviews;
create policy "Users update own reviews"
  on public.reviews for update
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Only the author can delete their own reviews.
drop policy if exists "Users delete own reviews" on public.reviews;
create policy "Users delete own reviews"
  on public.reviews for delete
  using (auth.uid() = user_id);
