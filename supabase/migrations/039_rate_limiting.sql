-- 037_rate_limiting.sql
--
-- Application-level ANTI-SPAM / ANTI-BOT / RATE-ABUSE protection on the write
-- paths. The founder asked for "filtro anti spam e anti bot" + "protezione dal
-- rate abusing e dagli attacchi DDoS".
--
-- SCOPE / WHO COVERS WHAT
--   • Network-layer DDoS (volumetric floods, L3/L4, TLS, raw HTTP) is handled
--     by the Supabase PLATFORM, which fronts every project with Cloudflare
--     (global anycast, automatic L3/L4 + L7 mitigation, connection rate
--     limiting). We cannot configure that from SQL and do not try to.
--   • What we CAN add — and what this migration does — is per-USER, per-ACTION
--     rate limiting + content anti-spam heuristics enforced inside Postgres, so
--     a single authenticated account cannot flood posts/comments/messages/
--     follows or spam duplicate/empty/oversized content. This closes the
--     follow-up flagged in docs/security-audit.md ("Add a rate-limit on posts /
--     messages insert (currently unlimited)") and the unfulfilled TODO in the
--     header of migration 016.
--
-- DESIGN
--   • All current write paths (posts, post_comments, messages, follows,
--     jam_highlight_comments) are PLAIN CLIENT INSERTS under RLS — none of them
--     go through a SECURITY DEFINER RPC (see lib/core/services/
--     supabase_service.dart: createPost / addPostComment / sendMessage /
--     followUser / addComment all call _client.from(...).insert(...)). So the
--     enforcement point is a BEFORE INSERT trigger on each table that calls the
--     shared check_rate_limit() helper and applies content heuristics, then
--     records the event. Triggers run as the table owner, so they read/write
--     rate_events regardless of the caller's RLS — without weakening any
--     existing table RLS (we add NO new SELECT/INSERT/UPDATE/DELETE policy that
--     loosens access; rate_events is fail-closed for clients).
--
--   • Idempotent throughout (create table if not exists / create or replace /
--     drop trigger if exists). Safe to re-run.
--
-- Apply via the Supabase MCP (the parent applies this; do NOT run it here).

-- ════════════════════════════════════════════════════════════════════════════
-- 1. rate_events — lightweight rolling log of write actions per user
-- ════════════════════════════════════════════════════════════════════════════
-- One row per counted write. check_rate_limit() counts rows in a trailing
-- window. Kept deliberately narrow (no payload) so it stays cheap to write and
-- prune. created_at is the only thing we ever filter on besides (user_id, action).

create table if not exists public.rate_events (
  id         bigint generated always as identity primary key,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  action     text        not null,
  created_at timestamptz not null default now()
);

-- Hot path for check_rate_limit: WHERE user_id = ? AND action = ? AND created_at > ?
create index if not exists rate_events_user_action_time_idx
  on public.rate_events (user_id, action, created_at desc);

-- For the pruning sweep (delete everything older than the retention horizon).
create index if not exists rate_events_created_idx
  on public.rate_events (created_at);

-- RLS: fail closed. rate_events is internal bookkeeping. We enable RLS and add
-- NO policy, so the anon/authenticated roles can neither read nor write it
-- directly from the client (deny-by-default). The SECURITY DEFINER /
-- trigger-owner functions below are the only writers/readers. This does not
-- touch or weaken any other table's RLS.
alter table public.rate_events enable row level security;

-- ════════════════════════════════════════════════════════════════════════════
-- 2. check_rate_limit(action, max, window_seconds)
-- ════════════════════════════════════════════════════════════════════════════
-- Counts the CALLER's (auth.uid()) recent `action` events inside the trailing
-- `window_seconds`. Raises (sqlstate 'P0001') when the count is already at/over
-- `p_max` — i.e. this would be the (max+1)-th action in the window. Otherwise
-- records the event and returns true.
--
-- SECURITY DEFINER so it can read/insert rate_events under the owner role even
-- though the table's RLS denies the client. search_path pinned (matches the
-- hardening convention in migrations 028/034). Also opportunistically prunes a
-- little stale history on ~2% of calls to keep the table small without a cron.
create or replace function public.check_rate_limit(
  p_action          text,
  p_max             int,
  p_window_seconds  int
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  -- No authenticated identity → nothing to meter against. Let RLS / WITH CHECK
  -- on the underlying table reject the row (they already require auth.uid()).
  if v_uid is null then
    return true;
  end if;

  -- Defensive defaults so a bad caller can't disable the limiter with 0/neg.
  if p_max is null or p_max < 1 then
    p_max := 1;
  end if;
  if p_window_seconds is null or p_window_seconds < 1 then
    p_window_seconds := 60;
  end if;

  select count(*)
    into v_count
    from public.rate_events
   where user_id = v_uid
     and action  = p_action
     and created_at > now() - make_interval(secs => p_window_seconds);

  if v_count >= p_max then
    raise exception
      'Rate limit exceeded for action "%" (max % per % seconds). Slow down and try again shortly.',
      p_action, p_max, p_window_seconds
      using errcode = 'P0001';
  end if;

  insert into public.rate_events (user_id, action) values (v_uid, p_action);

  -- Cheap, occasional self-pruning: drop rows older than 25h (longest window we
  -- use is the 24h daily post cap). ~2% sampling keeps it off the hot path.
  if random() < 0.02 then
    delete from public.rate_events
     where created_at < now() - interval '25 hours';
  end if;

  return true;
end;
$$;

-- Callable as a standalone RPC by signed-in users too (e.g. if a future
-- SECURITY DEFINER RPC wants to gate itself by calling it). Never by anon.
revoke all on function public.check_rate_limit(text, int, int) from public;
revoke all on function public.check_rate_limit(text, int, int) from anon;
grant execute on function public.check_rate_limit(text, int, int) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Anti-spam content heuristic (shared helper)
-- ════════════════════════════════════════════════════════════════════════════
-- Rejects trivially-duplicated content: the SAME non-empty trimmed text, for
-- the same user, posted again within p_window_seconds. Used by the post,
-- comment and message triggers. Reads rate_events? No — it reads the target
-- table itself, so it is implemented inline per trigger where the table/column
-- differ. This helper covers only the duplicate check against a provided
-- "previous body" set, keeping the triggers small.
--
-- NOTE: empty-after-trim and over-length checks are done in each trigger
-- because what counts as "empty" differs per table (a post may be image- or
-- highlight-only with a NULL body and that is legitimately NOT empty).

-- (No standalone duplicate helper is needed; each trigger runs a scoped EXISTS
--  against its own table. Kept as a comment to document the decision.)

-- ════════════════════════════════════════════════════════════════════════════
-- 4. Trigger functions (BEFORE INSERT) — one per write path
-- ════════════════════════════════════════════════════════════════════════════
-- Each: (a) normalises/validates content, (b) calls check_rate_limit with the
-- table's caps, (c) lets the row through. All run as the table owner (BEFORE
-- triggers do), so they may use check_rate_limit's owner privileges.

