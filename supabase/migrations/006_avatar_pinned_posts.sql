-- Marginalia — Migration 006: avatar, cover photo, pinned highlights, posts
-- Run in Supabase SQL Editor after 005. Idempotent.

-- ─── 1. Profile: avatar + cover photo URLs ───────────────────────────────────

alter table public.profiles
  add column if not exists avatar_url  text,
  add column if not exists cover_url   text;

-- ─── 2. Pinned highlights ────────────────────────────────────────────────────
-- Up to 3 highlights per user that appear in the "In evidenza" section.

create table if not exists public.pinned_highlights (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  highlight_id uuid not null,          -- references highlights(id)
  sort_order   int  not null default 0, -- 0 = top
  created_at   timestamptz not null default now(),
  unique (user_id, highlight_id)
);

-- RLS
alter table public.pinned_highlights enable row level security;

create policy if not exists "Users manage own pinned highlights"
  on public.pinned_highlights
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy if not exists "Pinned highlights visible to all authenticated users"
  on public.pinned_highlights
  for select
  using (auth.role() = 'authenticated');

-- ─── 3. Posts ────────────────────────────────────────────────────────────────
-- A post can be plain text, an attached highlight, or a video (url).

create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  body          text,                   -- testo libero (può essere null se solo video)
  highlight_id  uuid,                   -- highlight allegato (opzionale)
  video_url     text,                   -- URL video Supabase Storage (opzionale)
  jam_id        uuid references public.jams(id) on delete set null, -- contesto Jam (opzionale)
  likes_count   int  not null default 0,
  created_at    timestamptz not null default now()
);

-- Index per feed cronologico
create index if not exists posts_user_created on public.posts (user_id, created_at desc);
create index if not exists posts_created      on public.posts (created_at desc);

-- RLS
alter table public.posts enable row level security;

create policy if not exists "Users manage own posts"
  on public.posts
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy if not exists "Posts visible to authenticated users"
  on public.posts
  for select
  using (auth.role() = 'authenticated');

-- ─── 4. Post likes ───────────────────────────────────────────────────────────

create table if not exists public.post_likes (
  post_id  uuid not null references public.posts(id) on delete cascade,
  user_id  uuid not null references auth.users(id)  on delete cascade,
  primary key (post_id, user_id)
);

alter table public.post_likes enable row level security;

create policy if not exists "Users manage own post likes"
  on public.post_likes
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy if not exists "Post likes visible to authenticated users"
  on public.post_likes
  for select
  using (auth.role() = 'authenticated');

-- ─── 5. Storage buckets (eseguire separatamente se non esistono) ─────────────
-- Nota: i bucket vanno creati dal dashboard Supabase → Storage → New bucket.
-- Nome bucket avatars: public = true, maxFileSize = 5MB
-- Nome bucket covers:  public = true, maxFileSize = 10MB
-- Se si usa la CLI:
-- supabase storage create avatars --public
-- supabase storage create covers  --public
