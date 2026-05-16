-- Marginalia — Seed: 5 dummy users for social interaction testing
-- Run in Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).
-- Idempotent: ON CONFLICT DO NOTHING everywhere.
-- After running, copy the UUID of YOUR real account and run the follow/jam section
-- at the bottom to link yourself to the dummy users.

-- ─────────────────────────────────────────────────────────────────────────────
-- Fixed UUIDs (all hex-valid)
-- ─────────────────────────────────────────────────────────────────────────────
-- Users:     a1000001-aaaa-4000-8000-00000000000{1-5}
-- Books:     b1000001-aaaa-4000-8000-0000000000{11-51}
-- Highlights:c1000001-aaaa-4000-8000-000000000{101-501}
-- Jams:      de000001-aaaa-4000-8000-00000000000{1-2}

DO $$
DECLARE
  u1  uuid := 'a1000001-aaaa-4000-8000-000000000001';
  u2  uuid := 'a1000001-aaaa-4000-8000-000000000002';
  u3  uuid := 'a1000001-aaaa-4000-8000-000000000003';
  u4  uuid := 'a1000001-aaaa-4000-8000-000000000004';
  u5  uuid := 'a1000001-aaaa-4000-8000-000000000005';
  b1a uuid := 'b1000001-aaaa-4000-8000-000000000011';
  b1b uuid := 'b1000001-aaaa-4000-8000-000000000012';
  b2a uuid := 'b1000001-aaaa-4000-8000-000000000021';
  b2b uuid := 'b1000001-aaaa-4000-8000-000000000022';
  b3a uuid := 'b1000001-aaaa-4000-8000-000000000031';
  b4a uuid := 'b1000001-aaaa-4000-8000-000000000041';
  b5a uuid := 'b1000001-aaaa-4000-8000-000000000051';
  h1a uuid := 'c1000001-aaaa-4000-8000-000000000101';
  h1b uuid := 'c1000001-aaaa-4000-8000-000000000102';
  h2a uuid := 'c1000001-aaaa-4000-8000-000000000201';
  h2b uuid := 'c1000001-aaaa-4000-8000-000000000202';
  h3a uuid := 'c1000001-aaaa-4000-8000-000000000301';
  h4a uuid := 'c1000001-aaaa-4000-8000-000000000401';
  h5a uuid := 'c1000001-aaaa-4000-8000-000000000501';
  jam_id  uuid := 'de000001-aaaa-4000-8000-000000000001';
  jam_id2 uuid := 'de000001-aaaa-4000-8000-000000000002';
BEGIN

-- ─── 1. AUTH USERS ────────────────────────────────────────────────────────────
INSERT INTO auth.users (
  id, instance_id, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  role, aud, raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token,
  email_change_token_new, email_change
)
VALUES
  (u1,'00000000-0000-0000-0000-000000000000','marco.rossi@example.com','',now(),now()-interval'30 days',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"display_name":"Marco Rossi"}','','','',''),
  (u2,'00000000-0000-0000-0000-000000000000','sofia.bianchi@example.com','',now(),now()-interval'25 days',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"display_name":"Sofia Bianchi"}','','','',''),
  (u3,'00000000-0000-0000-0000-000000000000','luca.ferrari@example.com','',now(),now()-interval'20 days',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"display_name":"Luca Ferrari"}','','','',''),
  (u4,'00000000-0000-0000-0000-000000000000','elena.conti@example.com','',now(),now()-interval'15 days',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"display_name":"Elena Conti"}','','','',''),
  (u5,'00000000-0000-0000-0000-000000000000','davide.russo@example.com','',now(),now()-interval'10 days',now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"display_name":"Davide Russo"}','','','','')
ON CONFLICT (id) DO NOTHING;

-- ─── 2. PROFILES ──────────────────────────────────────────────────────────────
INSERT INTO public.profiles (id, username, display_name, currently_reading_title, currently_reading_author)
VALUES
  (u1,'marco.rossi','Marco Rossi','Il Nome della Rosa','Umberto Eco'),
  (u2,'sofia.bianchi','Sofia Bianchi','Sapiens','Yuval Noah Harari'),
  (u3,'luca.ferrari','Luca Ferrari','1984','George Orwell'),
  (u4,'elena.conti','Elena Conti','Il Piccolo Principe','Antoine de Saint-Exupery'),
  (u5,'davide.russo','Davide Russo','Siddhartha','Hermann Hesse')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  currently_reading_title = EXCLUDED.currently_reading_title,
  currently_reading_author = EXCLUDED.currently_reading_author;

-- ─── 3. BOOKS ─────────────────────────────────────────────────────────────────
INSERT INTO public.books (id, user_id, title, author)
VALUES
  (b1a,u1,'Il Nome della Rosa','Umberto Eco'),
  (b1b,u1,'Se questo e un uomo','Primo Levi'),
  (b2a,u2,'Sapiens','Yuval Noah Harari'),
  (b2b,u2,'La solitudine dei numeri primi','Paolo Giordano'),
  (b3a,u3,'1984','George Orwell'),
  (b4a,u4,'Il Piccolo Principe','Antoine de Saint-Exupery'),
  (b5a,u5,'Siddhartha','Hermann Hesse')
ON CONFLICT DO NOTHING;

