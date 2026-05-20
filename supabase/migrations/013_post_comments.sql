-- Marginalia — Migration 013: post_comments table
-- Comments on posts (text + optional image or GIF).

CREATE TABLE IF NOT EXISTS public.post_comments (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID        NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content    TEXT,
  image_url  TEXT,
  gif_url    TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "post_comments_select" ON public.post_comments
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "post_comments_insert" ON public.post_comments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "post_comments_delete" ON public.post_comments
  FOR DELETE USING (auth.uid() = user_id);

-- Index for fast per-post lookup
CREATE INDEX IF NOT EXISTS post_comments_post_id_idx
  ON public.post_comments(post_id, created_at);
