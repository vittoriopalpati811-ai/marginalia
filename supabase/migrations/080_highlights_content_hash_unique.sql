-- ─── The constraint the client already believed in ──────────────────────────
--
-- import_service_native.dart carries this comment above the cloud backup:
--
--     The server enforces UNIQUE(user_id, content_hash) with
--     content_hash = sha256("bookId content").
--
-- It did not. `highlights` had exactly three constraints — the primary key and
-- two foreign keys — so the only thing standing between a repeated sync and a
-- duplicated library was the deterministic row id, and any path that computed a
-- different id sailed straight past it. A book stored under two capitalisations
-- produced two book ids, therefore two highlight ids per quote, therefore two
-- copies of every highlight. That is not hypothetical: two production accounts
-- were in exactly that state ("Il nome della rosa" with 5 highlights alongside
-- "Il Nome della Rosa" with 21), and both were merged before this index was
-- created.
--
-- content_hash is sha256("<bookId> <content>"), so this reads as "the same
-- quote, in the same book, for the same reader, once". Two different books keep
-- their own copy of a shared quote, which is right — they are different
-- readings of it.
--
-- Partial on `content_hash is not null` so a row written by any path that has
-- not computed one yet is never rejected. Verified before creating: 2051 of
-- 2051 rows carry a hash, 0 conflicting groups.
create unique index if not exists highlights_user_content_hash_uidx
  on public.highlights (user_id, content_hash)
  where content_hash is not null;
