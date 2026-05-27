-- ─── Security hardening (audit 2026-05-27) ─────────────────────────────────
--
-- Findings:
--
-- [P0] create_notification: SECURITY DEFINER with no caller check + no
--      explicit search_path. Any authenticated user can spam any other user's
--      notification feed with arbitrary title/body — phishing vector.
--      FIX: lock down EXECUTE to internal roles, set search_path explicitly.
--
-- [P0] create_group_conversation: lets the creator add ARBITRARY users to a
--      conversation without their consent (no follow/relationship check).
--      Abuse vector for unsolicited DMs / spam.
--      FIX: require that the creator already has a relationship (mutual
--      follow OR existing direct DM) with every member.
--
-- [P1] books_finished_v: view lacked explicit security_invoker. Supabase
--      advisor flags any view without security_invoker=true as a definer-
--      style view. Make it explicit.
--
-- [P1] Dead tables (clippings_imports, tags, highlight_tags) have RLS on
--      but zero policies → fully locked. Either drop or grant minimal
--      access. Leaving them in place is fine but document the intent.

-- ─── P0 — create_notification: lock down + set search_path ─────────────────
create or replace function public.create_notification(
  p_user_id uuid,
  p_type    text,
  p_title   text,
  p_body    text,
  p_data    jsonb default null,
  p_jam_id  uuid  default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_id uuid;
begin
  -- Hard guard: only allow the database to call this (triggers, RPCs we
  -- mark as definer too). Direct calls from authenticated end users are
  -- a phishing vector. service_role still works because it bypasses RLS;
  -- triggers call as the table owner. Block 'authenticated' explicitly.
  if current_user = 'authenticated' or current_user = 'anon' then
    raise exception 'create_notification cannot be called directly from client';
  end if;

  insert into public.notifications (user_id, type, title, body, data, jam_id)
  values (p_user_id, p_type, p_title, p_body, p_data, p_jam_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- Revoke direct execute from PUBLIC (which anon/authenticated inherit).
-- The function is still callable from triggers / other definer functions
-- (which run as the table owner, typically postgres).
revoke execute on function public.create_notification(uuid, text, text, text, jsonb, uuid) from public;
revoke execute on function public.create_notification(uuid, text, text, text, jsonb, uuid) from anon, authenticated;

-- ─── P0 — create_group_conversation: relationship guard ────────────────────
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

  insert into public.conversations (is_group, group_name, created_by, updated_at)
  values (true, v_name, v_my_id, now())
  returning id into v_conv_id;

  foreach v_uid in array v_all_ids loop
    insert into public.conversation_members (conversation_id, user_id)
    values (v_conv_id, v_uid);
  end loop;

  return v_conv_id;
end;
$$;

-- ─── P1 — view: explicit security_invoker = true ──────────────────────────
alter view public.books_finished_v set (security_invoker = true);

-- ─── P1 — Add length caps via CHECK constraints to user-input columns ──────
-- These prevent storage-abuse / spam by limiting how large user-controlled
-- text fields can grow. Caps are generous so they don't restrict legitimate
-- use, but reject anything pathological.

do $$
begin
  if not exists (select 1 from pg_constraint where conname='posts_body_len_chk') then
    alter table public.posts
      add constraint posts_body_len_chk check (body is null or char_length(body) <= 4000);
  end if;
  if not exists (select 1 from pg_constraint where conname='comments_len_chk') then
    alter table public.post_comments
      add constraint comments_len_chk check (content is null or char_length(content) <= 2000);
  end if;
  if not exists (select 1 from pg_constraint where conname='book_notes_len_chk') then
    alter table public.book_notes
      add constraint book_notes_len_chk check (char_length(notes) <= 10000);
  end if;
  if not exists (select 1 from pg_constraint where conname='msg_content_len_chk') then
    alter table public.messages
      add constraint msg_content_len_chk check (content is null or char_length(content) <= 4000);
  end if;
end $$;
