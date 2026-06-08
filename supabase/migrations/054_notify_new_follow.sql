-- 054_notify_new_follow.sql
--
-- In-app notification when someone follows you. Mirrors notify_post_interaction
-- (036): a single SECURITY DEFINER RPC, no table/column changes — the existing
-- `notifications` table already has every column we need (user_id, type, title,
-- body, data jsonb). The actor id is stored inside `data`.
--
-- WHY AN RPC (not a client insert): `notifications` has NO INSERT policy
-- (migration 032 dropped it on purpose) so RLS denies direct client inserts.
-- This definer function runs as the table owner, derives the recipient
-- SERVER-SIDE (the followed user), uses auth.uid() as the actor, and verifies
-- the follow really exists — so a caller cannot forge a follow notification.
--
-- ⚠️ Applied via the Supabase MCP (idempotent: create or replace + guarded
-- grants), not a blind migration runner.

create or replace function public.notify_new_follow(p_following_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_actor uuid := auth.uid();
  v_name  text;
begin
  if v_actor is null then return; end if;

  -- Never notify yourself.
  if p_following_id = v_actor then return; end if;

  -- Only notify if the caller genuinely follows the target (anti-spam): a real
  -- follows row must exist before we create the notification.
  if not exists (
    select 1 from public.follows
    where follower_id = v_actor and following_id = p_following_id
  ) then
    return;
  end if;

  -- Actor display name for the human-readable title (fallback "Qualcuno").
  select coalesce(nullif(trim(display_name), ''), 'Qualcuno')
    into v_name from public.profiles where id = v_actor;
  v_name := coalesce(v_name, 'Qualcuno');

  insert into public.notifications (user_id, type, title, body, data)
  values (
    p_following_id,
    'follow',
    v_name || ' ha iniziato a seguirti',
    '',
    jsonb_build_object('actor_id', v_actor)
  );
end;
$$;

comment on function public.notify_new_follow(uuid) is
  'Creates a ''follow'' notification for the user identified by p_following_id. '
  'Recipient is that user; actor is auth.uid(). Skips self-notify and requires '
  'a real follows row. Stores actor_id in notifications.data for navigation.';

-- Signed-in users may call this; anon may not. The function enforces that the
-- caller can only notify someone they actually follow, as themselves.
revoke execute on function public.notify_new_follow(uuid) from public;
grant  execute on function public.notify_new_follow(uuid) to authenticated;

-- Reload PostgREST schema cache so the RPC is callable immediately.
notify pgrst, 'reload schema';
