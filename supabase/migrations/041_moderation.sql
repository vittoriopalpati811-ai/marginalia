-- 041_moderation.sql
--
-- USER BLOCKING + CONTENT REPORTING — App Store Review Guideline 1.2 (UGC).
--
-- Guideline 1.2 requires any app with user-generated content to provide:
--   • a way for users to BLOCK abusive users, and
--   • a way to REPORT (flag) objectionable content.
-- This migration adds the backend for both: two tables (blocked_users,
-- content_reports) with fail-closed RLS, plus three SECURITY DEFINER RPCs
-- (report_content, block_user, unblock_user). The Flutter service
-- (lib/core/services/supabase_service.dart) calls these RPCs and reads
-- blocked_users to filter feeds/conversations client-side.
--
-- ⚠️ DO NOT APPLY BLINDLY FROM A MIGRATION RUNNER — the parent applies this via
-- the Supabase MCP / SQL Editor. It is written to be idempotent
-- (create table if not exists / create or replace / drop policy if exists /
-- guarded grants) so re-running is safe. It adds ONLY new objects and NO policy
-- that loosens access to any existing table.
--
-- Conventions mirrored from migrations 034/038/039:
--   • SECURITY DEFINER + `set search_path = public, pg_catalog`.
--   • Caller identity is always auth.uid() server-side (never trusted from args).
--   • Functions revoked from public/anon, granted to authenticated only.
--   • notify pgrst at the end to refresh the REST schema cache.

-- ════════════════════════════════════════════════════════════════════════════
-- 1. blocked_users — each row is "blocker blocks blocked"
-- ════════════════════════════════════════════════════════════════════════════
-- Composite PK (blocker_id, blocked_id) makes a block idempotent: re-blocking
-- the same user is a no-op conflict, not a duplicate row. Both FKs cascade on
-- account deletion so a deleted user leaves no dangling block rows.

