-- 053_jam_book_proposals_fk.sql
--
-- "Libro del mese" (jam book voting) fix.
--
-- jam_book_proposals.proposed_by referenced auth.users(id), so the client's
-- PostgREST embed in fetchBookProposals — select('*, profiles:proposed_by(...)')
-- — could not traverse from the proposal to public.profiles (no FK path), and
-- the whole "Libro del mese" feed errored out on load.
--
-- Re-point the FK at public.profiles(id). profiles.id itself references
-- auth.users(id) (migration 001), so the ON DELETE CASCADE chain is unchanged
-- (delete user → delete profile → delete proposals) and PostgREST can now embed
-- the proposer's display_name / username / avatar_url.

alter table public.jam_book_proposals
  drop constraint if exists jam_book_proposals_proposed_by_fkey;

alter table public.jam_book_proposals
  add constraint jam_book_proposals_proposed_by_fkey
  foreign key (proposed_by) references public.profiles(id) on delete cascade;

notify pgrst, 'reload schema';
