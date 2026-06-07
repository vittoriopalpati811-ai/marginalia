-- 048_post_mentions.sql
-- @mention support for posts. Tagged user ids live in posts.mentions (uuid[]),
-- additive + retro-compatible (default '{}'). A SECURITY DEFINER RPC fans out
-- one in-app notification per mentioned user, mirroring notify_post_interaction
-- (server-derived recipients, auth.uid() actor, self-skip, author-only).

alter table public.posts
  add column if not exists mentions uuid[] not null default '{}';

create index if not exists posts_mentions_gin
  on public.posts using gin (mentions);

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
begin
  if v_actor is null then return; end if;
  select user_id, mentions into v_author, v_mentions
    from public.posts where id = p_post_id;
  if v_author is null then return; end if;
  -- only the post's own author may trigger mention notifications for it
  if v_author <> v_actor then return; end if;
  if v_mentions is null then return; end if;

  select coalesce(nullif(trim(display_name), ''), 'Qualcuno') into v_name
    from public.profiles where id = v_actor;
  v_name := coalesce(v_name, 'Qualcuno');

  for v_uid in select distinct x from unnest(v_mentions) as x loop
    if v_uid is null or v_uid = v_actor then continue; end if;
    insert into public.notifications (user_id, type, title, body, data)
    values (
      v_uid,
      'mention',
      v_name || ' ti ha menzionato in un post',
      '',
      jsonb_build_object('post_id', p_post_id, 'actor_id', v_actor)
    );
  end loop;
end;
$$;

revoke execute on function public.notify_post_mentions(uuid) from public;
revoke execute on function public.notify_post_mentions(uuid) from anon;
grant execute on function public.notify_post_mentions(uuid) to authenticated;
notify pgrst, 'reload schema';
