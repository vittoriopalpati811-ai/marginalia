-- ─── The shelf, arranged — and finally visible to other people ───────────────
--
-- Founder: "nella libreria sul profilo ci vuole un tastino che dia la
-- possibilità di modificare l'ordine dei libri … la disposizione scelta deve
-- essere poi visibile anche agli altri."
--
-- The second half of that sentence was blocked at the database, not in the UI.
-- `books` has exactly one SELECT policy — `USING (user_id = auth.uid())` — so a
-- visitor could never read another person's books AT ALL. The "LIBRI LETTI"
-- section on a visited profile has therefore always collapsed to nothing;
-- storing an arrangement without fixing that would persist the choice perfectly
-- and still show visitors an empty space.
--
-- Two objects, then:
--
--   1. user_shelf_layout — the arrangement itself. One row per reader.
--   2. public_user_shelf(target_id) — a SECURITY DEFINER window onto someone
--      else's shelf, returning ONLY titles, authors, covers and counts.
--
-- Why an RPC and not a wider RLS policy on `books`: `books` is joined from
-- `highlights` and sits on the importer's hot paths, so broadening its USING
-- clause would run on every one of those reads; and exposing a whole reading
-- history to anyone holding the public anon key plus a world-readable profile
-- id is the exact shape of the IDOR that migration 074 had to close. The RPC
-- changes nothing about existing reads and can be reasoned about on its own.

-- ── The pattern this mirrors, captured ──────────────────────────────────────
-- user_book_covers exists live (migration 20260609101459) but has no file in
-- this directory. Recreated idempotently here so a from-repo rebuild does not
-- land the table below in a database where the pattern it copies is missing.
create table if not exists public.user_book_covers (
  user_id    uuid not null,
  book_key   text not null,
  title      text,
  author     text,
  cover_url  text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, book_key)
);
alter table public.user_book_covers enable row level security;

-- ── 1. The arrangement ──────────────────────────────────────────────────────
create table if not exists public.user_shelf_layout (
  user_id uuid primary key references auth.users(id) on delete cascade,

  -- How the books are ordered. 'manual' defers to manual_order below.
  sort_mode text not null default 'title'
    check (sort_mode in ('title','author','color','most_highlighted','recent','manual')),

  -- A hand-arranged order, as an array of 'title|author' keys (lowercased,
  -- trimmed) — the SAME key user_book_covers uses and favCoverKey() already
  -- builds in Dart.
  --
  -- Deliberately NOT books.id: the profile's shelf entries carry no server id,
  -- and deleteAllBooks() wipes every books row on re-import, minting fresh
  -- uuids — an id-keyed arrangement would silently evaporate. (title, author)
  -- is already UNIQUE per user via books_user_title_author_idx.
  --
  -- Capped, because it is an unbounded user-controlled write otherwise — the
  -- same reasoning behind the length CHECKs migration 064 added everywhere.
  manual_order jsonb not null default '[]'::jsonb
    check (jsonb_typeof(manual_order) = 'array'
           and jsonb_array_length(manual_order) <= 500),

  updated_at timestamptz not null default now()
);

alter table public.user_shelf_layout enable row level security;

-- Readable by any signed-in user — that is the whole point, the arrangement is
-- meant to be seen. Scoped to `authenticated` rather than `public`: the app only
-- ever reads this signed in, and needless anon reach is what migration 074 had
-- to walk back.
drop policy if exists user_shelf_layout_read on public.user_shelf_layout;
create policy user_shelf_layout_read on public.user_shelf_layout
  for select to authenticated using (true);

drop policy if exists user_shelf_layout_owner_insert on public.user_shelf_layout;
create policy user_shelf_layout_owner_insert on public.user_shelf_layout
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists user_shelf_layout_owner_update on public.user_shelf_layout;
create policy user_shelf_layout_owner_update on public.user_shelf_layout
  for update to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists user_shelf_layout_owner_delete on public.user_shelf_layout;
create policy user_shelf_layout_owner_delete on public.user_shelf_layout
  for delete to authenticated using (user_id = auth.uid());

-- ── 2. Somebody else's shelf ────────────────────────────────────────────────
--
-- Returns what a shelf needs to be DRAWN and nothing else. In particular it
-- never returns highlights.content: the highlight text is the private asset,
-- and it is exactly what the migration-074 IDOR leaked. A count is enough to
-- set a spine's thickness.
--
-- Privacy is enforced INSIDE the function, so `profiles.is_private` becomes a
-- real boundary on this surface rather than the app-level soft gate it is
-- elsewhere. A private reader's shelf stays invisible to visitors — which is
-- also the status quo, since today they see nothing at all.
create or replace function public.public_user_shelf(target_id uuid)
returns table (title text, author text, cover_url text, highlight_count int)
language sql
security definer
set search_path to 'public', 'pg_catalog'
as $$
  select b.title,
         b.author,
         b.cover_url,
         (select count(*)::int from public.highlights h where h.book_id = b.id)
  from public.books b
  where b.user_id = target_id
    and (
      target_id = auth.uid()
      or coalesce((select p.is_private from public.profiles p where p.id = target_id), false) = false
      or exists (
        select 1 from public.follows f
        where f.follower_id = auth.uid() and f.following_id = target_id
      )
    )
  order by b.title;
$$;

-- Same rule as public_user_stats: a SECURITY DEFINER function that trusts an id
-- PARAMETER must not be reachable by anon.
revoke execute on function public.public_user_shelf(uuid) from public;
revoke execute on function public.public_user_shelf(uuid) from anon;
grant  execute on function public.public_user_shelf(uuid) to authenticated;
