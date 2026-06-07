-- 049_notify_post_mentions_cap.sql
-- Anti-spam hardening for the mention fan-out (security assessment, low sev):
-- cap notifications per post to 20 distinct recipients and rate-limit the
-- action per author, so a crafted client can't flood a victim's notifications
-- by mentioning them across many posts / with a huge mentions[] array.
create or replace function public.notify_post_mentions(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_actor    uuid := auth.uid();
  v_author   uuid;
  v_mentions uuid[];
  v_name     text;
  v_uid      uuid;
  v_count    int := 0;
begin
  if v_actor is null then return; end if;
  select user_id, mentions into v_author, v_mentions
    from public.posts where id = p_post_id;
  if v_author is null then return; end if;
  if v_author <> v_actor then return; end if;       -- author-only
  if v_mentions is null then return; end if;

  -- Best-effort per-author rate limit (no-op if the helper is absent).
  begin
    perform public.check_rate_limit('post_mention', 50, 3600);
  exception
    when undefined_function then null;
  end;

  select coalesce(nullif(trim(display_name), ''), 'Qualcuno') into v_name
    from public.profiles where id = v_actor;
  v_name := coalesce(v_name, 'Qualcuno');

  for v_uid in select distinct x from unnest(v_mentions) as x loop
    if v_uid is null or v_uid = v_actor then continue; end if;
    exit when v_count >= 20;                         -- cap fan-out per post
    insert into public.notifications (user_id, type, title, body, data)
    values (
      v_uid,
      'mention',
      v_name || ' ti ha menzionato in un post',
      '',
      jsonb_build_object('post_id', p_post_id, 'actor_id', v_actor)
    );
    v_count := v_count + 1;
  end loop;
end;
$$;

revoke execute on function public.notify_post_mentions(uuid) from public;
revoke execute on function public.notify_post_mentions(uuid) from anon;
grant execute on function public.notify_post_mentions(uuid) to authenticated;
notify pgrst, 'reload schema';
