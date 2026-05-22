-- ─── 018: Comment likes + reply threading + comment-images policy fix ─────────

-- 1. Reply threading: self-referential parent_comment_id on post_comments ──────
ALTER TABLE public.post_comments
  ADD COLUMN IF NOT EXISTS parent_comment_id UUID
    REFERENCES public.post_comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS post_comments_parent_id_idx
  ON public.post_comments(parent_comment_id);

-- 2. Comment likes ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.comment_likes (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id UUID        NOT NULL REFERENCES public.post_comments(id) ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(comment_id, user_id)
);

ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comment_likes_select" ON public.comment_likes
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "comment_likes_insert" ON public.comment_likes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "comment_likes_delete" ON public.comment_likes
  FOR DELETE USING (auth.uid() = user_id);

-- 3. Fix comment-images storage bucket (idempotent) ───────────────────────────
-- Ensure bucket exists and is public.
INSERT INTO storage.buckets (id, name, public)
VALUES ('comment-images', 'comment-images', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Re-assert SELECT policy so any authenticated or anonymous user can read.
DROP POLICY IF EXISTS "Comment image public read" ON storage.objects;
CREATE POLICY "Comment image public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'comment-images');

DROP POLICY IF EXISTS "Comment image auth upload" ON storage.objects;
CREATE POLICY "Comment image auth upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'comment-images'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

DROP POLICY IF EXISTS "Comment image auth update" ON storage.objects;
CREATE POLICY "Comment image auth update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'comment-images'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

DROP POLICY IF EXISTS "Comment image owner delete" ON storage.objects;
CREATE POLICY "Comment image owner delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'comment-images'
    AND auth.uid()::text = split_part(name, '/', 1)
  );

NOTIFY pgrst, 'reload schema';
