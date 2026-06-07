-- 046_message_images_private_signed.sql
-- DM image privacy: make the message-images bucket PRIVATE and serve objects
-- via short-lived signed URLs. Previously the bucket was public-by-URL, so a
-- leaked DM image URL was viewable by anyone forever. Now only:
--   • the uploader (owns the "<uid>/..." path), or
--   • a member of a conversation that references the object
-- can mint a signed URL (client calls createSignedUrl with their JWT, which is
-- authorised by the SELECT policy below).
--
-- The 1.0.32 client stores the storage PATH on messages.image_url and resolves
-- it (and any legacy full bucket URL) to a signed URL at display time; external
-- URLs (GIPHY GIFs) are used unchanged. NOTE: app builds older than 1.0.32 will
-- show DM photos as unavailable until updated (they still request the old
-- public URL). GIFs and all non-image messages are unaffected.

create policy "message_images_member_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'message-images'
    and (
      -- the uploader can always read their own object
      (auth.uid())::text = split_part(name, '/', 1)
      -- or a member of a conversation that references this object
      or exists (
        select 1
        from public.messages m
        join public.conversation_members cm
          on cm.conversation_id = m.conversation_id
        where cm.user_id = auth.uid()
          and (m.image_url = name
               or m.image_url like '%/message-images/' || name)
      )
    )
  );

update storage.buckets set public = false where id = 'message-images';
