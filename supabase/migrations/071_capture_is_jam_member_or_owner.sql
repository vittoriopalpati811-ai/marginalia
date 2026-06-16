-- 071_capture_is_jam_member_or_owner.sql
--
-- Migration-drift fix (surfaced by the 2026-06-17 security audit).
--
-- is_jam_member_or_owner() is referenced 11x across migrations 062/063/066 in
-- critical RLS policies + RPCs (jam-covers storage INSERT/UPDATE/DELETE/SELECT,
-- jam_ripasso_results / jam_quiz_results policies, the jam_ripasso_leaderboard
-- RPC, and set_jam_cover) — but the function itself was only ever created
-- directly on the live DB and was NEVER captured in a migration file. A clean
-- rebuild from migrations alone would therefore fail with undefined_function and
-- break jam-cover uploads + the Ripasso 2.0 leaderboard.
--
-- This captures the exact live definition. It is an idempotent CREATE OR REPLACE
-- (identical to what already runs in production, verified via pg_get_functiondef),
-- so applying it is a no-op on the live DB and makes a from-scratch rebuild work.
--
-- Mirrors is_jam_member (migration 020) but also grants the jam owner.

create or replace function public.is_jam_member_or_owner(p_jam uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select exists (select 1 from public.jam_members m where m.jam_id = p_jam and m.user_id = auth.uid())
      or exists (select 1 from public.jams j where j.id = p_jam and j.owner_id = auth.uid());
$function$;
