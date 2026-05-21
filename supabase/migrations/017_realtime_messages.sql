-- ─── 017: Enable Realtime on messages table ───────────────────────────────────
-- Allows clients to receive live INSERT events on the messages table.
-- Required for the in-app chat to deliver messages without manual refresh.

-- Add messages to the Supabase Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

-- Also add conversations so the list screen can refresh when updated_at changes
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;

NOTIFY pgrst, 'reload schema';
