-- 061_post_likes_count_trigger.sql
-- Fix: the like counter stayed at 0 even after real likes landed.
--
-- posts.likes_count is denormalized, but nothing maintained it server-side:
-- there is no trigger on post_likes, and the posts UPDATE RLS policy is
-- owner-only, so any client-side "bump the counter" write coming from the
-- LIKER (not the post owner) was silently rejected by RLS (0 rows updated).
-- Live state at fix time: 226 rows in post_likes across 93 posts, counter
-- stuck at 0 on most of them.
--
-- Maintain the counter with a SECURITY DEFINER trigger on post_likes (runs as
-- the function owner, so the owner-only posts policy doesn't apply), and
-- backfill from the existing rows. Also add posts.hide_like_count: the author
-- can hide the like COUNT from everyone else (the author keeps seeing it; the
-- heart still works for everyone).

create or replace function public.sync_post_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
      set likes_count = coalesce(likes_count, 0) + 1
      where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts
      set likes_count = greatest(coalesce(likes_count, 0) - 1, 0)
      where id = old.post_id;
    return old;
  end if;
  return null;
end;
$$;

-- Trigger dispatch does not need EXECUTE; nobody should call this directly.
revoke execute on function public.sync_post_likes_count() from public, anon, authenticated;

drop trigger if exists trg_sync_post_likes_count on public.post_likes;
create trigger trg_sync_post_likes_count
  after insert or delete on public.post_likes
  for each row execute function public.sync_post_likes_count();

-- Backfill: align likes_count with the rows that actually exist.
update public.posts p
set likes_count = c.cnt
from (
  select post_id, count(*)::int as cnt
  from public.post_likes
  group by post_id
) c
where p.id = c.post_id
  and p.likes_count is distinct from c.cnt;

update public.posts p
set likes_count = 0
where p.likes_count is distinct from 0
  and not exists (select 1 from public.post_likes l where l.post_id = p.id);

-- Author-controlled visibility of the like count (count only, not the heart).
alter table public.posts
  add column if not exists hide_like_count boolean not null default false;
