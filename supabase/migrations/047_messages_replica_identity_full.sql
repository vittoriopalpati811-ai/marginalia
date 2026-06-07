-- 047_messages_replica_identity_full.sql
-- Realtime: allow server-side postgres_changes filters on non-PK columns
-- (e.g. conversation_id) to actually match. Without REPLICA IDENTITY FULL the
-- WAL row image for an INSERT only carries the PK, so a filter on
-- conversation_id silently matches nothing and the open chat never receives
-- live events. The client (1.0.33) already filters in Dart as the primary fix;
-- this makes filtered subscriptions correct going forward. messages are
-- insert-mostly so the extra WAL cost is negligible.
alter table public.messages replica identity full;
notify pgrst, 'reload schema';
