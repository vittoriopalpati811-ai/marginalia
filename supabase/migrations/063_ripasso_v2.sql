-- 063_ripasso_v2.sql
-- Ripasso 2.0 backend: quiz-merged sessions with time-of-day, duration and
-- score, plus per-jam period leaderboards (day / week / month).
--
-- Also captures the long-standing drift: jam_ripasso_results and
-- jam_quiz_results were created live but never written to a migration file.
-- The CREATE TABLE IF NOT EXISTS below is a no-op in production and makes a
-- rebuilt environment match it.

-- ── Drift capture (no-op live) ──────────────────────────────────────────────

create table if not exists public.jam_ripasso_results (
  id           uuid primary key default gen_random_uuid(),
  jam_id       uuid not null references public.jams(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  completed_on date not null,
  cards_reviewed integer,
  completed_at timestamptz not null default now(),
  unique (jam_id, user_id, completed_on)
);
alter table public.jam_ripasso_results enable row level security;

create table if not exists public.jam_quiz_results (
  id           uuid primary key default gen_random_uuid(),
  jam_id       uuid not null references public.jams(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  completed_on date not null,
  score        integer,
  total        integer,
  completed_at timestamptz not null default now(),
  unique (jam_id, user_id, completed_on)
);
alter table public.jam_quiz_results enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='jam_ripasso_results' and policyname='jam_ripasso_read_member') then
    create policy jam_ripasso_read_member on public.jam_ripasso_results
      for select using (is_jam_member_or_owner(jam_id));
    create policy jam_ripasso_insert_own on public.jam_ripasso_results
      for insert with check (user_id = auth.uid() and is_jam_member_or_owner(jam_id));
    create policy jam_ripasso_update_own on public.jam_ripasso_results
      for update using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='jam_quiz_results' and policyname='jam_quiz_read_member') then
    create policy jam_quiz_read_member on public.jam_quiz_results
      for select using (is_jam_member_or_owner(jam_id));
    create policy jam_quiz_insert_own on public.jam_quiz_results
      for insert with check (user_id = auth.uid() and is_jam_member_or_owner(jam_id));
    create policy jam_quiz_update_own on public.jam_quiz_results
      for update using (user_id = auth.uid());
  end if;
end $$;

-- ── Ripasso 2.0 columns ─────────────────────────────────────────────────────

alter table public.jam_ripasso_results
  add column if not exists score integer,
  add column if not exists total integer,
  add column if not exists duration_seconds integer;

-- ── mark_review_completed_v2 ────────────────────────────────────────────────
-- Called ONCE at the end of a completed Ripasso 2.0 session (the v1 RPC was
-- called per graded card and stays for old clients). Same streak semantics as
-- 059, plus score / total / duration / fresh completed_at on every jam row.

create or replace function public.mark_review_completed_v2(
  p_cards integer default null,
  p_score integer default null,
  p_total integer default null,
  p_duration_seconds integer default null
)
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

  insert into jam_ripasso_results
    (jam_id, user_id, completed_on, cards_reviewed, score, total, duration_seconds, completed_at)
  select j.jam_id, v_uid, v_today, p_cards, p_score, p_total, p_duration_seconds, now()
    from (
      select jm.jam_id from jam_members jm where jm.user_id = v_uid
      union
      select ja.id from jams ja where ja.owner_id = v_uid
    ) j
  on conflict (jam_id, user_id, completed_on)
  do update set
    cards_reviewed   = greatest(coalesce(jam_ripasso_results.cards_reviewed, 0),
                                coalesce(excluded.cards_reviewed, 0)),
    score            = coalesce(excluded.score, jam_ripasso_results.score),
    total            = coalesce(excluded.total, jam_ripasso_results.total),
    duration_seconds = coalesce(excluded.duration_seconds, jam_ripasso_results.duration_seconds),
    completed_at     = case when excluded.score is not null
                            then excluded.completed_at
                            else jam_ripasso_results.completed_at end;

  return query select v_streak, v_best, v_today;
end;
$$;

revoke execute on function public.mark_review_completed_v2(integer, integer, integer, integer) from public;
revoke execute on function public.mark_review_completed_v2(integer, integer, integer, integer) from anon;
grant execute on function public.mark_review_completed_v2(integer, integer, integer, integer) to authenticated;

-- ── Per-jam period leaderboard (day / week / month, Europe/Rome) ────────────
-- Aggregated on read: the data volume is tiny (one row per member per day).
-- Ordered by total score, ties broken by total time (faster wins). The app
-- derives the day-titles ("Il più veloce", "Il primo/La prima", "Il più
-- preciso") from the day rows; gender comes along for the title wording.

create or replace function public.jam_ripasso_leaderboard_period(
  p_jam_id uuid,
  p_period text default 'day'
)
returns table(
  user_id uuid,
  display_name text,
  avatar_url text,
  gender text,
  sessions integer,
  total_score integer,
  total_questions integer,
  total_duration_seconds integer,
  best_duration_seconds integer,
  first_completed_at timestamptz
)
language plpgsql
stable security definer
set search_path to 'public'
as $$
declare
  v_today date := (now() at time zone 'Europe/Rome')::date;
  v_start date;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_jam_member_or_owner(p_jam_id) then
    raise exception 'not a member of this jam';
  end if;

  v_start := case p_period
    when 'week'  then date_trunc('week',  (now() at time zone 'Europe/Rome'))::date
    when 'month' then date_trunc('month', (now() at time zone 'Europe/Rome'))::date
    else v_today
  end;

  return query
  select
    r.user_id,
    p.display_name,
    p.avatar_url,
    p.gender,
    count(*)::integer                                   as sessions,
    coalesce(sum(r.score), 0)::integer                  as total_score,
    coalesce(sum(r.total), 0)::integer                  as total_questions,
    coalesce(sum(r.duration_seconds), 0)::integer       as total_duration_seconds,
    min(r.duration_seconds)::integer                    as best_duration_seconds,
    min(r.completed_at)                                 as first_completed_at
  from jam_ripasso_results r
  join profiles p on p.id = r.user_id
  where r.jam_id = p_jam_id
    and r.completed_on between v_start and v_today
  group by r.user_id, p.display_name, p.avatar_url, p.gender
  order by coalesce(sum(r.score), 0) desc,
           coalesce(sum(r.duration_seconds), 2147483647) asc,
           p.display_name asc nulls last;
end;
$$;

revoke execute on function public.jam_ripasso_leaderboard_period(uuid, text) from public;
revoke execute on function public.jam_ripasso_leaderboard_period(uuid, text) from anon;
grant execute on function public.jam_ripasso_leaderboard_period(uuid, text) to authenticated;

notify pgrst, 'reload schema';
