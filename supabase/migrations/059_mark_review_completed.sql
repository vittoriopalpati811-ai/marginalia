-- 059: server-side ripasso completion (already applied live as
-- `mark_review_completed_rpc` + grant hardening; this file captures it so a
-- rebuilt environment matches production).
--
-- One atomic entry point called by the app on each graded card:
--   (a) bumps the caller's review streak on profiles — the columns
--       jam_review_leaderboard reads — and
--   (b) records today's completion in EVERY jam the caller belongs to
--       (members AND owners), so the jam "Ripasso" section lights up.
-- Idempotent per (user, Europe/Rome day); repeated calls only raise
-- cards_reviewed (greatest). Replaces the old client-side mirrors that left
-- profiles.review_streak at 0 ("ancora nessuna serie" after a completed
-- ripasso).

create or replace function public.mark_review_completed(p_cards integer default null)
returns table(review_streak integer, review_best_streak integer, reviewed_on date)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Europe/Rome')::date;
  v_streak integer;
  v_best integer;
  v_last date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select p.review_streak, p.review_best_streak, p.last_reviewed_on
    into v_streak, v_best, v_last
    from profiles p where p.id = v_uid
    for update;

  if v_last is distinct from v_today then
    if v_last = v_today - 1 then
      v_streak := coalesce(v_streak, 0) + 1;
    else
      v_streak := 1;
    end if;
    v_best := greatest(coalesce(v_best, 0), v_streak);
    update profiles p
       set review_streak = v_streak,
           review_best_streak = v_best,
           last_reviewed_on = v_today
     where p.id = v_uid;
  else
    v_streak := coalesce(v_streak, 0);
    v_best := coalesce(v_best, 0);
  end if;

  insert into jam_ripasso_results (jam_id, user_id, completed_on, cards_reviewed)
  select j.jam_id, v_uid, v_today, p_cards
    from (
      select jm.jam_id from jam_members jm where jm.user_id = v_uid
      union
      select ja.id from jams ja where ja.owner_id = v_uid
    ) j
  on conflict (jam_id, user_id, completed_on)
  do update set cards_reviewed = greatest(
    coalesce(jam_ripasso_results.cards_reviewed, 0),
    coalesce(excluded.cards_reviewed, 0));

  return query select v_streak, v_best, v_today;
end;
$$;

-- Match the project's hardening posture (043/051): no PUBLIC/anon execute.
revoke execute on function public.mark_review_completed(integer) from public;
revoke execute on function public.mark_review_completed(integer) from anon;
grant execute on function public.mark_review_completed(integer) to authenticated;

-- jam_review_leaderboard: reviewed_today now uses the same Europe/Rome
-- calendar date the completion writes, so the two can never disagree.
create or replace function public.jam_review_leaderboard(p_jam_id uuid)
returns table(id uuid, display_name text, avatar_url text, review_streak integer, review_best_streak integer, last_reviewed_on date, reviewed_today boolean)
language sql
stable security definer
set search_path to 'public'
as $$
  select
    p.id,
    p.display_name,
    p.avatar_url,
    coalesce(p.review_streak, 0)      as review_streak,
    coalesce(p.review_best_streak, 0) as review_best_streak,
    p.last_reviewed_on,
    (p.last_reviewed_on = (now() at time zone 'Europe/Rome')::date) as reviewed_today
  from public.profiles p
  where
    (
      exists (select 1 from public.jam_members me
              where me.jam_id = p_jam_id and me.user_id = auth.uid())
      or exists (select 1 from public.jams j
                 where j.id = p_jam_id and j.owner_id = auth.uid())
    )
    and
    (
      p.id in (select jm.user_id from public.jam_members jm where jm.jam_id = p_jam_id)
      or p.id in (select j.owner_id from public.jams j where j.id = p_jam_id)
    )
  order by coalesce(p.review_streak, 0) desc,
           coalesce(p.review_best_streak, 0) desc,
           p.display_name asc nulls last;
$$;

notify pgrst, 'reload schema';
