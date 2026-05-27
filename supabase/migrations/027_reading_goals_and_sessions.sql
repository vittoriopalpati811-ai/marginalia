-- Reading goals (one per user per year) + reading sessions (manual/timer).
-- Powers the new onboarding screen and the stats page.
-- Currently-reading already lives on `profiles` (columns currently_reading_*).

-- ─── Reading goals ──────────────────────────────────────────────────────────
-- One row per user per year. Upsert on (user_id, year).
create table if not exists public.reading_goals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  year         int not null,
  target_books int not null check (target_books > 0 and target_books <= 9999),
  updated_at   timestamptz default now(),

  unique (user_id, year)
);

alter table public.reading_goals enable row level security;

create policy "Users read own goals"
  on public.reading_goals for select
  using (auth.uid() = user_id);

create policy "Users insert own goals"
  on public.reading_goals for insert
  with check (auth.uid() = user_id);

create policy "Users update own goals"
  on public.reading_goals for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users delete own goals"
  on public.reading_goals for delete
  using (auth.uid() = user_id);

create index if not exists reading_goals_user_year_idx
  on public.reading_goals (user_id, year desc);

-- ─── Reading sessions ───────────────────────────────────────────────────────
-- Each entry = one reading event. Can be created manually (just minutes_read)
-- or by the in-app timer (which fills started_at and ended_at).
--
-- pages_read is optional; users who don't want to track pages can leave it null.
create table if not exists public.reading_sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,

  -- Optional link to a book in our `books` table; null when book unknown.
  book_id      uuid references public.books(id) on delete set null,
  book_title   text,   -- denormalized for manual entries without a book row
  book_author  text,

  session_date date not null default current_date,
  started_at   timestamptz,
  ended_at     timestamptz,

  minutes_read int  not null check (minutes_read >= 0 and minutes_read <= 1440),
  pages_read   int  check (pages_read is null or (pages_read >= 0 and pages_read <= 10000)),

  source       text not null default 'manual' check (source in ('manual', 'timer')),
  note         text,

  created_at   timestamptz default now()
);

alter table public.reading_sessions enable row level security;

create policy "Users read own sessions"
  on public.reading_sessions for select
  using (auth.uid() = user_id);

create policy "Users insert own sessions"
  on public.reading_sessions for insert
  with check (auth.uid() = user_id);

create policy "Users update own sessions"
  on public.reading_sessions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users delete own sessions"
  on public.reading_sessions for delete
  using (auth.uid() = user_id);

create index if not exists reading_sessions_user_date_idx
  on public.reading_sessions (user_id, session_date desc);

create index if not exists reading_sessions_user_book_idx
  on public.reading_sessions (user_id, book_id);

-- ─── books_finished view ───────────────────────────────────────────────────
-- Derived: a book is "finished" when it has any reading_session with
-- pages_read >= total_pages, OR when manually marked via profile setting.
-- For now we keep it simple — front-end can compute finished count from
-- sessions and book metadata. This view documents the intent.
create or replace view public.books_finished_v as
select
  rs.user_id,
  rs.book_id,
  max(rs.session_date) as last_session_date
from public.reading_sessions rs
where rs.book_id is not null
  and rs.pages_read is not null
group by rs.user_id, rs.book_id;
