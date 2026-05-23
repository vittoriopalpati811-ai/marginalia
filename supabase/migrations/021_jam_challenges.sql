-- ─── Jam 2.0: Reading Challenges ─────────────────────────────────────────────
--
-- A Jam admin creates a shared reading challenge (e.g. "Read 3 books by June").
-- Each member tracks their own progress.
-- Run in Supabase SQL Editor.

-- ─── Challenges ───────────────────────────────────────────────────────────────

create table public.jam_challenges (
  id            uuid primary key default gen_random_uuid(),
  jam_id        uuid references public.jams(id) on delete cascade not null,
  created_by    uuid references auth.users(id) on delete cascade not null,
  title         text not null,
  description   text,
  target_count  int default 1 not null check (target_count > 0),
  unit          text default 'books' not null,  -- 'books' | 'highlights' | 'chapters'
  deadline      timestamptz,
  is_active     boolean default true not null,
  created_at    timestamptz default now() not null
);

create index jam_challenges_jam_idx on public.jam_challenges(jam_id);

-- ─── Per-member progress ──────────────────────────────────────────────────────

create table public.jam_challenge_progress (
  challenge_id   uuid references public.jam_challenges(id) on delete cascade not null,
  user_id        uuid references auth.users(id) on delete cascade not null,
  current_count  int default 0 not null check (current_count >= 0),
  updated_at     timestamptz default now() not null,
  primary key (challenge_id, user_id)
);

-- ─── RLS ──────────────────────────────────────────────────────────────────────

alter table public.jam_challenges          enable row level security;
alter table public.jam_challenge_progress  enable row level security;

-- Challenges: readable by Jam members; insertable by Jam owner/admin
create policy "jam_challenges_select" on public.jam_challenges
  for select using (is_jam_member(jam_id));

create policy "jam_challenges_insert" on public.jam_challenges
  for insert with check (
    auth.uid() = created_by
    and (
      is_jam_member(jam_id)
      or exists (select 1 from public.jams where id = jam_id and owner_id = auth.uid())
    )
  );

create policy "jam_challenges_update" on public.jam_challenges
  for update using (auth.uid() = created_by);

create policy "jam_challenges_delete" on public.jam_challenges
  for delete using (auth.uid() = created_by);

-- Progress: each user manages their own row; all Jam members can read
create policy "jam_challenge_progress_select" on public.jam_challenge_progress
  for select using (
    exists (
      select 1 from public.jam_challenges c
      where c.id = challenge_id and is_jam_member(c.jam_id)
    )
  );

create policy "jam_challenge_progress_upsert" on public.jam_challenge_progress
  for all using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ─── Realtime ─────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.jam_challenges;
alter publication supabase_realtime add table public.jam_challenge_progress;
