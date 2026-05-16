-- Marginalia — Migration 004: profile reading status, reactions, comments, role in jam_members
-- Run in Supabase SQL editor.  Idempotent.

-- ─────────────────────────────────────────────
-- PROFILES: add reading status + bio columns
-- ─────────────────────────────────────────────
alter table public.profiles
  add column if not exists currently_reading_title  text,
  add column if not exists currently_reading_author text,
  add column if not exists bio                      text;

-- ─────────────────────────────────────────────
-- JAM_MEMBERS: add role column
-- ─────────────────────────────────────────────
alter table public.jam_members
  add column if not exists role text not null default 'member';

-- ─────────────────────────────────────────────
-- JAM_HIGHLIGHTS: reactions + comments
-- ─────────────────────────────────────────────
create table if not exists public.jam_highlight_reactions (
  id               uuid primary key default gen_random_uuid(),
  jam_highlight_id uuid not null,
  user_id          uuid references auth.users on delete cascade not null,
  emoji            text not null,
  created_at       timestamptz default now() not null,
  unique (jam_highlight_id, user_id, emoji)
);

create index if not exists reactions_jam_hl_idx on public.jam_highlight_reactions(jam_highlight_id);

create table if not exists public.jam_highlight_comments (
  id               uuid primary key default gen_random_uuid(),
  jam_highlight_id uuid not null,
  user_id          uuid references auth.users on delete cascade not null,
  content          text not null,
  created_at       timestamptz default now() not null
);

create index if not exists comments_jam_hl_idx on public.jam_highlight_comments(jam_highlight_id);

-- RLS for reactions
alter table public.jam_highlight_reactions enable row level security;
drop policy if exists "reactions_select" on public.jam_highlight_reactions;
drop policy if exists "reactions_insert" on public.jam_highlight_reactions;
drop policy if exists "reactions_delete" on public.jam_highlight_reactions;
create policy "reactions_select" on public.jam_highlight_reactions
  for select using (auth.role() = 'authenticated');
create policy "reactions_insert" on public.jam_highlight_reactions
  for insert with check (auth.uid() = user_id);
create policy "reactions_delete" on public.jam_highlight_reactions
  for delete using (auth.uid() = user_id);

-- RLS for comments
alter table public.jam_highlight_comments enable row level security;
drop policy if exists "comments_select" on public.jam_highlight_comments;
drop policy if exists "comments_insert" on public.jam_highlight_comments;
drop policy if exists "comments_delete" on public.jam_highlight_comments;
create policy "comments_select" on public.jam_highlight_comments
  for select using (auth.role() = 'authenticated');
create policy "comments_insert" on public.jam_highlight_comments
  for insert with check (auth.uid() = user_id);
create policy "comments_delete" on public.jam_highlight_comments
  for delete using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- FOLLOWS (may already exist from migration 003)
-- ─────────────────────────────────────────────
create table if not exists public.follows (
  follower_id  uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

alter table public.follows enable row level security;
drop policy if exists "follows_select" on public.follows;
drop policy if exists "follows_insert" on public.follows;
drop policy if exists "follows_delete" on public.follows;
create policy "follows_select" on public.follows
  for select using (auth.role() = 'authenticated');
create policy "follows_insert" on public.follows
  for insert with check (auth.uid() = follower_id);
create policy "follows_delete" on public.follows
  for delete using (auth.uid() = follower_id);

create index if not exists follows_follower_idx  on public.follows (follower_id);
create index if not exists follows_following_idx on public.follows (following_id);
