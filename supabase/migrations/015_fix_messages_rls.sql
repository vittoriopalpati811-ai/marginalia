-- ─── 015: Fix recursive RLS on conversation_members ──────────────────────────

-- 1. Fix conv_members_select (remove self-referencing recursion)
DROP POLICY IF EXISTS "conv_members_select" ON public.conversation_members;

CREATE POLICY "conv_members_select" ON public.conversation_members
  FOR SELECT USING (user_id = auth.uid());

-- 2. SECURITY DEFINER function so we can fetch ALL members of a conversation
--    even though users can only SELECT their own member rows.
--    Returns member profiles to callers who ARE members of the conversation.
CREATE OR REPLACE FUNCTION public.get_conversation_member_profiles(
  p_conversation_id UUID
)
RETURNS TABLE(
  id          UUID,
  display_name TEXT,
  avatar_url  TEXT,
  username    TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.display_name, p.avatar_url, p.username
  FROM public.conversation_members cm
  JOIN public.profiles p ON p.id = cm.user_id
  WHERE cm.conversation_id = p_conversation_id
    AND EXISTS (
      SELECT 1 FROM public.conversation_members
      WHERE conversation_id = p_conversation_id
        AND user_id = auth.uid()
    );
$$;

-- Allow any authenticated user to call this function
GRANT EXECUTE ON FUNCTION public.get_conversation_member_profiles(UUID)
  TO authenticated;

-- 3. Ensure profiles are visible to all authenticated users (needed for search)
--    Drop first to avoid "already exists" errors.
DROP POLICY IF EXISTS "profiles_select" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;

CREATE POLICY "profiles_select" ON public.profiles
  FOR SELECT TO authenticated USING (true);

-- 4. Reload schema
NOTIFY pgrst, 'reload schema';
