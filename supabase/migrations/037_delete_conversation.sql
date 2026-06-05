-- ─── 037: Leave / delete a conversation (per-user) ───────────────────────────
--
-- FEATURE: let a user delete a chat from their Messages list. This is a
-- *leave* (remove the caller's own membership), NOT a hard-delete for every
-- participant — the other members keep the conversation. When the LAST member
-- leaves, the now-orphaned conversation row is removed; its messages and any
-- leftover member rows cascade away via the ON DELETE CASCADE FKs defined in
-- migration 014.
--
-- WHY THIS MIGRATION EXISTS:
-- migration 014 enabled RLS on `conversation_members` but only ever created
-- SELECT + INSERT policies — there was never a DELETE policy (the exact same
-- gap migration 030 documented for UPDATE). With RLS fail-closed, a client
-- `delete().eq('user_id', auth.uid())` silently affects ZERO rows. We close
-- the gap two complementary ways, matching patterns already in this codebase:
--
--   1. A DELETE RLS policy (`conv_members_delete`) scoped to the caller's own
--      row — so a direct client delete works and can NEVER remove anyone
--      else's membership. Mirrors follows_delete / post_likes_delete (016).
--
--   2. A SECURITY DEFINER RPC `leave_conversation` — mirrors
--      `mark_conversation_read` (030). The Dart client (deleteConversation in
--      supabase_service.dart) calls this first and falls back to the direct
--      delete if the RPC is absent. The RPC additionally cleans up the
--      conversation row once it has no members left, which a plain client
--      delete cannot do (the caller loses SELECT/visibility on the
--      conversation the instant their membership row is gone).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. DELETE RLS policy: a member may remove only their OWN membership ──────
DROP POLICY IF EXISTS "conv_members_delete" ON public.conversation_members;
CREATE POLICY "conv_members_delete" ON public.conversation_members
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ── 2. SECURITY DEFINER RPC: leave + orphan cleanup ──────────────────────────
CREATE OR REPLACE FUNCTION public.leave_conversation(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid             uuid := auth.uid();
  v_remaining     integer;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- Defensive: only act if the caller is actually a member. Without this a
  -- malicious client could probe arbitrary conversation ids.
  IF NOT EXISTS (
    SELECT 1 FROM public.conversation_members
    WHERE conversation_id = p_conversation_id
      AND user_id = uid
  ) THEN
    RAISE EXCEPTION 'not a member of this conversation';
  END IF;

  -- Remove the caller's membership.
  DELETE FROM public.conversation_members
  WHERE conversation_id = p_conversation_id
    AND user_id = uid;

  -- If nobody is left, delete the conversation itself. Remaining messages and
  -- member rows cascade via the FKs from migration 014.
  SELECT count(*) INTO v_remaining
  FROM public.conversation_members
  WHERE conversation_id = p_conversation_id;

  IF v_remaining = 0 THEN
    DELETE FROM public.conversations
    WHERE id = p_conversation_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_conversation(uuid) TO authenticated;

-- ── 3. Reload PostgREST schema ───────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
