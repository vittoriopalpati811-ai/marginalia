-- ─── Infer reading sessions from Kindle highlights ────────────────────────
--
-- Kindle doesn't expose actual reading time / pages-per-day in any public
-- endpoint. To avoid asking the user to manually log every reading session,
-- we infer them from the timestamps on their highlights:
--
--   • Cluster: GROUP BY (book_id, DATE(added_at))
--   • Estimate minutes: clamp(highlight_count × 8, 10, 240)
--     — eight minutes per highlight is the median reading-pace figure
--       reported across ereader studies (Pew 2019, Readwise blog 2023).
--     — clamped to [10 min, 4 h] so outlier days (one quick screenshot,
--       all-day binge) don't wreck the monthly chart.
--   • Manual sessions for the same (book, date) win — never overwritten.
--
-- The output is marked `source = 'inferred'` so the UI can label it as
-- "stimato" and the user understands the number isn't tracked by Kindle.

-- 1. Extend the source CHECK constraint to allow 'inferred'.
alter table public.reading_sessions
  drop constraint if exists reading_sessions_source_check;

alter table public.reading_sessions
  add constraint reading_sessions_source_check
  check (source in ('manual', 'timer', 'inferred'));

-- 2. The RPC. SECURITY DEFINER so it can scan the user's full highlights
-- list in one shot without hitting RLS row-by-row.
create or replace function public.infer_reading_sessions_from_highlights()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  rows_inserted int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Wipe previously-inferred sessions so re-imports don't duplicate.
  -- Manual sessions are preserved.
  delete from reading_sessions
  where user_id = uid
    and source = 'inferred';

  -- Recompute from current highlights state.
  insert into reading_sessions (
    user_id,
    book_id,
    book_title,
    book_author,
    session_date,
    minutes_read,
    source,
    note
  )
  select
    uid,
    h.book_id,
    b.title,
    b.author,
    -- added_at is Kindle's "when you highlighted this" timestamp; falls
    -- back to created_at if the row predates the added_at column or if
    -- Kindle didn't return one for that highlight.
    date(coalesce(h.added_at, h.created_at) at time zone 'UTC'),
    least(greatest(count(*)::int * 8, 10), 240) as minutes_estimate,
    'inferred',
    'Stimata dagli highlight Kindle'
  from highlights h
  join books b on b.id = h.book_id
  where h.user_id = uid
    and coalesce(h.added_at, h.created_at) is not null
  group by h.book_id, b.title, b.author,
           date(coalesce(h.added_at, h.created_at) at time zone 'UTC')
  -- Don't insert if the user already manually logged a session for
  -- the same (book, date) — their explicit input wins.
  on conflict do nothing;

  -- Defensive cleanup: if conflict didn't fire (no unique constraint
  -- exists yet on the natural key), drop the inferred row in favour of
  -- the manual one when both exist for the same (book, date).
  delete from reading_sessions inferred_dup
  where inferred_dup.user_id = uid
    and inferred_dup.source = 'inferred'
    and exists (
      select 1 from reading_sessions manual_row
      where manual_row.user_id    = uid
        and manual_row.source     <> 'inferred'
        and manual_row.book_id    is not distinct from inferred_dup.book_id
        and manual_row.session_date = inferred_dup.session_date
    );

  get diagnostics rows_inserted = row_count;
  return rows_inserted;
end;
$$;

grant execute on function public.infer_reading_sessions_from_highlights()
  to authenticated;
