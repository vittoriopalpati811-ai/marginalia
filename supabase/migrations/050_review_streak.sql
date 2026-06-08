-- 050_review_streak.sql
--
-- Adds the Ripasso (spaced-repetition) streak mirror columns to profiles. The
-- LOCAL Isar ReviewState is authoritative; these columns are a best-effort
-- publish so the streak can become social later (leaderboards, profile badge).
--
-- Idempotent (add column if not exists), mirroring the 004/027 style. RLS
-- already covers self-update on profiles, so no new policy is needed: these
-- columns are write-by-owner and readable wherever profiles already are.

alter table public.profiles
  add column if not exists review_streak      int  not null default 0,
  add column if not exists review_best_streak int  not null default 0,
  add column if not exists last_reviewed_on   date;
