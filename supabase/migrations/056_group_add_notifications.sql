-- 056_group_add_notifications.sql
--
-- create_group_conversation now also drops an in-app notification into each
-- ADDED member's inbox ("X ti ha aggiunto a <group>"). The function body is an
-- EXACT copy of migration 028 (the P0 relationship guard is preserved verbatim)
-- with only two additions:
--   1. resolve the creator's display name (v_my_name);
--   2. insert a 'group_add' notification for every member except the creator.
--
-- SECURITY DEFINER, so the inserts bypass the notifications no-INSERT RLS policy
-- the same way the other notify_* functions do. notifications.data carries the
-- conversation_id + group_name so the client can deep-link to the chat.

create or replace function public.create_group_conversation(
  p_member_ids uuid[],
  p_group_name text
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_my_id   uuid := auth.uid();
  v_conv_id uuid;
  v_uid     uuid;
  v_all_ids uuid[];
  v_name    text := nullif(trim(coalesce(p_group_name, '')), '');
  v_my_name text;
begin
  if v_my_id is null then
    raise exception 'not authenticated';
  end if;
  if v_name is null then
    raise exception 'group_name required';
  end if;
  if array_length(p_member_ids, 1) is null or array_length(p_member_ids, 1) > 100 then
    raise exception 'invalid member list (1-100 members required)';
  end if;

  -- Relationship guard: every proposed member must be someone the creator
  -- mutually follows (i.e. they follow each other) — same trust threshold
  -- as direct DMs. Self is exempt (creator always allowed).
  for v_uid in select unnest(p_member_ids) loop
    if v_uid = v_my_id then continue; end if;
    if not exists (
      select 1 from public.follows f1
      join public.follows f2
        on f2.follower_id = f1.followed_id
       and f2.followed_id = f1.follower_id
      where f1.follower_id = v_my_id and f1.followed_id = v_uid
    ) then
      raise exception 'cannot add user % to group: must mutually follow', v_uid;
    end if;
  end loop;

  v_all_ids := array(
    select distinct unnest(array_append(p_member_ids, v_my_id))
  );

  -- Creator display name for the "added you" notice (fallback "Qualcuno").
  select coalesce(nullif(trim(display_name), ''), 'Qualcuno')
    into v_my_name from public.profiles where id = v_my_id;
  v_my_name := coalesce(v_my_name, 'Qualcuno');

  insert into public.conversations (is_group, group_name, created_by, updated_at)
  values (true, v_name, v_my_id, now())
  returning id into v_conv_id;

  foreach v_uid in array v_all_ids loop
    insert into public.conversation_members (conversation_id, user_id)
    values (v_conv_id, v_uid);

    -- Notify every ADDED member (never the creator) about the new group.
    if v_uid <> v_my_id then
      insert into public.notifications (user_id, type, title, body, data)
      values (
        v_uid,
        'group_add',
        v_my_name || ' ti ha aggiunto a ' || v_name,
        '',
        jsonb_build_object(
          'conversation_id', v_conv_id,
          'group_name', v_name,
          'actor_id', v_my_id
        )
      );
    end if;
  end loop;

  return v_conv_id;
end;
$$;

revoke execute on function public.create_group_conversation(uuid[], text) from public;
grant  execute on function public.create_group_conversation(uuid[], text) to authenticated;
notify pgrst, 'reload schema';
