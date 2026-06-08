-- 052_conversation_members_realtime.sql
--
-- Make the conversation LIST reactive to read-state.
--
-- Bug: opening a chat marks it read (conversation_members.last_read_at advances),
-- but the inbox list kept showing the conversation BOLD/unread until a manual
-- pull-to-refresh or app-resume. Root cause: conversation_members was never in
-- the `supabase_realtime` publication (migration 017 only added `messages` and
-- `conversations`), so no realtime event was ever emitted when last_read_at
-- changed — the list had no way to learn the conversation had been read.
--
-- Fix: publish conversation_members on realtime so the client can subscribe to
-- UPDATEs of the user's OWN member row and refetch the inbox the instant the
-- server commits last_read_at (covering reads made on another device too).
--
-- REPLICA IDENTITY FULL is required for the SAME reason as migration 047 on
-- `messages`: without the full row image, a realtime server-side filter on
-- `user_id` silently matches nothing and the UPDATE events never arrive.
--
-- Security: realtime respects RLS. The conversation_members SELECT policy only
-- exposes the caller's own membership rows, so a client receives UPDATE events
-- for ITS OWN last_read_at only — never another user's read receipts.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_members'
  ) then
    alter publication supabase_realtime add table public.conversation_members;
  end if;
end $$;

alter table public.conversation_members replica identity full;

notify pgrst, 'reload schema';
