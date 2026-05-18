-- Marginalia — Migration 009: post-images bucket + image_url column
-- Run in Supabase SQL Editor. Idempotent.
--
-- Adds:
--   • post-images storage bucket (public) with RLS policies
--   • image_url column to posts table (for photo posts)

-- ─── 1. post-images bucket ───────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

drop policy if exists "Post image public read"  on storage.objects;
drop policy if exists "Post image auth upload"  on storage.objects;
drop policy if exists "Post image auth update"  on storage.objects;
drop policy if exists "Post image owner delete" on storage.objects;

create policy "Post image public read"
  on storage.objects for select
  using (bucket_id = 'post-images');

create policy "Post image auth upload"
  on storage.objects for insert
  with check (
    bucket_id = 'post-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Post image auth update"
  on storage.objects for update
  using (
    bucket_id = 'post-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Post image owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'post-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

-- ─── 2. image_url column on posts ───────────────────────────────────────────

alter table public.posts
  add column if not exists image_url text;
