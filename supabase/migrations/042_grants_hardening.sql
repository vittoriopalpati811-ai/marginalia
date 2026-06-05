-- 042_grants_hardening.sql
--
-- Defense-in-depth on the EXECUTE privileges of our SECURITY DEFINER functions.
--
-- The Supabase security advisor flags several SECURITY DEFINER functions as
-- executable by the `anon` role. Every one of them already self-guards with
-- auth.uid() (they no-op / raise for an unauthenticated caller), so this is NOT
-- a live vulnerability — it is hardening: shrink the callable surface so anon
-- can't even reach these RPCs through PostgREST.
--
-- What this migration does:
--   1) USER-ACTION RPCs — REVOKE EXECUTE ... FROM anon (keep `authenticated`,
--      the app calls them while signed in; revoking authenticated would break
--      the app). Re-running is harmless; some of these were already locked down
--      in 036/038 and this re-asserts the same posture.
--   2) PURE TRIGGER functions (handle_new_user, handle_new_jam) — these only
--      ever fire from row triggers, never legitimately via the REST RPC
--      endpoint. REVOKE EXECUTE ... FROM anon, authenticated, public so they
--      are not part of the callable API at all. (034 already revoked anon +
--      authenticated; this adds the explicit `public` revoke too.)
--
-- This migration does NOT touch RLS and does NOT revoke `authenticated` on the
-- user-action RPCs.
--
-- Tolerance: each REVOKE is wrapped in its own DO block that swallows
-- undefined_function (SQLSTATE 42883), so a function that was renamed, never
-- created in this database, or defined by a parallel migration does not abort
-- the whole script. Exact argument signatures are taken from the migrations
-- that defined each function:
--   create_direct_conversation(uuid)            -- 016
--   create_group_conversation(uuid[], text)     -- 016
--   leave_conversation(uuid)                    -- 037
--   mark_conversation_read(uuid)                -- 030
--   notify_post_interaction(uuid, text, text)   -- 036
--   delete_post_comment_as_owner(uuid)          -- 038
--   delete_my_account()                         -- 025 / 029
--   infer_reading_sessions_from_highlights()    -- 031
--   public_user_stats(uuid)                     -- 036
--   is_jam_member(uuid)                         -- 020
--   get_conversation_member_profiles(uuid)      -- 015
--   handle_new_user()  [trigger]                -- 001
--   handle_new_jam()   [trigger]                -- (jam migration / applied live)

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) USER-ACTION RPCs — revoke anon only, keep authenticated.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.create_direct_conversation(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.create_group_conversation(uuid[], text) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.leave_conversation(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.mark_conversation_read(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.notify_post_interaction(uuid, text, text) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.delete_post_comment_as_owner(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.infer_reading_sessions_from_highlights() FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.public_user_stats(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.is_jam_member(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.get_conversation_member_profiles(uuid) FROM anon;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) PURE TRIGGER functions — never callable via RPC. Revoke from everyone.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated, public;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.handle_new_jam() FROM anon, authenticated, public;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Reload the PostgREST schema cache so the tightened grants take effect now.
-- ═══════════════════════════════════════════════════════════════════════════
NOTIFY pgrst, 'reload schema';
