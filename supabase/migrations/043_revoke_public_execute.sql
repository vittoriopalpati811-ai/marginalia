-- 043_revoke_public_execute.sql
--
-- Corrects the 042 hardening. Verification after 042 showed seven SECURITY
-- DEFINER RPCs still answered true to has_function_privilege('anon', ...):
--   create_direct_conversation, create_group_conversation, mark_conversation_read,
--   get_conversation_member_profiles, delete_my_account,
--   infer_reading_sessions_from_highlights, is_jam_member.
--
-- Root cause: anon does NOT hold a *direct* EXECUTE grant on these — it inherits
-- EXECUTE from the implicit grant `CREATE FUNCTION` gives to the PUBLIC role by
-- default. `REVOKE EXECUTE ... FROM anon` (what 042 did) therefore changes
-- nothing: there is no anon grant to revoke, and the PUBLIC path remains. The
-- functions that already showed anon=false (leave_conversation,
-- delete_post_comment_as_owner, public_user_stats) were created by newer
-- migrations that already did `REVOKE ... FROM PUBLIC`.
--
-- The correct lever is `REVOKE EXECUTE ... FROM PUBLIC`, which removes the
-- inherited path for anon (and every other role) — followed by an explicit
-- `GRANT EXECUTE ... TO authenticated` so the signed-in app keeps calling them.
--
-- This is defense-in-depth, NOT a fix for a live hole: every function here is
-- SECURITY DEFINER and already raises / no-ops for an unauthenticated caller
-- (auth.uid() is null). We are only shrinking the callable surface so anon can't
-- reach these RPCs through PostgREST at all.
--
-- Each statement is wrapped in its own DO/EXCEPTION block that swallows
-- undefined_function (SQLSTATE 42883), so a signature that differs in another
-- environment does not abort the whole script.

-- ── The seven that 042 missed: revoke the PUBLIC path, keep authenticated ──────
DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.create_direct_conversation(uuid) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.create_direct_conversation(uuid) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.create_group_conversation(uuid[], text) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.create_group_conversation(uuid[], text) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.mark_conversation_read(uuid) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.get_conversation_member_profiles(uuid) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.get_conversation_member_profiles(uuid) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.infer_reading_sessions_from_highlights() FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.infer_reading_sessions_from_highlights() TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.is_jam_member(uuid) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.is_jam_member(uuid) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- ── Re-assert the same posture on RPCs that were already locked (idempotent) ───
DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.leave_conversation(uuid) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.leave_conversation(uuid) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.notify_post_interaction(uuid, text, text) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION public.notify_post_interaction(uuid, text, text) TO authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

NOTIFY pgrst, 'reload schema';
