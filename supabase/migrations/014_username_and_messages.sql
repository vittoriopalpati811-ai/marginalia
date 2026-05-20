-- ─── 014: Username + Messaging ───────────────────────────────────────────────
-- Run this in the Supabase SQL Editor.

-- ── 1. Username on profiles ───────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username TEXT;

-- Enforce uniqueness (case-insensitive via LOWER index)
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_idx
  ON public.profiles (LOWER(username))
  WHERE username IS NOT NULL;

-- ── 2. Conversations ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversations (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group        BOOLEAN     NOT NULL DEFAULT false,
  group_name      TEXT,
  group_avatar_url TEXT,
  created_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 3. Conversation members ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.conversation_members (
  conversation_id UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_read_at    TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, user_id)
);

-- ── 4. Messages ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.messages (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content         TEXT,
  image_url       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 5. Indexes ────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS conv_members_user_idx
  ON public.conversation_members (user_id);

CREATE INDEX IF NOT EXISTS messages_conv_created_idx
  ON public.messages (conversation_id, created_at);

CREATE INDEX IF NOT EXISTS conversations_updated_idx
  ON public.conversations (updated_at DESC);

-- ── 6. Row Level Security ─────────────────────────────────────────────────────

ALTER TABLE public.conversations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages             ENABLE ROW LEVEL SECURITY;

-- conversations: visible only to members
CREATE POLICY "conversations_select" ON public.conversations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = id AND user_id = auth.uid()
    )
  );

CREATE POLICY "conversations_insert" ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "conversations_update" ON public.conversations
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = id AND user_id = auth.uid()
    )
  );

-- conversation_members: visible to other members of the same conversation
CREATE POLICY "conv_members_select" ON public.conversation_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members AS cm
      WHERE cm.conversation_id = conversation_id AND cm.user_id = auth.uid()
    )
  );

CREATE POLICY "conv_members_insert" ON public.conversation_members
  FOR INSERT WITH CHECK (
    -- creator can add anyone; or a member can add themselves (join)
    auth.uid() = user_id OR
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = conversation_id AND created_by = auth.uid()
    )
  );

-- messages: readable and writable only to conversation members
CREATE POLICY "messages_select" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "messages_insert" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id AND
    EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = messages.conversation_id AND user_id = auth.uid()
    )
  );

-- ── 7. Storage bucket for message images ──────────────────────────────────────

INSERT INTO storage.buckets (id, name, public)
VALUES ('message-images', 'message-images', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "message_images_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'message-images' AND auth.role() = 'authenticated'
  );

CREATE POLICY "message_images_select" ON storage.objects
  FOR SELECT USING (bucket_id = 'message-images');

-- ── 8. Notify PostgREST to reload schema ──────────────────────────────────────

NOTIFY pgrst, 'reload schema';
