-- 073: waitlist per il sito get-scripta.app.
-- Solo INSERT via API (anon): nessuna policy SELECT/UPDATE/DELETE ⇒ la lista
-- è leggibile solo dal dashboard/service-role. Email deduplicata case-insensitive.
create table public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null
    check (char_length(email) <= 320 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  locale text check (locale is null or char_length(locale) <= 8),
  source text check (source is null or char_length(source) <= 40),
  created_at timestamptz not null default now()
);

create unique index waitlist_signups_email_key
  on public.waitlist_signups (lower(email));

alter table public.waitlist_signups enable row level security;

create policy waitlist_insert_anyone
  on public.waitlist_signups
  for insert
  to anon, authenticated
  with check (true);