-- ── 4a. posts ────────────────────────────────────────────────────────────────
-- Caps: 5/min AND 100/day. Content: must carry SOMETHING (body OR highlight OR
-- image OR video — a NULL body alone is fine for a highlight/image post); body
-- (if present) not over the existing 4000-char CHECK; no exact-duplicate body
-- re-posted within 60s by the same user.
create or replace function public.tg_posts_antispam()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_body text := nullif(btrim(coalesce(new.body, '')), '');
begin
  -- Normalise: store the trimmed body (or NULL) so downstream/length checks and
  -- the duplicate test see a canonical value.
  new.body := v_body;

  -- Content presence: a post must contain at least one of body / highlight /
  -- image / video. Reject a completely empty post (anti-spam / anti-bot noise).
  if v_body is null
     and new.highlight_id is null
     and coalesce(new.image_url, '') = ''
     and coalesce(new.video_url, '') = '' then
    raise exception 'A post cannot be empty.' using errcode = 'P0001';
  end if;

  -- Absurdly long (mirrors posts_body_len_chk = 4000 from migration 028; we
  -- raise a friendly error before the CHECK constraint fires).
  if v_body is not null and char_length(v_body) > 4000 then
    raise exception 'Post is too long (max 4000 characters).' using errcode = 'P0001';
  end if;

  -- Trivial duplicate: same trimmed body by the same user within 60s.
  if v_body is not null and exists (
    select 1 from public.posts p
     where p.user_id = new.user_id
       and p.body    = v_body
       and p.created_at > now() - interval '60 seconds'
  ) then
    raise exception 'Duplicate post detected — you just posted this.' using errcode = 'P0001';
  end if;

  -- Rate caps: burst (5/min) and sustained (100/day).
  perform public.check_rate_limit('post_minute', 5,   60);
  perform public.check_rate_limit('post_day',    100, 86400);

  return new;
end;
$$;

-- ── 4b. post_comments ────────────────────────────────────────────────────────
-- Cap: 10/min. Content: must carry text OR image OR gif; content (if present)
-- not over the existing 2000-char CHECK; no exact-duplicate text within 30s on
-- the SAME post by the same user.
create or replace function public.tg_post_comments_antispam()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_content text := nullif(btrim(coalesce(new.content, '')), '');
begin
  new.content := v_content;

  if v_content is null
     and coalesce(new.image_url, '') = ''
     and coalesce(new.gif_url, '')   = '' then
    raise exception 'A comment cannot be empty.' using errcode = 'P0001';
  end if;

  if v_content is not null and char_length(v_content) > 2000 then
    raise exception 'Comment is too long (max 2000 characters).' using errcode = 'P0001';
  end if;

  if v_content is not null and exists (
    select 1 from public.post_comments c
     where c.user_id = new.user_id
       and c.post_id = new.post_id
       and c.content = v_content
       and c.created_at > now() - interval '30 seconds'
  ) then
    raise exception 'Duplicate comment detected.' using errcode = 'P0001';
  end if;

  perform public.check_rate_limit('comment_minute', 10, 60);

  return new;
