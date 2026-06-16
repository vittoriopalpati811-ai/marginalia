-- 069_jam_poll_candidates_update_policy.sql
--
-- jam_poll_candidates had INSERT + SELECT + DELETE RLS policies but NO UPDATE
-- policy. The client submits candidates with
--   .upsert(onConflict: 'poll_id,submitted_by')
-- so re-submitting (a user changing their candidate for a poll) becomes
-- INSERT ... ON CONFLICT DO UPDATE. The UPDATE branch needs an UPDATE policy;
-- without one Postgres rejects it with 42501 "new row violates row-level
-- security policy (USING expression) for table jam_poll_candidates" — exactly
-- the error the founder hit.
--
-- Add an UPDATE policy letting the submitter change their own candidate while
-- the poll is still open and they're still a jam member (is_jam_member already
-- includes the jam owner).

drop policy if exists jam_poll_candidates_update on public.jam_poll_candidates;

create policy jam_poll_candidates_update
  on public.jam_poll_candidates for update
  using (auth.uid() = submitted_by)
  with check (
    auth.uid() = submitted_by
    and exists (
      select 1 from public.jam_highlight_polls p
      where p.id = jam_poll_candidates.poll_id
        and is_jam_member(p.jam_id)
        and not p.is_closed
    )
  );
