-- 066_restore_storage_owner_read.sql
-- FIX a production regression introduced by 044_security_hardening_storage_reviews.
--
-- 044 dropped the public-read SELECT policies on storage.objects for the PUBLIC
-- buckets (avatars / covers / post-images / comment-images / jam-covers /
-- book-covers) to stop file ENUMERATION. That intent is correct, but it had an
-- unintended side effect: the storage-api reads the object row back after the
-- INSERT (RETURNING), so with NO SELECT policy at all the upload itself fails
-- with "new row violates row-level security policy" (HTTP 400 / statusCode 403).
-- Net effect since 044 shipped (2026-06-11): NOBODY could upload a post image,
-- comment image, avatar, profile cover, book cover or jam cover. Only
-- message-images kept working because it still had a SELECT policy
-- (message_images_member_read).
--
-- Confirmed by reproduction: a real authenticated user gets 10/10 failures on
-- public buckets and 10/10 successes on message-images; adding an owner-scoped
-- SELECT flips the public bucket to 10/10 successes.
--
-- FIX: give each public bucket an OWNER-SCOPED SELECT policy. This restores
-- uploads (the uploader can read back its own freshly-inserted row) WITHOUT
-- re-introducing the enumeration hole 044 closed: a user can only list/read
-- files under its OWN "<uid>/..." folder, never anyone else's. Public display
-- of other users' images keeps working through the bucket's public flag / CDN
-- URL, which does not consult these RLS policies. Private DM images
-- (message-images) are untouched and stay member-scoped.

-- avatars (path: <uid>/...)
drop policy if exists "avatars_owner_read" on storage.objects;
create policy "avatars_owner_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (auth.uid())::text = split_part(name, '/', 1));

-- covers (path: <uid>/...)
drop policy if exists "covers_owner_read" on storage.objects;
create policy "covers_owner_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'covers' and (auth.uid())::text = split_part(name, '/', 1));

-- post-images (path: <uid>/...)
drop policy if exists "post_images_owner_read" on storage.objects;
create policy "post_images_owner_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'post-images' and (auth.uid())::text = split_part(name, '/', 1));

-- comment-images (path: <uid>/...)
drop policy if exists "comment_images_owner_read" on storage.objects;
create policy "comment_images_owner_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'comment-images' and (auth.uid())::text = split_part(name, '/', 1));

-- book-covers (path: <uid>/...)
drop policy if exists "book_covers_owner_read" on storage.objects;
create policy "book_covers_owner_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (auth.uid())::text);

-- jam-covers (path: <jamId>/cover.<ext>; the uploader is a member/owner)
drop policy if exists "jam_covers_member_read" on storage.objects;
create policy "jam_covers_member_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'jam-covers'
    and case
      when split_part(name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then is_jam_member_or_owner(split_part(name, '/', 1)::uuid)
      else false
    end
  );
