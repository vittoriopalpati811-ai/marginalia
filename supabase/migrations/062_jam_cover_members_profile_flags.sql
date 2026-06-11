-- 062_jam_cover_members_profile_flags.sql
-- Three founder requests in one batch:
--
-- (1) JAM PHOTO EDITABLE BY MEMBERS. The jam-covers storage policies were
--     owner-only, but jams are edited by whoever is in them (the founder hit
--     "StorageException 403: new row violates row-level security policy"
--     changing the photo of a jam he is a member of, not the owner).
--     WhatsApp-style: any member or the owner can change the group photo.
--     The jams.cover_url column update is exposed through a SECURITY DEFINER
--     RPC (set_jam_cover) with the same membership check, because the jams
--     UPDATE policy stays owner-only for everything else (title, etc).
--
-- (2) REMOVE A FOLLOWER. follows only had a DELETE policy for the FOLLOWER
--     side (unfollow). The followee could not curate their own followers.
--
-- (3) PROFILE FLAGS. profiles.is_private (private/public profile toggle,
--     app-level gating in v1) and profiles.gender ('f'/'m', optional — used to
--     gender leaderboard titles like "Il primo"/"La prima"; the onboarding
--     already collects it but only stored it locally until now).

-- ── (1) jam-covers: member-or-owner write access ────────────────────────────

drop policy if exists "Jam cover owner upload" on storage.objects;
drop policy if exists "Jam cover owner update" on storage.objects;
drop policy if exists "Jam cover owner delete" on storage.objects;

-- Path convention: <jamId>/cover.<ext>. The uuid-shape regex guard keeps the
-- cast from ever erroring on rows of other buckets (predicate order in RLS is
-- not guaranteed). is_jam_member_or_owner is SECURITY DEFINER, so jams /
-- jam_members RLS does not interfere with the check.
create policy "Jam cover member upload" on storage.objects
  for insert with check (
    bucket_id = 'jam-covers'
    and case
      when split_part(name, '/', 1)
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.is_jam_member_or_owner(split_part(name, '/', 1)::uuid)
      else false
    end
  );

create policy "Jam cover member update" on storage.objects
  for update using (
    bucket_id = 'jam-covers'
    and case
      when split_part(name, '/', 1)
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.is_jam_member_or_owner(split_part(name, '/', 1)::uuid)
      else false
    end
  );

create policy "Jam cover member delete" on storage.objects
  for delete using (
    bucket_id = 'jam-covers'
    and case
      when split_part(name, '/', 1)
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.is_jam_member_or_owner(split_part(name, '/', 1)::uuid)
      else false
    end
  );

create or replace function public.set_jam_cover(p_jam_id uuid, p_cover_url text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_jam_member_or_owner(p_jam_id) then
    raise exception 'not a member of this jam';
  end if;
  update jams set cover_url = p_cover_url where id = p_jam_id;
end;
$$;

revoke execute on function public.set_jam_cover(uuid, text) from public;
revoke execute on function public.set_jam_cover(uuid, text) from anon;
grant execute on function public.set_jam_cover(uuid, text) to authenticated;

-- ── (2) followee can remove a follower ──────────────────────────────────────

drop policy if exists follows_remove_follower on public.follows;
create policy follows_remove_follower on public.follows
  for delete using (following_id = auth.uid());

-- ── (3) profile flags ───────────────────────────────────────────────────────

alter table public.profiles
  add column if not exists is_private boolean not null default false;

alter table public.profiles
  add column if not exists gender text
  check (gender is null or gender in ('f', 'm'));

notify pgrst, 'reload schema';
