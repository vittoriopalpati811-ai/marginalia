-- 074 — Close an unauthenticated IDOR on match_highlights (P0 data exposure).
--
-- match_highlights(p_user_id, p_query_embedding, p_match_count) is SECURITY
-- DEFINER (so it bypasses the RLS on `highlights`) and filters by the
-- CALLER-SUPPLIED `p_user_id` with no `auth.uid()` check. It was also granted
-- EXECUTE to `anon`, so it was reachable directly via
--   POST /rest/v1/rpc/match_highlights
-- with nothing but the public anon key (which ships in the app binary) and a
-- target user's UUID (trivially obtained — profiles are world-readable, and
-- UUIDs appear on posts/follows/jam members). That let ANY unauthenticated
-- caller read ANY user's private highlight text, 50 rows per call. Verified
-- live before this fix.
--
-- The ONLY legitimate caller is the `semantic-search` edge function, which runs
-- with the SERVICE_ROLE key and passes p_user_id = the VERIFIED caller id. So
-- the fix is to remove the client-reachable grants and keep service_role only.
-- The search feature is unaffected (service_role retains EXECUTE).

revoke execute on function public.match_highlights(uuid, public.vector, integer) from anon;
revoke execute on function public.match_highlights(uuid, public.vector, integer) from authenticated;
revoke execute on function public.match_highlights(uuid, public.vector, integer) from public;

-- Keep the sole legitimate caller working (semantic-search uses SERVICE_ROLE).
grant execute on function public.match_highlights(uuid, public.vector, integer) to service_role;
