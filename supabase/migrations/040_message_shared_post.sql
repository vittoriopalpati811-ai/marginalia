-- 040_message_shared_post.sql
--
-- Adds an optional reference from a chat message to a shared post, so a post
-- can be sent into a direct or group conversation and rendered as a tappable
-- card that opens /post/:id. The column is nullable and ON DELETE SET NULL so
-- deleting a post never removes the message — the card simply stops resolving.
--
-- Backwards-compatible: existing messages keep NULL, and all current
-- message-send paths are unaffected.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS shared_post_id uuid
    REFERENCES public.posts(id) ON DELETE SET NULL;

-- Tell PostgREST to reload its schema cache so the new column is queryable
-- (select/insert) immediately without a restart.
NOTIFY pgrst, 'reload schema';
