-- 035_post_interaction_notifications.sql
--
-- Two SECURITY DEFINER RPCs. NO table/column changes — the existing
-- `notifications` table (migration 023) already has every column we need
-- (user_id, type, title, body, data jsonb, is_read, created_at). The actor id
-- and post id are stored inside the `data` jsonb, so no new columns are added.
--
-- ⚠️ DO NOT APPLY BLINDLY FROM A MIGRATION RUNNER yet — the parent applies this
-- via the Supabase MCP. It is written to be idempotent (create or replace +
-- guarded grants) so re-running is safe.
--
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY RPCs INSTEAD OF CLIENT-SIDE INSERTS
-- ───────────────────────────────────────────────────────────────────────────────
--   • notifications has NO INSERT policy (migration 032 dropped it on purpose),
--     so RLS denies any direct client insert (fail-closed).
--   • create_notification() had its EXECUTE revoked from anon/authenticated
--     (migration 028) and raises if called by those roles.
--   • Both rules exist to stop forged/spam notifications (arbitrary user_id /
--     title / body). We keep that guarantee here: each function runs as the
--     table owner (SECURITY DEFINER), derives the recipient SERVER-SIDE, and
--     uses auth.uid() as the actor — the caller cannot choose who gets notified
--     nor impersonate another actor.


-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) public_user_stats(target_id) — TRUE profile counts, bypassing RLS
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- Used by SupabaseService.fetchUserStats() to render another user's profile
-- stats row (highlights / shared / following / followers).
--
-- Needed because `highlights` and `jam_highlights` are NOT world-readable
-- (migration 002: highlights are owner-only, visible to others only when shared
-- into a common Jam). Counting them directly from the client therefore returns
-- the WRONG total for a stranger. This definer function counts them correctly.
-- It returns ONLY four integers (counts) — never highlight content — so it
-- leaks nothing sensitive beyond aggregate numbers the profile already shows.

create or replace function public.public_user_stats(target_id uuid)
returns table (
  highlights integer,
  shared     integer,
  following  integer,
  followers  integer
)
language sql
security definer
set search_path = public, pg_catalog
as $$
  select
    (select count(*)::int from public.highlights      h  where h.user_id      = target_id),
    (select count(*)::int from public.jam_highlights   jh where jh.shared_by    = target_id),
    (select count(*)::int from public.follows          f  where f.follower_id   = target_id),
    (select count(*)::int from public.follows          f  where f.following_id  = target_id);
$$;

comment on function public.public_user_stats(uuid) is
  'Aggregate public profile counts (highlights/shared/following/followers) for '
  'any user, computed bypassing RLS. Returns counts only — no content.';

-- Any signed-in user may read these aggregate counts; anon may not.
revoke execute on function public.public_user_stats(uuid) from public;
grant  execute on function public.public_user_stats(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) notify_post_interaction(p_post_id, p_kind, p_preview) — like/comment alerts
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- Called by SupabaseService after a successful like / comment. Inserts ONE row
-- into notifications for the POST OWNER:
--   • type    = 'like' | 'comment'
--   • title   = localized (Italian) actor sentence using the actor's display_name
--   • body    = comment preview (for comments) — empty for likes
--   • data    = {"post_id": "...", "actor_id": "..."} for in-app navigation
--   • user_id = the post's owner (derived server-side from posts.user_id)
--
-- Self-interactions are skipped (you never notify yourself).

create or replace function public.notify_post_interaction(
  p_post_id uuid,
  p_kind    text,
  p_preview text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_actor   uuid := auth.uid();
  v_owner   uuid;
  v_name    text;
  v_title   text;
  v_body    text;
  v_preview text;
begin
  -- Must be a signed-in user, and only the two supported kinds.
  if v_actor is null then
    return;
  end if;
  if p_kind not in ('like', 'comment') then
    return;
  end if;

  -- Resolve the post owner. If the post vanished, do nothing.
  select user_id into v_owner from public.posts where id = p_post_id;
  if v_owner is null then
    return;
  end if;

  -- Never notify yourself.
  if v_owner = v_actor then
    return;
  end if;

  -- Actor display name for the human-readable title (fallback: "Qualcuno").
  select coalesce(nullif(trim(display_name), ''), 'Qualcuno')
    into v_name
    from public.profiles
   where id = v_actor;
  v_name := coalesce(v_name, 'Qualcuno');

  -- Compose Italian copy. (The Flutter client renders title/body verbatim and
  -- also picks a heart/comment icon from `type`, so keep these self-contained.)
  if p_kind = 'like' then
    v_title := v_name || ' ha messo mi piace al tuo post';
    v_body  := '';
  else
    v_title := v_name || ' ha commentato il tuo post';
    v_preview := nullif(trim(coalesce(p_preview, '')), '');
    if v_preview is not null then
      if char_length(v_preview) > 140 then
        v_preview := left(v_preview, 140) || '…';
      end if;
      v_body := v_preview;
    else
      v_body := '';
    end if;
  end if;

  insert into public.notifications (user_id, type, title, body, data)
  values (
    v_owner,
    p_kind,
    v_title,
    v_body,
    jsonb_build_object('post_id', p_post_id, 'actor_id', v_actor)
  );
end;
$$;

comment on function public.notify_post_interaction(uuid, text, text) is
  'Creates a like/comment notification for a post owner. Recipient is derived '
  'server-side from posts.user_id; actor is auth.uid(). Skips self-notify. '
  'Stores post_id + actor_id in notifications.data for navigation.';

-- Signed-in users may call this; anon may not. The function itself enforces
-- that the caller can only notify a post's real owner (not an arbitrary user)
-- and only as themselves, so granting it to authenticated is safe.
revoke execute on function public.notify_post_interaction(uuid, text, text) from public;
grant  execute on function public.notify_post_interaction(uuid, text, text) to authenticated;

-- Reload PostgREST schema cache so the new RPCs are callable immediately.
notify pgrst, 'reload schema';