create table if not exists public.blocked_users (
  blocker_id uuid        not null references auth.users(id) on delete cascade,
  blocked_id uuid        not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- Hot path: "is X in my block list?" / "list everyone I blocked" (filter feeds).
create index if not exists blocked_users_blocker_idx
  on public.blocked_users (blocker_id);
-- Reverse lookup: "who blocked me?" (e.g. future server-side feed exclusion).
create index if not exists blocked_users_blocked_idx
  on public.blocked_users (blocked_id);

-- RLS: a user may only ever see and manage THEIR OWN block list. They can read,
-- create, and remove rows where they are the blocker; they can never read whom
-- someone else has blocked, nor block on behalf of another user. Fail-closed:
-- no UPDATE policy (a block has nothing to update — you block or you unblock).
alter table public.blocked_users enable row level security;

drop policy if exists blocked_users_select_own on public.blocked_users;
create policy blocked_users_select_own on public.blocked_users
  for select using (auth.uid() = blocker_id);

drop policy if exists blocked_users_insert_own on public.blocked_users;
create policy blocked_users_insert_own on public.blocked_users
  for insert with check (auth.uid() = blocker_id);

drop policy if exists blocked_users_delete_own on public.blocked_users;
create policy blocked_users_delete_own on public.blocked_users
  for delete using (auth.uid() = blocker_id);

-- ════════════════════════════════════════════════════════════════════════════
-- 2. content_reports — user flags of objectionable content
-- ════════════════════════════════════════════════════════════════════════════
-- One row per report. content_id is TEXT (not uuid) because the reportable
-- surfaces use heterogeneous id types/sources and a profile/user "id" target is
-- also stored here; keeping it text avoids cast failures across content types.
-- status defaults to 'open' for the moderation queue (reviewed out-of-band).

create table if not exists public.content_reports (
  id               uuid        primary key default gen_random_uuid(),
  reporter_id      uuid        not null references auth.users(id) on delete cascade,
  content_type     text        not null check (content_type in
                                 ('post','comment','message','profile','review','jam')),
  content_id       text,
  reported_user_id uuid        references auth.users(id) on delete set null,
  reason           text,
  details          text,
  status           text        not null default 'open',
  created_at       timestamptz not null default now()
);

-- Moderation queue scans by status; abuse triage groups by the reported user.
create index if not exists content_reports_status_idx
  on public.content_reports (status);
create index if not exists content_reports_reported_user_idx
  on public.content_reports (reported_user_id);

-- RLS: NO public read. A reporter may INSERT a report as themselves and may read
-- back ONLY their own reports (so the UI can confirm "report submitted" without
-- exposing the global moderation queue or who-reported-whom to other users).
-- Reviewing/closing reports happens server-side (service role / SQL editor),
-- which bypasses RLS — so we deliberately add NO update/delete policy here.
alter table public.content_reports enable row level security;

drop policy if exists content_reports_insert_self on public.content_reports;
create policy content_reports_insert_self on public.content_reports
  for insert to authenticated
  with check (auth.uid() = reporter_id);

drop policy if exists content_reports_select_own on public.content_reports;
create policy content_reports_select_own on public.content_reports
  for select to authenticated
  using (auth.uid() = reporter_id);

-- ════════════════════════════════════════════════════════════════════════════
-- 3. report_content(...) — insert a report for the caller (rate-limited)
-- ════════════════════════════════════════════════════════════════════════════
-- The reporter is ALWAYS auth.uid() (never trusted from an argument), so a
-- client cannot forge reports as another user. Rate-limited to 20/day via the
-- existing check_rate_limit('report', 20, 86400) helper (migration 039) so a
-- single account can't flood the moderation queue. The rate-limit call is
-- wrapped defensively: if the helper is somehow absent (undefined_function),
-- reporting still works — we never want an App-Store-required safety feature to
-- hard-fail because an optional limiter isn't deployed. A genuine
-- rate-limit-exceeded error (raised by the helper, sqlstate P0001) is
-- re-raised so the caller sees "slow down".
create or replace function public.report_content(
  p_content_type     text,
  p_content_id       text,
  p_reported_user_id uuid,
  p_reason           text,
  p_details          text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Validate the content type up front (mirrors the table CHECK) so a bad value
  -- fails with a clear message instead of a constraint violation.
  if p_content_type is null or p_content_type not in
       ('post','comment','message','profile','review','jam') then
    raise exception 'Invalid content_type: %', p_content_type using errcode = 'P0001';
  end if;

  -- Anti-abuse: cap reports per user per day. Re-raise a real rate-limit hit;
  -- tolerate the limiter being missing (don't block a Guideline-1.2 feature).
  begin
    perform public.check_rate_limit('report', 20, 86400);
  exception
    when undefined_function then
      null;  -- limiter not deployed → allow the report through
    when sqlstate 'P0001' then
      raise;  -- genuine "rate limit exceeded" → surface to the caller
  end;

  insert into public.content_reports
    (reporter_id, content_type, content_id, reported_user_id, reason, details)
  values
    (v_uid, p_content_type, p_content_id, p_reported_user_id,
     nullif(btrim(coalesce(p_reason, '')), ''),
     nullif(btrim(coalesce(p_details, '')), ''))
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.report_content(text, text, uuid, text, text) is
  'Inserts a content_reports row for the caller (reporter = auth.uid()). '
  'Rate-limited to 20/day via check_rate_limit. Used by '
  'SupabaseService.reportContent for App Store Guideline 1.2 content flagging.';

revoke all     on function public.report_content(text, text, uuid, text, text) from public;
revoke all     on function public.report_content(text, text, uuid, text, text) from anon;
grant  execute on function public.report_content(text, text, uuid, text, text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4. block_user(p_blocked_id) — block + sever follows in BOTH directions
-- ════════════════════════════════════════════════════════════════════════════
-- Upserts the (caller, target) block row (idempotent — never errors if already
-- blocked), then removes any follow edge in EITHER direction so a blocked user
-- immediately stops following you and you stop following them. Guards against
-- self-blocking. Runs as definer so it can delete from follows regardless of
-- which side of the edge the caller is on (the follows DELETE policy only
-- allows deleting rows where you are the follower; blocking must also drop the
-- edge where the OTHER user follows you).
create or replace function public.block_user(
  p_blocked_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_blocked_id is null or p_blocked_id = v_uid then
    raise exception 'You cannot block yourself.' using errcode = 'P0001';
  end if;

  -- Idempotent block: no error if the row already exists.
  insert into public.blocked_users (blocker_id, blocked_id)
  values (v_uid, p_blocked_id)
  on conflict (blocker_id, blocked_id) do nothing;

  -- Sever the relationship both ways so neither user keeps following the other.
  delete from public.follows
   where (follower_id = v_uid          and following_id = p_blocked_id)
      or (follower_id = p_blocked_id   and following_id = v_uid);
end;
$$;

comment on function public.block_user(uuid) is
  'Blocks p_blocked_id for the caller (auth.uid()) idempotently and removes any '
  'follow edge in both directions. Guards against self-block. Backs '
  'SupabaseService.blockUser (App Store Guideline 1.2).';

revoke all     on function public.block_user(uuid) from public;
revoke all     on function public.block_user(uuid) from anon;
grant  execute on function public.block_user(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5. unblock_user(p_blocked_id) — remove the block row
-- ════════════════════════════════════════════════════════════════════════════
-- Deletes the (caller, target) block row. Idempotent: deleting a non-existent
-- block is a silent no-op. Does NOT restore prior follows (unblocking just
-- lifts the block; re-following is a separate explicit user action).
create or replace function public.unblock_user(
  p_blocked_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  if p_blocked_id is null or p_blocked_id = v_uid then
    raise exception 'Invalid target.' using errcode = 'P0001';
  end if;

  delete from public.blocked_users
   where blocker_id = v_uid
     and blocked_id = p_blocked_id;
end;
$$;

comment on function public.unblock_user(uuid) is
  'Removes the caller''s block on p_blocked_id (auth.uid() as blocker). '
  'Idempotent. Backs SupabaseService.unblockUser (App Store Guideline 1.2).';

revoke all     on function public.unblock_user(uuid) from public;
revoke all     on function public.unblock_user(uuid) from anon;
grant  execute on function public.unblock_user(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6. Reload PostgREST schema cache so the new tables/RPCs are callable now
-- ════════════════════════════════════════════════════════════════════════════
notify pgrst, 'reload schema';
