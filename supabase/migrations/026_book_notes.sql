-- Personal book notes: one row per (user, book title, author).
-- Used by the "recommended books" feature so readers can jot down
-- thoughts about a book before — or after — reading it.

create table if not exists public.book_notes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  book_title   text not null,
  book_author  text not null default '',
  notes        text not null default '',
  updated_at   timestamptz default now(),

  -- One note per (user, title, author) — upsert-friendly
  unique (user_id, book_title, book_author)
);

alter table public.book_notes enable row level security;

create policy "Users own their book notes"
  on public.book_notes for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);
