-- 045_storage_owner_scoping.sql
-- Tighten storage UPDATE/DELETE/INSERT policies so a stored file can only be
-- modified or removed by its OWNER (or, for jam covers, the Jam's owner).
-- Several legacy policies used auth.role()='authenticated'. Because RLS policies
-- are OR-combined (permissive), those let ANY authenticated user overwrite or
-- delete ANY other user's post images, comment images and jam covers
-- (tampering / IDOR). Uploads are written under "<uid>/..." (post/comment/
-- message images) or "<jamId>/cover.<ext>" (jam covers), so we scope by the
-- first path segment.

-- ── post-images ─────────────────────────────────────────────────────────────
drop policy if exists "Post image auth update" on storage.objects;
drop policy if exists "Post image auth delete" on storage.objects;

create policy "Post image owner update"
  on storage.objects for update to authenticated
  using (bucket_id = 'post-images' and (auth.uid())::text = split_part(name, '/', 1))
  with check (bucket_id = 'post-images' and (auth.uid())::text = split_part(name, '/', 1));
-- "Post image owner delete" (owner-scoped) already exists and is kept.

-- ── comment-images ──────────────────────────────────────────────────────────
drop policy if exists "Comment image auth delete" on storage.objects;
-- "Comment image owner delete" + "Comment image auth update" (already
-- owner-scoped) + comment_images_owner_upload are kept.

-- ── jam-covers ──────────────────────────────────────────────────────────────
-- Covers live at "<jamId>/cover.<ext>"; scope all writes to the Jam's owner.
drop policy if exists "Jam cover auth upload" on storage.objects;
drop policy if exists "Jam cover auth update" on storage.objects;
drop policy if exists "Jam cover auth delete" on storage.objects;

create policy "Jam cover owner upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'jam-covers'
    and exists (
      select 1 from public.jams j
      where j.id::text = split_part(name, '/', 1) and j.owner_id = auth.uid()
    )
  );

create policy "Jam cover owner update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'jam-covers'
    and exists (
      select 1 from public.jams j
      where j.id::text = split_part(name, '/', 1) and j.owner_id = auth.uid()
    )
  );

create policy "Jam cover owner delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'jam-covers'
    and exists (
      select 1 from public.jams j
      where j.id::text = split_part(name, '/', 1) and j.owner_id = auth.uid()
    )
  );

-- ── message-images ──────────────────────────────────────────────────────────
-- Written at "<uid>/...", so scope INSERT to the owner (was auth.role()).
drop policy if exists "message_images_insert" on storage.objects;

create policy "message_images_owner_insert"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'message-images' and (auth.uid())::text = split_part(name, '/', 1));
