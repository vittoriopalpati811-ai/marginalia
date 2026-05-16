-- 003_follows.sql — Social follow system
-- Twitter/Instagram-style asymmetric follow (A follows B, B need not follow A back)

create table if not exists public.follows (
  follower_id  uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

alter table public.follows enable row level security;

-- Anyone authenticated can see all follow relationships (needed for counts & suggestions)
create policy "follows_select" on public.follows
  for select using (auth.role() = 'authenticated');

-- Users can only follow as themselves
create policy "follows_insert" on public.follows
  for insert with check (auth.uid() = follower_id);

-- Users can only unfollow their own follows
create policy "follows_delete" on public.follows
  for delete using (auth.uid() = follower_id);

-- Index for fast follower/following lookups
create index if not exists follows_follower_idx  on public.follows (follower_id);
create index if not exists follows_following_idx on public.follows (following_id);
