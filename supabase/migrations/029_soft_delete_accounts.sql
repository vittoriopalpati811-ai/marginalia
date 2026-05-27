-- ─── Soft-delete + anonymize accounts ───────────────────────────────────────
--
-- Before this migration: delete_my_account() removed auth.users, which
-- cascaded everything (highlights, books, posts, comments, messages,
-- follows, jam memberships). The chat threads the deleted user had
-- participated in lost their entire history — anyone they'd messaged
-- saw an empty conversation.
--
-- New policy:
--   • In CHATS, the deleted person's messages stay visible; the sender
--     just reads as "Account eliminato" instead of their old name.
--   • EVERYWHERE ELSE (search, feed, follows, jams, profile pages) the
--     deleted account vanishes entirely — not findable, not visible.
--
-- We achieve this by detaching the profiles.id → auth.users FK so the
-- profile row can survive after auth.users is deleted, and by marking
-- the surviving row with deleted_at + nulling out the PII.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Add deleted_at column + partial index for "live profile" lookups.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.profiles
  add column if not exists deleted_at timestamptz;

-- Partial index: feed/search/follows queries filter on `deleted_at IS NULL`,
-- so a partial index keeps lookups O(log n) without bloating the index with
-- tombstones.
create index if not exists profiles_alive_idx
  on public.profiles(id)
  where deleted_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Decouple profiles from auth.users.
--
-- Currently `profiles.id` is `references auth.users on delete cascade`.
-- We drop the FK so deleting the auth row leaves an anonymized profile
-- behind for chats to reference. The PK constraint stays; `id` is still
-- a unique UUID, it just no longer has to match an existing auth row.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.profiles
  drop constraint if exists profiles_id_fkey;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Replace the RPC.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- a) Anonymize the profile in place. The row survives so messages,
  --    comments and posts can still resolve `sender_id` / `user_id`
  --    to a profile (display_name = null → app shows "Account eliminato").
  --    Note: `username` is a NOT NULL UNIQUE column in the original schema,
  --    so we substitute an internal tombstone value rather than nulling it.
  update public.profiles set
    username     = 'deleted_' || substr(id::text, 1, 8),
    display_name = null,
    avatar_url   = null,
    deleted_at   = now()
  where id = uid;

  -- The schema also added bio/cover_url/currently_reading_*/favorite_book_ids/
  -- pinned_post_ids in later migrations. Null them defensively if they exist.
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
    when undefined_column then null;   -- older schema → just skip
  end;

  -- b) Wipe the user's *private* data. None of this is visible to others
  --    after deletion anyway, and keeping it would just waste storage.
  delete from public.highlights         where user_id     = uid;
  delete from public.books              where user_id     = uid;

  -- Best-effort cleanup of tables added in later migrations.
  begin delete from public.tags                 where user_id = uid; exception when undefined_table then null; end;
  begin delete from public.clippings_imports    where user_id = uid; exception when undefined_table then null; end;
  begin delete from public.reading_goals        where user_id = uid; exception when undefined_table then null; end;
  begin delete from public.reading_sessions     where user_id = uid; exception when undefined_table then null; end;
  begin delete from public.book_notes           where user_id = uid; exception when undefined_table then null; end;
  begin delete from public.notifications        where recipient_id = uid or actor_id = uid; exception when undefined_table then null; end;
  begin delete from public.jam_members          where user_id = uid; exception when undefined_table then null; end;

  -- c) Remove follow relationships both directions so the deleted person
  --    doesn't appear in anyone's followers/following list.
  begin
    delete from public.follows where follower_id = uid or followee_id = uid;
  exception when undefined_table then null;
  end;

  -- d) Finally drop the auth row. Because we removed the FK on profiles.id,
  --    the soft-deleted profile is NOT cascade-deleted — chats keep history.
  delete from auth.users where id = uid;
end;
$$;

-- Make sure the RPC is callable by authenticated users.
grant execute on function public.delete_my_account() to authenticated;
