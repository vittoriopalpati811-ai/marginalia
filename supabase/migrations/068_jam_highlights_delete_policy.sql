-- 068_jam_highlights_delete_policy.sql
--
-- jam_highlights carried only INSERT + SELECT RLS policies on the live DB (the
-- original migration-002 "rimozione solo chi ha condiviso" delete policy was
-- dropped at some point and never re-added), so with RLS enabled NOBODY could
-- remove a shared highlight — every delete silently affected 0 rows.
--
-- Add a DELETE policy allowing the user who shared the highlight OR the jam
-- owner (content moderation). This backs the "3 dots -> Remove from jam"
-- affordance added to the jam highlight cards in jam_detail_screen.dart.

drop policy if exists "jam_highlights: rimozione solo chi ha condiviso" on public.jam_highlights;
drop policy if exists jam_highlights_delete on public.jam_highlights;

create policy jam_highlights_delete
  on public.jam_highlights for delete
  using (
    auth.uid() = shared_by
    or jam_id in (select id from public.jams where owner_id = auth.uid())
  );
