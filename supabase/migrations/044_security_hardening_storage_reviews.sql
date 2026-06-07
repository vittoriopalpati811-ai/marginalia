-- 044_security_hardening_storage_reviews.sql
-- Security audit follow-up (50-point vibe-coded hardening).

-- ── 1. reviews: was readable by anon (public role + USING true). The app is
--    account-only, so restrict reads to signed-in users. Reviews carry the
--    reviewer's user_id and an attached highlight excerpt → not for anon. ──────
drop policy if exists "Reviews are publicly readable" on public.reviews;
create policy "reviews_select_authenticated" on public.reviews
  for select to authenticated using (true);

-- ── 2. Public buckets must not be LISTABLE. A broad SELECT policy on
--    storage.objects lets clients enumerate EVERY file in the bucket (incl. all
--    users' avatars/post images and — worst — private DM images). Public-URL
--    reads do NOT need this policy (the bucket's public flag serves objects by
--    URL), so dropping it stops enumeration without breaking image display. ────
drop policy if exists "Avatar public read"                on storage.objects;
drop policy if exists "avatars storage: lettura pubblica" on storage.objects;
drop policy if exists "Comment image public read"         on storage.objects;
drop policy if exists "Cover public read"                 on storage.objects;
drop policy if exists "Jam cover public read"             on storage.objects;
drop policy if exists "Post image public read"            on storage.objects;
drop policy if exists "message_images_select"             on storage.objects;

-- ── 3. Scope uploads to the uploader's OWN folder (auth.uid()/...). Previously
--    any authenticated user could write to ANY path in post-images /
--    comment-images (overwrite/spoof others' images). The client already
--    uploads to '<uid>/<ts>.<ext>', so owner-scoping is transparent. ──────────
drop policy if exists "Post image auth upload" on storage.objects;
create policy "post_images_owner_upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'post-images'
    and (auth.uid())::text = split_part(name, '/', 1)
  );

drop policy if exists "Comment image auth upload" on storage.objects;
create policy "comment_images_owner_upload" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'comment-images'
    and (auth.uid())::text = split_part(name, '/', 1)
  );
