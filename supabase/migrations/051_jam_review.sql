-- 051_jam_review.sql
--
-- Jam review competition: the "Ripasso" leaderboard inside each Jam, plus the
-- recipient list for the "member finished today's review" push.
--
-- Two SECURITY DEFINER RPCs, mirroring the posture of the existing ones
-- (mark_conversation_read / get_conversation_member_profiles / is_jam_member):
--   * search_path pinned to public so the function can't be hijacked,
--   * auth.uid() guards so an unauthenticated / non-member caller gets nothing,
--   * EXECUTE revoked from PUBLIC (removes the inherited anon path) and granted
--     only to `authenticated`, ending with a PostgREST schema reload.
--
-- Reads the streak mirror columns added by migration 050
-- (profiles.review_streak / review_best_streak / last_reviewed_on). The LOCAL
-- Isar ReviewState stays authoritative; these RPCs only expose what the client
-- already publishes there.

-- ─── jam_review_leaderboard ────────────────────────────────────────────────────
--
-- For every member of `p_jam_id` (the jam OWNER is always a member by virtue of
-- being in jam_members; a left-join from jam_members -> profiles), returns the
-- streak snapshot ordered by current streak desc. `reviewed_today` is computed
-- server-side against current_date so the client never has to reason about the
-- day boundary / clock skew. Self-guarded: only a member of the jam (or its
-- owner) may call it; everyone else gets zero rows.

create or replace function public.jam_review_leaderboard(p_jam_id uuid)
returns table (
  id                uuid,
  display_name      text,
  avatar_url        text,
  review_streak     int,
  review_best_streak int,
  last_reviewed_on  date,
  reviewed_today    boolean
)
language sql
security definer
stable
set search_path = public
as $$
  select
    p.id,
    p.display_name,
    p.avatar_url,
    coalesce(p.review_streak, 0)      as review_streak,
    coalesce(p.review_best_streak, 0) as review_best_streak,
    p.last_reviewed_on,
    (p.last_reviewed_on = current_date) as reviewed_today
  from public.jam_members jm
  join public.profiles p on p.id = jm.user_id
  where jm.jam_id = p_jam_id
    -- Only members of this jam (or its owner) may read the leaderboard.
    and (
      exists (
        select 1 from public.jam_members me
        where me.jam_id = p_jam_id and me.user_id = auth.uid()
      )
      or exists (
        select 1 from public.jams j
        where j.id = p_jam_id and j.owner_id = auth.uid()
      )
    )
  order by coalesce(p.review_streak, 0) desc,
           coalesce(p.review_best_streak, 0) desc,
           p.display_name asc nulls last;
$$;

-- ─── jam_mates_for_review ──────────────────────────────────────────────────────
--
-- The DISTINCT user ids of every OTHER member across ALL jams the caller belongs
-- to (caller excluded). Used to fan out the "finished today's review" push to a
-- reader's jam-mates. Returns nothing for an unauthenticated caller.

create or replace function public.jam_mates_for_review()
returns table (user_id uuid)
language sql
security definer
stable
set search_path = public
as $$
  select distinct other.user_id
  from public.jam_members mine
  join public.jam_members other on other.jam_id = mine.jam_id
  where mine.user_id = auth.uid()
    and other.user_id <> auth.uid()
    and auth.uid() is not null;
$$;

-- ─── Grants: revoke the inherited PUBLIC path, allow only authenticated ─────────

revoke execute on function public.jam_review_leaderboard(uuid) from public;
grant  execute on function public.jam_review_leaderboard(uuid) to authenticated;

revoke execute on function public.jam_mates_for_review() from public;
grant  execute on function public.jam_mates_for_review() to authenticated;

notify pgrst, 'reload schema';
