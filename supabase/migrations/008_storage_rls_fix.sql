-- Marginalia — Migration 008: Storage buckets + RLS policy fix (simplified)
-- Run in Supabase SQL Editor. Idempotent.
--
-- Fixes:
--   • 404 on 'covers' bucket  → bucket was missing (optional columns broke INSERT)
--   • 403 on 'avatars' upload → storage.foldername() unreliable; use split_part instead

-- ─── 1. Storage buckets (minimal INSERT, no optional columns) ────────────────
-- Avoids failures caused by file_size_limit / allowed_mime_types columns not
-- existing in older Supabase versions.

insert into storage.buckets (id, name, public)
values
  ('avatars',    'avatars',    true),
  ('covers',     'covers',     true),
  ('jam-covers', 'jam-covers', true)
on conflict (id) do nothing;

-- ─── 2. Drop all existing storage object policies ────────────────────────────
-- Use explicit DROP to avoid "policy already exists" errors.

drop policy if exists "Avatar public read"     on storage.objects;
drop policy if exists "Avatar owner upload"    on storage.objects;
drop policy if exists "Avatar owner update"    on storage.objects;
drop policy if exists "Avatar owner delete"    on storage.objects;
drop policy if exists "Cover public read"      on storage.objects;
drop policy if exists "Cover owner upload"     on storage.objects;
drop policy if exists "Cover owner update"     on storage.objects;
drop policy if exists "Cover owner delete"     on storage.objects;
drop policy if exists "Jam cover public read"  on storage.objects;
drop policy if exists "Jam cover auth upload"  on storage.objects;
drop policy if exists "Jam cover auth update"  on storage.objects;
drop policy if exists "Jam cover auth delete"  on storage.objects;

-- ─── 3. Avatars bucket ───────────────────────────────────────────────────────
-- Path convention: {userId}/avatar.{ext}
-- Use split_part(name, '/', 1) which is more reliable than storage.foldername()[1]

create policy "Avatar public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Avatar owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Avatar owner update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Avatar owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
  );

-- ─── 4. Covers bucket ────────────────────────────────────────────────────────
-- Path convention: {userId}/cover.{ext}

create policy "Cover public read"
  on storage.objects for select
  using (bucket_id = 'covers');

create policy "Cover owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'covers'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Cover owner update"
  on storage.objects for update
  using (
    bucket_id = 'covers'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Cover owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'covers'
    and auth.uid()::text = split_part(name, '/', 1)
  );

-- ─── 5. Jam-covers bucket ────────────────────────────────────────────────────
-- Any authenticated user may upload/update/delete (jam members may add covers)

create policy "Jam cover public read"
  on storage.objects for select
  using (bucket_id = 'jam-covers');

create policy "Jam cover auth upload"
  on storage.objects for insert
  with check (
    bucket_id = 'jam-covers'
    and auth.role() = 'authenticated'
  );

create policy "Jam cover auth update"
  on storage.objects for update
  using (
    bucket_id = 'jam-covers'
    and auth.role() = 'authenticated'
  );

create policy "Jam cover auth delete"
  on storage.objects for delete
  using (
    bucket_id = 'jam-covers'
    and auth.role() = 'authenticated'
  );
