-- Marginalia — Row Level Security Policies
-- Esegui DOPO 001_initial_schema.sql

-- ─────────────────────────────────────────────
-- Abilita RLS su tutte le tabelle
-- ─────────────────────────────────────────────
alter table public.profiles        enable row level security;
alter table public.books           enable row level security;
alter table public.highlights      enable row level security;
alter table public.tags            enable row level security;
alter table public.highlight_tags  enable row level security;
alter table public.jams            enable row level security;
alter table public.jam_members     enable row level security;
alter table public.jam_highlights  enable row level security;
alter table public.clippings_imports enable row level security;

-- ─────────────────────────────────────────────
-- PROFILES
-- ─────────────────────────────────────────────
create policy "profiles: lettura pubblica"
  on public.profiles for select using (true);

create policy "profiles: modifica solo se proprio"
  on public.profiles for update using (auth.uid() = id);

-- ─────────────────────────────────────────────
-- BOOKS
-- ─────────────────────────────────────────────
create policy "books: CRUD solo proprietario"
  on public.books for all using (auth.uid() = user_id);

-- i membri di un Jam possono vedere i libri associati agli highlight condivisi
create policy "books: visibili a jam members via highlights"
  on public.books for select
  using (
    exists (
      select 1 from public.highlights h
      join public.jam_highlights jh on jh.highlight_id = h.id
      join public.jam_members jm on jm.jam_id = jh.jam_id
      where h.book_id = books.id
        and jm.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────
-- HIGHLIGHTS
-- ─────────────────────────────────────────────
create policy "highlights: CRUD solo proprietario"
  on public.highlights for all using (auth.uid() = user_id);

-- visibili a chi fa parte di un Jam dove sono stati condivisi
create policy "highlights: visibili a jam members se condivisi"
  on public.highlights for select
  using (
    exists (
      select 1 from public.jam_highlights jh
      join public.jam_members jm on jm.jam_id = jh.jam_id
      where jh.highlight_id = highlights.id
        and jm.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────
-- TAGS
-- ─────────────────────────────────────────────
create policy "tags: CRUD solo proprietario"
  on public.tags for all using (auth.uid() = user_id);

create policy "highlight_tags: CRUD solo proprietario"
  on public.highlight_tags for all
  using (
    exists (
      select 1 from public.highlights h
      where h.id = highlight_id and h.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────
-- JAMS
-- ─────────────────────────────────────────────
create policy "jams: lettura se membro o owner"
  on public.jams for select
  using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.jam_members jm
      where jm.jam_id = jams.id and jm.user_id = auth.uid()
    )
  );

create policy "jams: inserimento solo autenticati"
  on public.jams for insert with check (auth.uid() = owner_id);

create policy "jams: modifica solo owner"
  on public.jams for update using (auth.uid() = owner_id);

create policy "jams: cancellazione solo owner"
  on public.jams for delete using (auth.uid() = owner_id);

-- lettura pubblica invite_code (serve per join senza essere già membro)
create policy "jams: invite code pubblico per join"
  on public.jams for select using (is_active = true);

-- ─────────────────────────────────────────────
-- JAM_MEMBERS
-- ─────────────────────────────────────────────
create policy "jam_members: lettura se nel jam"
  on public.jam_members for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.jams j
      where j.id = jam_id and j.owner_id = auth.uid()
    )
  );

create policy "jam_members: join se autenticati"
  on public.jam_members for insert with check (auth.uid() = user_id);

-- l'owner può rimuovere membri, il membro può rimuovere se stesso
create policy "jam_members: uscita o rimozione"
  on public.jam_members for delete
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.jams j
      where j.id = jam_id and j.owner_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────────
-- JAM_HIGHLIGHTS
-- ─────────────────────────────────────────────
create policy "jam_highlights: lettura se membro"
  on public.jam_highlights for select
  using (
    exists (
      select 1 from public.jam_members jm
      where jm.jam_id = jam_highlights.jam_id and jm.user_id = auth.uid()
    )
    or exists (
      select 1 from public.jams j
      where j.id = jam_highlights.jam_id and j.owner_id = auth.uid()
    )
  );

-- solo il proprietario dell'highlight può condividerlo
create policy "jam_highlights: condivisione solo se propri highlight"
  on public.jam_highlights for insert
  with check (
    auth.uid() = shared_by
    and exists (
      select 1 from public.highlights h
      where h.id = highlight_id and h.user_id = auth.uid()
    )
    and exists (
      select 1 from public.jam_members jm
      where jm.jam_id = jam_highlights.jam_id and jm.user_id = auth.uid()
    )
  );

-- rimozione: solo chi ha condiviso
create policy "jam_highlights: rimozione solo chi ha condiviso"
  on public.jam_highlights for delete using (auth.uid() = shared_by);

-- ─────────────────────────────────────────────
-- CLIPPINGS IMPORTS
-- ─────────────────────────────────────────────
create policy "clippings_imports: solo proprietario"
  on public.clippings_imports for all using (auth.uid() = user_id);

-- ─────────────────────────────────────────────
-- STORAGE RLS (per i bucket)
-- ─────────────────────────────────────────────
-- bucket: clippings (privato)
create policy "clippings storage: upload autenticati"
  on storage.objects for insert
  with check (bucket_id = 'clippings' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "clippings storage: lettura solo proprio"
  on storage.objects for select
  using (bucket_id = 'clippings' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "clippings storage: delete solo proprio"
  on storage.objects for delete
  using (bucket_id = 'clippings' and auth.uid()::text = (storage.foldername(name))[1]);

-- bucket: avatars (pubblico in lettura)
create policy "avatars storage: lettura pubblica"
  on storage.objects for select using (bucket_id = 'avatars');

create policy "avatars storage: upload solo proprio"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
