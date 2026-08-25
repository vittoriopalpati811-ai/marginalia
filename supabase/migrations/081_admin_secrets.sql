-- ─── Where the console token lives now ──────────────────────────────────────
--
-- It used to be a string constant inside the deployed admin-metrics function,
-- which is why that function could never be committed: this repo is public.
-- Keeping source out of version control in order to hide a secret is the wrong
-- trade — the source stops being reviewable and starts drifting, which
-- CLAUDE.md §5 already lists as a problem in its own right.
--
-- So the secret moves here. RLS is ON with NO policies and every grant revoked,
-- which makes the table unreachable through PostgREST for anon and authenticated
-- alike; the only reader is the service role the edge function runs as. The
-- function source is now identical in the repo and in production, and rotating
-- the token is an UPDATE rather than a redeploy.
--
-- The function still prefers an ADMIN_TOKEN environment variable when one is
-- set, so moving to Supabase secrets later needs no code change. It also treats
-- an EMPTY expected token as a refusal — a missing secret must never read as
-- "let everyone in".
create table if not exists public.admin_secrets (
  name       text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table public.admin_secrets enable row level security;
revoke all on public.admin_secrets from anon, authenticated;

-- The value itself is NOT in this file. Seed it once, out of band:
--   insert into public.admin_secrets (name, value)
--   values ('console_token', '<the token>')
--   on conflict (name) do update set value = excluded.value, updated_at = now();
