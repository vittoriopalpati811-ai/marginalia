-- Marginalia — Migration 010: comment images + bucket
-- Run in Supabase SQL Editor. Idempotent.

-- ─── 1. comment-images bucket ────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('comment-images', 'comment-images', true)
on conflict (id) do nothing;

drop policy if exists "Comment image public read"  on storage.objects;
drop policy if exists "Comment image auth upload"  on storage.objects;
drop policy if exists "Comment image auth update"  on storage.objects;
drop policy if exists "Comment image owner delete" on storage.objects;

create policy "Comment image public read"
  on storage.objects for select
  using (bucket_id = 'comment-images');

create policy "Comment image auth upload"
  on storage.objects for insert
  with check (
    bucket_id = 'comment-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Comment image auth update"
  on storage.objects for update
  using (
    bucket_id = 'comment-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

create policy "Comment image owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'comment-images'
    and auth.uid()::text = split_part(name, '/', 1)
  );

-- ─── 2. image_url on jam_highlight_comments ──────────────────────────────────

alter table public.jam_highlight_comments
  add column if not exists image_url text;
