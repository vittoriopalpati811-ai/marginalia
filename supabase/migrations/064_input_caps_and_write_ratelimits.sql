-- 064_input_caps_and_write_ratelimits.sql
-- Security hardening (OWASP "strict input validation" + "rate limit public
-- writes"). Closes the gaps the 039 anti-spam batch left: a cluster of
-- secondary write paths (jam create, reviews, jam proposals/polls/challenges/
-- candidates) had NO rate limit, and several user-text columns had NO length
-- CHECK (a user could store megabytes or flood those tables).
--
-- Verified against live data first: every existing row is far under these caps
-- (max bio 19, review body 20, jam title 18, …), so the CHECKs add cleanly.
-- Rate limits reuse the existing check_rate_limit(action,max,window) RPC, which
-- RAISES when the caller (auth.uid()) exceeds the budget in the trailing
-- window — same pattern as tg_follows_antispam.

-- ── Length caps ─────────────────────────────────────────────────────────────

alter table public.profiles
  add constraint profiles_bio_len_chk
    check (bio is null or char_length(bio) <= 500),
  add constraint profiles_dname_len_chk
    check (display_name is null or char_length(display_name) <= 80),
  add constraint profiles_cr_title_len_chk
    check (currently_reading_title is null or char_length(currently_reading_title) <= 300),
  add constraint profiles_cr_author_len_chk
    check (currently_reading_author is null or char_length(currently_reading_author) <= 200);

alter table public.reviews
  add constraint reviews_body_len_chk
    check (body is null or char_length(body) <= 4000),
  add constraint reviews_booktitle_len_chk
    check (book_title is null or char_length(book_title) <= 300),
  add constraint reviews_bookauthor_len_chk
    check (book_author is null or char_length(book_author) <= 200),
  add constraint reviews_hltext_len_chk
    check (highlight_text is null or char_length(highlight_text) <= 4000);

alter table public.jams
  add constraint jams_title_len_chk
    check (title is null or char_length(title) <= 200),
  add constraint jams_desc_len_chk
    check (description is null or char_length(description) <= 2000);

alter table public.content_reports
  add constraint reports_reason_len_chk
    check (reason is null or char_length(reason) <= 300),
  add constraint reports_details_len_chk
    check (details is null or char_length(details) <= 2000);

alter table public.jam_book_proposals
  add constraint jbp_title_len_chk check (title is null or char_length(title) <= 300),
  add constraint jbp_author_len_chk check (author is null or char_length(author) <= 200),
  add constraint jbp_desc_len_chk check (description is null or char_length(description) <= 2000);

alter table public.jam_challenges
  add constraint jch_title_len_chk check (title is null or char_length(title) <= 200),
  add constraint jch_desc_len_chk check (description is null or char_length(description) <= 2000),
  add constraint jch_unit_len_chk check (unit is null or char_length(unit) <= 40);

alter table public.jam_highlight_polls
  add constraint jhp_title_len_chk check (title is null or char_length(title) <= 300);

alter table public.jam_poll_candidates
  add constraint jpc_hl_len_chk check (highlight_content is null or char_length(highlight_content) <= 2000),
  add constraint jpc_btitle_len_chk check (book_title is null or char_length(book_title) <= 300),
  add constraint jpc_bauthor_len_chk check (book_author is null or char_length(book_author) <= 200);

-- ── Anti-spam rate limits on the unthrottled write paths ────────────────────

create or replace function public.tg_jams_antispam()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_catalog'
as $$
begin
  perform public.check_rate_limit('jam_create', 10, 86400); -- 10/day
  return new;
end;
$$;
revoke execute on function public.tg_jams_antispam() from public, anon, authenticated;
drop trigger if exists trg_jams_antispam on public.jams;
create trigger trg_jams_antispam
  before insert on public.jams
  for each row execute function public.tg_jams_antispam();

create or replace function public.tg_reviews_antispam()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_catalog'
as $$
begin
  perform public.check_rate_limit('review_create', 30, 86400); -- 30/day
  return new;
end;
$$;
revoke execute on function public.tg_reviews_antispam() from public, anon, authenticated;
drop trigger if exists trg_reviews_antispam on public.reviews;
create trigger trg_reviews_antispam
  before insert on public.reviews
  for each row execute function public.tg_reviews_antispam();

-- One shared limiter for the members-only jam content tables (30/hour each).
create or replace function public.tg_jam_content_antispam()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_catalog'
as $$
begin
  perform public.check_rate_limit('jam_content', 30, 3600); -- 30/hour
  return new;
end;
$$;
revoke execute on function public.tg_jam_content_antispam() from public, anon, authenticated;

drop trigger if exists trg_jbp_antispam on public.jam_book_proposals;
create trigger trg_jbp_antispam before insert on public.jam_book_proposals
  for each row execute function public.tg_jam_content_antispam();
drop trigger if exists trg_jhp_antispam on public.jam_highlight_polls;
create trigger trg_jhp_antispam before insert on public.jam_highlight_polls
  for each row execute function public.tg_jam_content_antispam();
drop trigger if exists trg_jpc_antispam on public.jam_poll_candidates;
create trigger trg_jpc_antispam before insert on public.jam_poll_candidates
  for each row execute function public.tg_jam_content_antispam();
drop trigger if exists trg_jch_antispam on public.jam_challenges;
create trigger trg_jch_antispam before insert on public.jam_challenges
  for each row execute function public.tg_jam_content_antispam();

-- ── Lock down the Amazon extractor-script table (supply-chain) ──────────────
-- The injected JS runs inside the user's logged-in Amazon session, so only the
-- backend (service_role) must ever change it. The migration that created it
-- intended this but the write grants were never revoked from clients.
revoke insert, update, delete on public.amazon_sync_scripts from anon, authenticated;

notify pgrst, 'reload schema';