end;
$$;

-- ── 4c. messages ─────────────────────────────────────────────────────────────
-- Cap: 30/min (chat is naturally chattier). Content: text OR image; content
-- (if present) not over the existing 4000-char CHECK. No duplicate check on
-- messages — repeating a short message ("ok", "ahah") in chat is legitimate;
-- the per-minute cap is the abuse control here.
create or replace function public.tg_messages_antispam()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_content text := nullif(btrim(coalesce(new.content, '')), '');
begin
  new.content := v_content;

  if v_content is null
     and coalesce(new.image_url, '') = '' then
    raise exception 'A message cannot be empty.' using errcode = 'P0001';
  end if;

  if v_content is not null and char_length(v_content) > 4000 then
    raise exception 'Message is too long (max 4000 characters).' using errcode = 'P0001';
  end if;

  perform public.check_rate_limit('message_minute', 30, 60);

  return new;
end;
$$;

-- ── 4d. follows ──────────────────────────────────────────────────────────────
-- Cap: 60/min (mass-follow is the classic bot signal). No content. The
-- followUser() client path UPSERTs, so re-following an existing edge is a
-- conflict-do-nothing and does NOT fire a fresh INSERT — only genuinely new
-- follow rows are metered.
create or replace function public.tg_follows_antispam()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  perform public.check_rate_limit('follow_minute', 60, 60);
  return new;
end;
$$;

-- ── 4e. jam_highlight_comments ───────────────────────────────────────────────
-- Same family as post comments (the in-Jam comment thread). Cap: 10/min.
-- content is NOT NULL on this table, but could still be whitespace-only — reject
-- that. No existing length CHECK on this table, so we apply the same 2000 cap as
-- post_comments for parity. Duplicate text on the same highlight within 30s is
-- rejected.
create or replace function public.tg_jam_comments_antispam()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_content text := nullif(btrim(coalesce(new.content, '')), '');
begin
  if v_content is null then
    raise exception 'A comment cannot be empty.' using errcode = 'P0001';
  end if;
  new.content := v_content;

  if char_length(v_content) > 2000 then
    raise exception 'Comment is too long (max 2000 characters).' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.jam_highlight_comments c
     where c.user_id          = new.user_id
       and c.jam_highlight_id = new.jam_highlight_id
       and c.content          = v_content
       and c.created_at > now() - interval '30 seconds'
  ) then
    raise exception 'Duplicate comment detected.' using errcode = 'P0001';
  end if;

  perform public.check_rate_limit('jam_comment_minute', 10, 60);

  return new;
end;
$$;

-- These trigger functions fire from the database, never legitimately via the
-- REST RPC endpoint — remove them from the callable API (same posture as the
-- trigger functions hardened in migration 034).
revoke all on function public.tg_posts_antispam()         from public, anon, authenticated;
revoke all on function public.tg_post_comments_antispam() from public, anon, authenticated;
revoke all on function public.tg_messages_antispam()      from public, anon, authenticated;
revoke all on function public.tg_follows_antispam()       from public, anon, authenticated;
revoke all on function public.tg_jam_comments_antispam()  from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 5. Wire up the triggers (idempotent: drop-if-exists then create)
-- ════════════════════════════════════════════════════════════════════════════
drop trigger if exists trg_posts_antispam on public.posts;
create trigger trg_posts_antispam
  before insert on public.posts
  for each row execute function public.tg_posts_antispam();

drop trigger if exists trg_post_comments_antispam on public.post_comments;
create trigger trg_post_comments_antispam
  before insert on public.post_comments
  for each row execute function public.tg_post_comments_antispam();

drop trigger if exists trg_messages_antispam on public.messages;
create trigger trg_messages_antispam
  before insert on public.messages
  for each row execute function public.tg_messages_antispam();

drop trigger if exists trg_follows_antispam on public.follows;
create trigger trg_follows_antispam
  before insert on public.follows
  for each row execute function public.tg_follows_antispam();

drop trigger if exists trg_jam_comments_antispam on public.jam_highlight_comments;
create trigger trg_jam_comments_antispam
  before insert on public.jam_highlight_comments
  for each row execute function public.tg_jam_comments_antispam();

-- ════════════════════════════════════════════════════════════════════════════
-- 6. Reload PostgREST schema cache
-- ════════════════════════════════════════════════════════════════════════════
notify pgrst, 'reload schema';
