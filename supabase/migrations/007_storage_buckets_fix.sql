-- Marginalia — Migration 007: Storage buckets + profile RLS fixes
-- Run in Supabase SQL Editor. Idempotent.
--
-- IMPORTANT: Supabase SQL Editor does NOT support "CREATE POLICY IF NOT EXISTS".
-- Use DROP POLICY IF EXISTS → CREATE POLICY pattern for all policies.

-- ─── 1. Storage buckets ───────────────────────────────────────────────────────
-- Creates the 'avatars' and 'covers' public buckets if they don't exist.
-- If they already exist this is a no-op thanks to the ON CONFLICT clause.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',    'avatars',    true, 5242880,  array['image/jpeg','image/png','image/webp','image/gif']),
  ('covers',     'covers',     true, 10485760, array['image/jpeg','image/png','image/webp']),
  ('jam-covers', 'jam-covers', true, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- ─── Jam cover_url column ────────────────────────────────────────────────────
alter table public.jams add column if not exists cover_url text;

-- ─── 2. Storage RLS policies ─────────────────────────────────────────────────

-- Avatars bucket: anyone can read, only owner can upload/update/delete
drop policy if exists "Avatar public read"          on storage.objects;
drop policy if exists "Avatar owner upload"         on storage.objects;
drop policy if exists "Avatar owner update"         on storage.objects;
drop policy if exists "Avatar owner delete"         on storage.objects;
drop policy if exists "Cover public read"           on storage.objects;
drop policy if exists "Cover owner upload"          on storage.objects;
drop policy if exists "Cover owner update"          on storage.objects;
drop policy if exists "Cover owner delete"          on storage.objects;
drop policy if exists "Jam cover public read"       on storage.objects;
drop policy if exists "Jam cover auth upload"       on storage.objects;
drop policy if exists "Jam cover auth update"       on storage.objects;
drop policy if exists "Jam cover auth delete"       on storage.objects;

create policy "Avatar public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Avatar owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Avatar owner update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Avatar owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Cover public read"
  on storage.objects for select
  using (bucket_id = 'covers');

create policy "Cover owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'covers'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Cover owner update"
  on storage.objects for update
  using (
    bucket_id = 'covers'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Cover owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'covers'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

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

-- ─── 3. Profiles table RLS fix ───────────────────────────────────────────────
-- Make sure the profiles table allows owners to update their own row.

drop policy if exists "Users can update own profile"  on public.profiles;
drop policy if exists "Profiles are viewable by everyone" on public.profiles;
drop policy if exists "Users can insert own profile"  on public.profiles;

create policy "Profiles are viewable by everyone"
  on public.profiles for select
  using (true);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ─── 4. Fix migration 006 policies (IF NOT EXISTS not supported) ─────────────

-- pinned_highlights
drop policy if exists "Users manage own pinned highlights" on public.pinned_highlights;
drop policy if exists "Pinned highlights visible to all authenticated users" on public.pinned_highlights;

create policy "Users manage own pinned highlights"
  on public.pinned_highlights for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Pinned highlights visible to all authenticated users"
  on public.pinned_highlights for select
  using (auth.role() = 'authenticated');

-- posts
drop policy if exists "Users can create posts"      on public.posts;
drop policy if exists "Posts visible to authenticated" on public.posts;
drop policy if exists "Users can update own posts"  on public.posts;
drop policy if exists "Users can delete own posts"  on public.posts;

create policy "Users can create posts"
  on public.posts for insert
  with check (auth.uid() = user_id);

create policy "Posts visible to authenticated"
  on public.posts for select
  using (auth.role() = 'authenticated');

create policy "Users can update own posts"
  on public.posts for update
  using (auth.uid() = user_id);

create policy "Users can delete own posts"
  on public.posts for delete
  using (auth.uid() = user_id);

-- post_likes
drop policy if exists "Users manage own likes"        on public.post_likes;
drop policy if exists "Likes visible to authenticated" on public.post_likes;

create policy "Users manage own likes"
  on public.post_likes for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Likes visible to authenticated"
  on public.post_likes for select
  using (auth.role() = 'authenticated');
