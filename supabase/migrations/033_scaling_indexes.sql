-- 033_scaling_indexes.sql
--
-- Database scaling hygiene (the "5 DB mistakes" that break an app at ~1000
-- users: missing indexes → full table scans; index bloat → slow writes).
-- Applied to the live project via the Supabase MCP; committed here for record.
--
-- 1) Add a covering index for every foreign-key column in `public` that lacked
--    one. These are the columns joined/filtered as the social graph grows
--    (feeds, jams, comments, messages, notifications).
CREATE INDEX IF NOT EXISTS idx_conversations_created_by  ON public.conversations(created_by);
CREATE INDEX IF NOT EXISTS idx_jam_challenges_created_by ON public.jam_challenges(created_by);
CREATE INDEX IF NOT EXISTS idx_jam_hl_comments_user      ON public.jam_highlight_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_jam_hl_polls_winner       ON public.jam_highlight_polls(winner_id);
CREATE INDEX IF NOT EXISTS idx_jam_hl_polls_created_by   ON public.jam_highlight_polls(created_by);
CREATE INDEX IF NOT EXISTS idx_jam_highlights_shared_by  ON public.jam_highlights(shared_by);
CREATE INDEX IF NOT EXISTS idx_messages_sender           ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_notifications_jam         ON public.notifications(jam_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_user        ON public.post_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_jam                 ON public.posts(jam_id);
CREATE INDEX IF NOT EXISTS idx_posts_highlight           ON public.posts(highlight_id);

-- 2) Drop exact-duplicate indexes (same table, columns, order, type). They cost
--    write throughput and storage for no read benefit; each surviving twin has
--    an identical definition.
DROP INDEX IF EXISTS public.idx_books_user;            -- == books_user_id_idx (user_id)
DROP INDEX IF EXISTS public.idx_highlights_user;       -- == highlights_user_id_idx (user_id)
DROP INDEX IF EXISTS public.idx_highlights_book;       -- == highlights_book_id_idx (book_id)
DROP INDEX IF EXISTS public.jam_highlights_jam_id_idx; -- == idx_jam_highlights_jam (jam_id)
DROP INDEX IF EXISTS public.posts_user_created_idx;    -- == posts_user_created (user_id, created_at DESC)
DROP INDEX IF EXISTS public.post_comments_post_idx;    -- == post_comments_post_id_idx (post_id, created_at)
