-- ─── Jam 2.0: Weekly Highlight Polls ─────────────────────────────────────────
--
-- A Jam member creates a poll; others submit their favourite highlights as
-- candidates; members vote; poll auto-closes after deadline.
-- Run in Supabase SQL Editor.

-- ─── Poll ─────────────────────────────────────────────────────────────────────

create table public.jam_highlight_polls (
  id          uuid primary key default gen_random_uuid(),
  jam_id      uuid references public.jams(id) on delete cascade not null,
  created_by  uuid references auth.users(id) on delete cascade not null,
  title       text not null default 'Highlight della settimana',
  ends_at     timestamptz not null,
  is_closed   boolean default false not null,
  winner_id   uuid,       -- FK added below after candidates table exists
  created_at  timestamptz default now() not null
);

create index jam_highlight_polls_jam_idx on public.jam_highlight_polls(jam_id);

-- ─── Candidates (one per member per poll) ────────────────────────────────────

create table public.jam_poll_candidates (
  id                uuid primary key default gen_random_uuid(),
  poll_id           uuid references public.jam_highlight_polls(id) on delete cascade not null,
  submitted_by      uuid references auth.users(id) on delete cascade not null,
  highlight_content text not null,
  book_title        text,
  book_author       text,
  created_at        timestamptz default now() not null,
  unique(poll_id, submitted_by)     -- one candidate per user per poll
);

create index jam_poll_candidates_poll_idx on public.jam_poll_candidates(poll_id);

-- ─── Votes (one per member per poll) ─────────────────────────────────────────

create table public.jam_poll_votes (
  candidate_id  uuid references public.jam_poll_candidates(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  created_at    timestamptz default now() not null,
  primary key (candidate_id, user_id)
);

-- Add winner FK now that candidates table exists
alter table public.jam_highlight_polls
  add constraint fk_poll_winner
  foreign key (winner_id) references public.jam_poll_candidates(id)
  on delete set null;

-- ─── RLS ──────────────────────────────────────────────────────────────────────

alter table public.jam_highlight_polls  enable row level security;
alter table public.jam_poll_candidates  enable row level security;
alter table public.jam_poll_votes       enable row level security;

-- Polls
create policy "jam_polls_select" on public.jam_highlight_polls
  for select using (is_jam_member(jam_id));

create policy "jam_polls_insert" on public.jam_highlight_polls
  for insert with check (auth.uid() = created_by and is_jam_member(jam_id));

create policy "jam_polls_update" on public.jam_highlight_polls
  for update using (auth.uid() = created_by);

-- Candidates
create policy "jam_poll_candidates_select" on public.jam_poll_candidates
  for select using (
    exists (
      select 1 from public.jam_highlight_polls p
      where p.id = poll_id and is_jam_member(p.jam_id)
    )
  );

create policy "jam_poll_candidates_insert" on public.jam_poll_candidates
  for insert with check (
    auth.uid() = submitted_by
    and exists (
      select 1 from public.jam_highlight_polls p
      where p.id = poll_id and is_jam_member(p.jam_id) and not p.is_closed
    )
  );

create policy "jam_poll_candidates_delete" on public.jam_poll_candidates
  for delete using (auth.uid() = submitted_by);

-- Votes
create policy "jam_poll_votes_select" on public.jam_poll_votes
  for select using (
    exists (
      select 1 from public.jam_poll_candidates c
        join public.jam_highlight_polls p on p.id = c.poll_id
      where c.id = candidate_id and is_jam_member(p.jam_id)
    )
  );

create policy "jam_poll_votes_insert" on public.jam_poll_votes
  for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.jam_poll_candidates c
        join public.jam_highlight_polls p on p.id = c.poll_id
      where c.id = candidate_id and is_jam_member(p.jam_id) and not p.is_closed
    )
    -- Only one vote per user per poll
    and not exists (
      select 1 from public.jam_poll_votes v2
        join public.jam_poll_candidates c2 on c2.id = v2.candidate_id
      where v2.user_id = auth.uid() and c2.poll_id = (
        select poll_id from public.jam_poll_candidates where id = candidate_id
      )
    )
  );

create policy "jam_poll_votes_delete" on public.jam_poll_votes
  for delete using (auth.uid() = user_id);

-- ─── Realtime ─────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.jam_highlight_polls;
alter publication supabase_realtime add table public.jam_poll_candidates;
alter publication supabase_realtime add table public.jam_poll_votes;
