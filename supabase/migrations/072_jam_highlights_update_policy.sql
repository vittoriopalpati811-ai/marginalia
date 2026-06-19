-- 072_jam_highlights_update_policy.sql
--
-- Bug (founder, 2026-06-19): replying to a shared citation with a citation in a
-- jam fails with PostgrestException 42501 "new row violates row-level security
-- policy (USING expression) for table jam_highlights".
--
-- Cause: shareHighlightInJam() (supabase_service.dart) upserts onConflict
-- (jam_id, highlight_id). When the highlight is already shared to that jam, the
-- upsert takes the ON CONFLICT DO UPDATE branch — but jam_highlights had only
-- INSERT / SELECT / DELETE policies (no UPDATE), so the UPDATE failed its
-- (missing) USING check. Exact same class of bug as jam_poll_candidates (069).
--
-- Fix: add an UPDATE policy mirroring the live INSERT/DELETE owner logic so the
-- sharer (or the jam owner) can re-share idempotently. Applied live via MCP.
create policy jam_highlights_update on public.jam_highlights
  for update
  using (
    auth.uid() = shared_by
    or jam_id in (select id from public.jams where owner_id = auth.uid())
  )
  with check (
    shared_by = auth.uid()
    and (
      jam_id in (select jam_id from public.jam_members where user_id = auth.uid())
      or jam_id in (select id from public.jams where owner_id = auth.uid())
    )
  );
