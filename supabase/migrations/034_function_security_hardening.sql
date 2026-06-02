-- 034_function_security_hardening.sql
--
-- Security-advisor hardening (applied live via the Supabase MCP; committed here
-- for record). Taken with judgement — the user-facing RPCs (create_*_conversation,
-- delete_my_account for signed-in users, mark_conversation_read, …) stay callable
-- by authenticated users; only the genuinely unsafe surface is closed.

-- 1) Pin search_path on SECURITY DEFINER / trigger functions so a caller's
--    session search_path can't redirect unqualified name resolution. These
--    reference public tables, so keep public on the (now fixed) path.
ALTER FUNCTION public.handle_new_user()     SET search_path = public, pg_catalog;
ALTER FUNCTION public.handle_new_jam()      SET search_path = public, pg_catalog;
ALTER FUNCTION public.set_jam_invite_code() SET search_path = public, pg_catalog;
ALTER FUNCTION public.is_jam_member(uuid)   SET search_path = public, pg_catalog;

-- 2) These three are TRIGGER functions — they fire from the database, never
--    legitimately via the REST RPC endpoint. Remove them from the callable API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user()     FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_jam()      FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_jam_invite_code() FROM anon, authenticated;

-- 3) Account deletion must require a signed-in user; never the anon role.
REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM anon;
