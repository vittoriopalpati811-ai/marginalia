-- Marginalia — Initial Schema
-- Run in Supabase SQL editor or via supabase db push

-- ─────────────────────────────────────────────
-- PROFILES (extends auth.users)
-- ─────────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  username    text unique not null,
  display_name text,
  avatar_url  text,
  created_at  timestamptz default now() not null
);

-- ─────────────────────────────────────────────
-- BOOKS
-- ─────────────────────────────────────────────
create table public.books (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users on delete cascade not null,
  title        text not null,
  author       text not null,
  imported_at  timestamptz default now() not null,
  cover_color  text default '#8B7355' not null  -- hex, fallback seppia
);

create index books_user_id_idx on public.books(user_id);
create unique index books_user_title_author_idx on public.books(user_id, title, author);

-- ─────────────────────────────────────────────
-- HIGHLIGHTS
-- ─────────────────────────────────────────────
create table public.highlights (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references auth.users on delete cascade not null,
  book_id              uuid references public.books on delete cascade not null,
  content              text not null,
  location             text,                        -- "Location 1234-1236"
  added_at             timestamptz,                 -- quando l'utente ha sottolineato su Kindle
  personal_note        text,
  content_hash         text not null,               -- sha256(book_id || content) per dedup
  last_shown_in_widget timestamptz,
  created_at           timestamptz default now() not null
);

create index highlights_user_id_idx on public.highlights(user_id);
create index highlights_book_id_idx on public.highlights(book_id);
create unique index highlights_content_hash_idx on public.highlights(user_id, content_hash);

-- ─────────────────────────────────────────────
-- TAGS
-- ─────────────────────────────────────────────
create table public.tags (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users on delete cascade not null,
  name    text not null,
  color   text default '#C4A882',
  unique(user_id, name)
);

create table public.highlight_tags (
  highlight_id uuid references public.highlights on delete cascade not null,
  tag_id       uuid references public.tags on delete cascade not null,
  primary key (highlight_id, tag_id)
);

-- ─────────────────────────────────────────────
-- JAMS (social reading circles)
-- ─────────────────────────────────────────────
create table public.jams (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid references auth.users on delete cascade not null,
  title        text not null,
  description  text,
  book_filter  text,    -- optional: jam focalizzato su un libro specifico (titolo libero, non FK)
  invite_code  text unique not null default substr(md5(random()::text), 1, 8),
  is_active    boolean default true not null,
  created_at   timestamptz default now() not null
);

create index jams_owner_id_idx on public.jams(owner_id);

create table public.jam_members (
  jam_id    uuid references public.jams on delete cascade not null,
  user_id   uuid references auth.users on delete cascade not null,
  joined_at timestamptz default now() not null,
  primary key (jam_id, user_id)
);

-- highlight condiviso esplicitamente in un Jam
create table public.jam_highlights (
  jam_id       uuid references public.jams on delete cascade not null,
  highlight_id uuid references public.highlights on delete cascade not null,
  shared_by    uuid references auth.users on delete cascade not null,
  shared_at    timestamptz default now() not null,
  primary key (jam_id, highlight_id)
);

create index jam_highlights_jam_id_idx on public.jam_highlights(jam_id);

-- ─────────────────────────────────────────────
-- CLIPPINGS IMPORTS (log upload)
-- ─────────────────────────────────────────────
create table public.clippings_imports (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users on delete cascade not null,
  file_path          text,         -- path in Supabase Storage
  status             text default 'pending' not null,  -- pending | processing | done | error
  error_message      text,
  books_added        int default 0,
  highlights_added   int default 0,
  duplicates_skipped int default 0,
  imported_at        timestamptz default now() not null
);

create index clippings_imports_user_id_idx on public.clippings_imports(user_id);

-- ─────────────────────────────────────────────
-- STORAGE BUCKETS (esegui in Supabase dashboard o via API)
-- ─────────────────────────────────────────────
-- insert into storage.buckets (id, name, public) values ('clippings', 'clippings', false);
-- insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true);

-- ─────────────────────────────────────────────
-- TRIGGER: crea profilo automaticamente su signup
-- ─────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'username',
      split_part(new.email, '@', 1)
    ),
    new.raw_user_meta_data->>'display_name'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
