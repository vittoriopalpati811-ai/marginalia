-- delete_my_account had wrong column names that aborted the whole deletion:
--   notifications.recipient_id / actor_id  -> the table only has user_id
--   follows.followee_id                    -> the column is following_id
-- The best-effort blocks caught only `undefined_table`, NOT `undefined_column`,
-- so the wrong-column errors propagated and the account delete FAILED with
-- 42703 (column does not exist). Fix the names + broaden the handlers to also
-- swallow undefined_column so a future rename can never abort the deletion.
-- Applied live 2026-06-11.
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- a) Anonymize the profile in place (kept so messages/comments still resolve).
  update public.profiles set
    username     = 'deleted_' || substr(id::text, 1, 8),
    display_name = null,
    avatar_url   = null,
    deleted_at   = now()
  where id = uid;

  begin
    update public.profiles set
      bio                      = null,
      cover_url                = null,
      currently_reading_title  = null,
      currently_reading_author = null,
      favorite_book_ids        = '{}',
      pinned_post_ids          = '{}'
    where id = uid;
  exception
    when undefined_column then null;
  end;

  -- b) Wipe the user's private data.
  delete from public.highlights where user_id = uid;
  delete from public.books      where user_id = uid;

  -- Best-effort cleanup of optional tables (swallow missing table OR column).
  begin delete from public.tags              where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.clippings_imports where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.reading_goals     where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.reading_sessions  where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.book_notes        where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.notifications     where user_id = uid; exception when undefined_table or undefined_column then null; end;
  begin delete from public.jam_members       where user_id = uid; exception when undefined_table or undefined_column then null; end;

  -- c) Remove follow relationships both directions.
  begin
    delete from public.follows where follower_id = uid or following_id = uid;
  exception when undefined_table or undefined_column then null;
  end;

  -- d) Drop the auth row.
  delete from auth.users where id = uid;
end;
$function$;