-- ─── 4. HIGHLIGHTS ────────────────────────────────────────────────────────────
INSERT INTO public.highlights (id, user_id, book_id, content, location, added_at, content_hash, color)
VALUES
  (h1a,u1,b1a,'I libri non sono fatti per essere creduti, ma per essere sottoposti a indagine.','342',now()-interval'28 days',md5(u1::text||h1a::text),'yellow'),
  (h1b,u1,b1b,'Se comprendere e impossibile, conoscere e necessario, perche cio che e accaduto puo ritornare.','89',now()-interval'26 days',md5(u1::text||h1b::text),'blue'),
  (h2a,u2,b2a,'La storia comincio quando circa 70.000 anni fa avvenne una mutazione accidentale nelle catene del DNA di un Sapiens.','55',now()-interval'22 days',md5(u2::text||h2a::text),'orange'),
  (h2b,u2,b2b,'La solitudine non e stare soli. La solitudine e non riuscire a comunicare le cose che sembrano importanti.','211',now()-interval'18 days',md5(u2::text||h2b::text),'pink'),
  (h3a,u3,b3a,'La guerra e pace. La liberta e schiavitu. L ignoranza e forza.','17',now()-interval'16 days',md5(u3::text||h3a::text),'yellow'),
  (h4a,u4,b4a,'Tutte le persone grandi sono state bambine una volta. Ma poche di esse se ne ricordano.','5',now()-interval'12 days',md5(u4::text||h4a::text),'yellow'),
  (h5a,u5,b5a,'Dentro di noi c e qualcuno che sa tutto, che vuole tutto, che fa tutto meglio di noi.','134',now()-interval'8 days',md5(u5::text||h5a::text),'blue')
ON CONFLICT DO NOTHING;

-- ─── 5. JAMS ──────────────────────────────────────────────────────────────────
INSERT INTO public.jams (id, owner_id, title, description, invite_code)
VALUES
  (jam_id,u1,'Libri di Settembre','Il nostro club di lettura mensile','settembre'),
  (jam_id2,u2,'Classici del 900','Solo i grandi classici del novecento','novecento')
ON CONFLICT DO NOTHING;

-- ─── 6. JAM MEMBERS ───────────────────────────────────────────────────────────
INSERT INTO public.jam_members (jam_id, user_id, role, joined_at)
VALUES
  (jam_id,u1,'owner',now()-interval'28 days'),
  (jam_id,u2,'member',now()-interval'27 days'),
  (jam_id,u3,'member',now()-interval'25 days'),
  (jam_id,u4,'member',now()-interval'20 days'),
  (jam_id,u5,'member',now()-interval'18 days'),
  (jam_id2,u2,'owner',now()-interval'25 days'),
  (jam_id2,u1,'member',now()-interval'24 days'),
  (jam_id2,u3,'member',now()-interval'22 days')
ON CONFLICT DO NOTHING;

-- ─── 7. SHARED HIGHLIGHTS IN JAM ──────────────────────────────────────────────
INSERT INTO public.jam_highlights (jam_id, highlight_id, shared_by, shared_at)
VALUES
  (jam_id,h1a,u1,now()-interval'25 days'),
  (jam_id,h2a,u2,now()-interval'20 days'),
  (jam_id,h3a,u3,now()-interval'15 days'),
  (jam_id,h4a,u4,now()-interval'10 days'),
  (jam_id,h5a,u5,now()-interval'5 days'),
  (jam_id2,h1b,u1,now()-interval'22 days'),
  (jam_id2,h2b,u2,now()-interval'17 days')
ON CONFLICT DO NOTHING;

-- ─── 8. FOLLOWS between dummy users ───────────────────────────────────────────
INSERT INTO public.follows (follower_id, following_id, created_at)
VALUES
  (u1,u2,now()-interval'25 days'),(u1,u3,now()-interval'24 days'),
  (u2,u1,now()-interval'23 days'),(u2,u4,now()-interval'22 days'),
  (u3,u1,now()-interval'20 days'),(u3,u5,now()-interval'18 days'),
  (u4,u2,now()-interval'15 days'),(u5,u1,now()-interval'10 days'),
  (u5,u3,now()-interval'8 days')
ON CONFLICT DO NOTHING;

RAISE NOTICE 'Seed completato: 5 utenti, 7 libri, 7 highlights, 2 jam.';
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASSO 2: Collegati agli utenti dummy (esegui separatamente)
-- Vai su Authentication → Users, copia il tuo UUID, sostituiscilo qui sotto.
-- ─────────────────────────────────────────────────────────────────────────────
/*
DO $$
DECLARE
  me      uuid := 'IL-TUO-UUID-QUI';
  u1      uuid := 'a1000001-aaaa-4000-8000-000000000001';
  u2      uuid := 'a1000001-aaaa-4000-8000-000000000002';
  u3      uuid := 'a1000001-aaaa-4000-8000-000000000003';
  u4      uuid := 'a1000001-aaaa-4000-8000-000000000004';
  u5      uuid := 'a1000001-aaaa-4000-8000-000000000005';
  jam_id  uuid := 'de000001-aaaa-4000-8000-000000000001';
  jam_id2 uuid := 'de000001-aaaa-4000-8000-000000000002';
BEGIN
  INSERT INTO public.follows (follower_id, following_id)
  VALUES (me,u1),(me,u2),(me,u3),(me,u4),(me,u5)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.jam_members (jam_id, user_id, role)
  VALUES (jam_id,me,'member'),(jam_id2,me,'member')
  ON CONFLICT DO NOTHING;
END $$;
*/
