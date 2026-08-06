-- ─── Close the door 078 left open ───────────────────────────────────────────
--
-- Migration 078 gave `user_shelf_layout` a read policy of `using (true)` on the
-- reasoning that an arrangement is meant to be seen. That was wrong, and wrong
-- in a way the same migration should have caught: `manual_order` is not an
-- opaque preference. It is the reader's ENTIRE book list, as 'title|author'
-- keys — the client writes every book, whatever sort mode is active, so that
-- switching to a filter and back does not throw a hand arrangement away.
--
-- So an unfiltered `GET /rest/v1/user_shelf_layout` handed any signed-in caller
-- every user's whole library, including accounts marked private, whose books
-- `public_user_shelf` in the very same migration deliberately withholds. The
-- boundary was built carefully in one object and left open in the one beside it
-- — the same class of mistake as the migration-074 IDOR, one table over.
--
-- Verified live before and after: with the owner set private, a stranger's
-- unfiltered select returned 43 keys before this and 0 after, while the owner
-- still reads their own row and public profiles stay visible.
drop policy if exists user_shelf_layout_read on public.user_shelf_layout;
create policy user_shelf_layout_read on public.user_shelf_layout
  for select to authenticated using (
    user_id = auth.uid()
    or coalesce((select p.is_private from public.profiles p where p.id = user_id), false) = false
    or exists (
      select 1 from public.follows f
      where f.follower_id = auth.uid() and f.following_id = user_id
    )
  );

-- ── "Recent" has to have something to be recent BY ──────────────────────────
--
-- The arrange sheet offers a "Recenti"/"Recent" filter, and it was a no-op: both
-- book queries ordered by title, and the sort mode is deliberately the identity
-- (it means "the order the rows arrived in"), so picking it silently gave
-- alphabetical — a filter that lies about what it does.
--
-- `books.imported_at` already exists. Ordering the source by it makes the mode
-- real without adding a field to the shelf entry, and costs the other modes
-- nothing: they all re-sort in Dart anyway.
create or replace function public.public_user_shelf(target_id uuid)
returns table (title text, author text, cover_url text, highlight_count int)
language sql
security definer
set search_path to 'public', 'pg_catalog'
as $$
  select b.title,
         b.author,
         b.cover_url,
         (select count(*)::int from public.highlights h where h.book_id = b.id)
  from public.books b
  where b.user_id = target_id
    and (
      target_id = auth.uid()
      or coalesce((select p.is_private from public.profiles p where p.id = target_id), false) = false
      or exists (
        select 1 from public.follows f
        where f.follower_id = auth.uid() and f.following_id = target_id
      )
    )
  order by b.imported_at desc nulls last, b.title;
$$;

revoke execute on function public.public_user_shelf(uuid) from public;
revoke execute on function public.public_user_shelf(uuid) from anon;
grant  execute on function public.public_user_shelf(uuid) to authenticated;
