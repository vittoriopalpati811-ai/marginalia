-- 067_fix_jam_poll_votes_recursion.sql
-- FIX: voting on a jam highlight poll raised
--   PostgrestException 42P17 "infinite recursion detected in policy for
--   relation jam_poll_votes"  → NOBODY could vote (heart) a poll candidate.
--
-- Cause: the jam_poll_votes INSERT policy enforced "one vote per poll" with a
-- subquery that read jam_poll_votes itself. A RLS policy that reads its own
-- table makes Postgres re-apply the policy recursively → 42P17.
--
-- Fix: move the "already voted in this poll?" check into a SECURITY DEFINER
-- function (which bypasses RLS, so it does not re-enter the policy), and call
-- it from the policy. The membership + poll-open checks are unchanged.

create or replace function public.has_voted_in_poll(p_candidate_id uuid)
returns boolean
language sql
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1
    from jam_poll_votes v
    join jam_poll_candidates c on c.id = v.candidate_id
    where v.user_id = auth.uid()
      and c.poll_id = (select poll_id from jam_poll_candidates where id = p_candidate_id)
  );
$$;

grant execute on function public.has_voted_in_poll(uuid) to authenticated, anon;

drop policy if exists "jam_poll_votes_insert" on public.jam_poll_votes;
create policy "jam_poll_votes_insert" on public.jam_poll_votes
  for insert to public
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from jam_poll_candidates c
      join jam_highlight_polls p on p.id = c.poll_id
      where c.id = jam_poll_votes.candidate_id
        and is_jam_member(p.jam_id)
        and not p.is_closed
    )
    and not has_voted_in_poll(jam_poll_votes.candidate_id)
  );
