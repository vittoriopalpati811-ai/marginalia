-- 076 — Playable shelf posts.
--
-- A shared shelf used to be a flat PNG plus a question answered in the
-- comments, which is not interaction — it is a caption. These two additions let
-- the feed render the shelf LIVE and let a reader play it in place: tap the
-- spine you believe is the most-highlighted book and the post answers you.
--
--   • posts.payload — the shelf itself (titles, authors, highlight counts), so
--     the feed can draw real spines instead of a screenshot AND check an answer
--     without a round trip. Additive and nullable: every existing post and
--     every older client keeps working untouched.
--
--   • post_guesses — one row per player per post, which is what turns a
--     private guess into a shared result ("62% got it right").
--
-- Deliberate privacy line: a player may read back only their OWN guess, so the
-- table can never be mined to see what any particular person answered. The
-- crowd figure comes from post_guess_stats(), which returns two integers and
-- nothing else.

alter table public.posts add column if not exists payload jsonb;

create table if not exists public.post_guesses (
  post_id    uuid    not null references public.posts(id) on delete cascade,
  user_id    uuid    not null references auth.users(id)   on delete cascade,
  correct    boolean not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists post_guesses_post on public.post_guesses (post_id);

alter table public.post_guesses enable row level security;

-- Play once, as yourself. The primary key enforces the "once".
drop policy if exists "guess_insert_own" on public.post_guesses;
create policy "guess_insert_own"
  on public.post_guesses
  for insert to authenticated
  with check (auth.uid() = user_id);

-- Read back only your own answer, so a returning reader sees the post in the
-- state they left it — and so nobody can read anyone else's answer.
drop policy if exists "guess_select_own" on public.post_guesses;
create policy "guess_select_own"
  on public.post_guesses
  for select to authenticated
  using (auth.uid() = user_id);

-- The crowd result: two integers, no rows, no identities. SECURITY DEFINER
-- because the row-level policy above deliberately hides other people's answers;
-- this is the one aggregate view over them that is safe to share.
create or replace function public.post_guess_stats(p_post_id uuid)
returns table(total int, correct int)
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    count(*)::int,
    count(*) filter (where g.correct)::int
  from public.post_guesses g
  where g.post_id = p_post_id;
$$;

-- Signed-in players only: never reachable with the public anon key.
revoke execute on function public.post_guess_stats(uuid) from anon;
revoke execute on function public.post_guess_stats(uuid) from public;
grant execute on function public.post_guess_stats(uuid) to authenticated;
