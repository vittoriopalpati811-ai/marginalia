-- ─── Jam 2.0: Book of the Month Voting ───────────────────────────────────────
--
-- Members can propose books and vote for the next Jam read.
-- One vote per user per proposal; proposals are scoped per Jam.
-- Run in Supabase SQL Editor.

-- ─── Book proposals ───────────────────────────────────────────────────────────

create table public.jam_book_proposals (
  id           uuid primary key default gen_random_uuid(),
  jam_id       uuid references public.jams(id) on delete cascade not null,
  proposed_by  uuid references auth.users(id) on delete cascade not null,
  title        text not null,
  author       text,
  description  text,
  cover_url    text,
  is_winner    boolean default false not null,
  created_at   timestamptz default now() not null,
  unique(jam_id, title, proposed_by)          -- one proposal per user+title per Jam
);

create index jam_book_proposals_jam_idx on public.jam_book_proposals(jam_id);

-- ─── Votes on proposals ───────────────────────────────────────────────────────

create table public.jam_book_votes (
  proposal_id  uuid references public.jam_book_proposals(id) on delete cascade not null,
  user_id      uuid references auth.users(id) on delete cascade not null,
  created_at   timestamptz default now() not null,
  primary key (proposal_id, user_id)
);

-- ─── RLS ──────────────────────────────────────────────────────────────────────

alter table public.jam_book_proposals enable row level security;
alter table public.jam_book_votes      enable row level security;

-- Helper: is the user a member of this Jam?
create or replace function public.is_jam_member(p_jam_id uuid)
returns boolean
language sql security definer stable
as $$
  select exists (
    select 1 from public.jam_members
    where jam_id = p_jam_id and user_id = auth.uid()
  )
  or exists (
    select 1 from public.jams
    where id = p_jam_id and owner_id = auth.uid()
  );
$$;

-- Proposals: any Jam member can read; authenticated members can insert their own
create policy "jam_book_proposals_select" on public.jam_book_proposals
  for select using (is_jam_member(jam_id));

create policy "jam_book_proposals_insert" on public.jam_book_proposals
  for insert with check (
    auth.uid() = proposed_by
    and is_jam_member(jam_id)
  );

create policy "jam_book_proposals_delete" on public.jam_book_proposals
  for delete using (auth.uid() = proposed_by);

-- Votes: read by Jam members; insert/delete by authenticated members
create policy "jam_book_votes_select" on public.jam_book_votes
  for select using (
    exists (
      select 1 from public.jam_book_proposals p
      where p.id = proposal_id and is_jam_member(p.jam_id)
    )
  );

create policy "jam_book_votes_insert" on public.jam_book_votes
  for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.jam_book_proposals p
      where p.id = proposal_id and is_jam_member(p.jam_id)
    )
  );

create policy "jam_book_votes_delete" on public.jam_book_votes
  for delete using (auth.uid() = user_id);

-- ─── Realtime ─────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.jam_book_proposals;
alter publication supabase_realtime add table public.jam_book_votes;
