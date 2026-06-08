-- 057_fix_create_group_conversation_follows_column.sql
--
-- BUG FIX (pre-existing, latent since migration 028). The mutual-follow
-- relationship guard inside create_group_conversation referenced
-- public.follows.followed_id — a column that DOES NOT EXIST. The follows table's
-- columns are (follower_id, following_id, created_at). Postgres plpgsql does not
-- validate column references until the statement runs, so this only failed at
-- call time: creating a group with at least one OTHER member raised
--   column f1.followed_id does not exist
-- and the whole RPC aborted → group chat creation was broken for real groups.
--
-- Migration 056 (group-add notifications) inherited the same broken guard by
-- re-creating the function from 028's body. This migration re-creates the
-- function identically EXCEPT the guard now uses the real `following_id` column.
-- Mutual follow = (me → them) AND (them → me). Verified against live data: the
-- corrected join matches an existing mutual-follow pair.

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

  -- Relationship guard: every proposed member must MUTUALLY follow the creator
  -- (me → them AND them → me). Uses the real `following_id` column. Self exempt.
  for v_uid in select unnest(p_member_ids) loop
    if v_uid = v_my_id then continue; end if;
    if not exists (
      select 1
      from public.follows f1
      join public.follows f2
        on f2.follower_id  = f1.following_id
       and f2.following_id = f1.follower_id
      where f1.follower_id = v_my_id and f1.following_id = v_uid
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
