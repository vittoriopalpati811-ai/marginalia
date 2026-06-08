-- 055_notify_jam_highlight_comment.sql
--
-- In-app notification when someone comments on a highlight you shared into a
-- Jam. Mirrors notify_post_interaction (036): one SECURITY DEFINER RPC, no
-- table/column changes — recipient (the highlight's sharer) is derived
-- server-side from jam_highlights.shared_by, the actor is auth.uid(), and
-- self-comments are skipped. The jam_id + jam_highlight_id are stored in
-- notifications.data so tapping the notification opens the Jam.
--
-- ⚠️ Applied via the Supabase MCP (idempotent: create or replace + guarded
-- grants), not a blind migration runner.

create or replace function public.notify_jam_highlight_comment(
  p_jam_highlight_id uuid,
  p_preview          text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_actor   uuid := auth.uid();
  v_owner   uuid;
  v_jam     uuid;
  v_name    text;
  v_preview text;
begin
  if v_actor is null then return; end if;

  -- Recipient = whoever shared the jam highlight. Unknown highlight → no-op.
  select shared_by, jam_id into v_owner, v_jam
    from public.jam_highlights where id = p_jam_highlight_id;
  if v_owner is null then return; end if;

  -- Never notify yourself.
  if v_owner = v_actor then return; end if;

  select coalesce(nullif(trim(display_name), ''), 'Qualcuno')
    into v_name from public.profiles where id = v_actor;
  v_name := coalesce(v_name, 'Qualcuno');

  v_preview := nullif(trim(coalesce(p_preview, '')), '');
  if v_preview is not null and char_length(v_preview) > 140 then
    v_preview := left(v_preview, 140) || '…';
  end if;

  insert into public.notifications (user_id, type, title, body, data)
  values (
    v_owner,
    'jam_comment',
    v_name || ' ha commentato la tua evidenziazione',
    coalesce(v_preview, ''),
    jsonb_build_object(
      'jam_id', v_jam,
      'jam_highlight_id', p_jam_highlight_id,
      'actor_id', v_actor
    )
  );
end;
$$;

comment on function public.notify_jam_highlight_comment(uuid, text) is
  'Creates a jam_comment notification for the sharer of a jam highlight. '
  'Recipient derived from jam_highlights.shared_by; actor is auth.uid(); skips '
  'self. Stores jam_id + jam_highlight_id in data for navigation.';

revoke execute on function public.notify_jam_highlight_comment(uuid, text) from public;
grant  execute on function public.notify_jam_highlight_comment(uuid, text) to authenticated;
notify pgrst, 'reload schema';
