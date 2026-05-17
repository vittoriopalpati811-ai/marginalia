-- Marginalia — Seed posts dummy
-- Esegui DOPO seed_dummy_users.sql e DOPO migration 006.
-- I post usano gli UUID dei dummy users già inseriti.
-- Idempotente grazie a ON CONFLICT DO NOTHING.

do $$
declare
  uid_marco  uuid;
  uid_sofia  uuid;
  uid_luca   uuid;
  uid_elena  uuid;
  uid_davide uuid;
  h1 uuid; h2 uuid; h3 uuid; h4 uuid; h5 uuid;
begin
  -- Recupera UUIDs dummy users
  select id into uid_marco  from auth.users where email = 'marco.rossi@marginalia.demo';
  select id into uid_sofia  from auth.users where email = 'sofia.bianchi@marginalia.demo';
  select id into uid_luca   from auth.users where email = 'luca.ferrari@marginalia.demo';
  select id into uid_elena  from auth.users where email = 'elena.conti@marginalia.demo';
  select id into uid_davide from auth.users where email = 'davide.russo@marginalia.demo';

  -- Recupera qualche highlight da usare nei post
  select id into h1 from public.highlights where user_id = uid_marco  limit 1;
  select id into h2 from public.highlights where user_id = uid_sofia  limit 1;
  select id into h3 from public.highlights where user_id = uid_luca   limit 1;
  select id into h4 from public.highlights where user_id = uid_elena  limit 1;
  select id into h5 from public.highlights where user_id = uid_davide limit 1;

  -- Post di Marco
  insert into public.posts (id, user_id, body, highlight_id, created_at) values
    (
      'a1000001-0000-0000-0000-000000000001',
      uid_marco,
      'Ho finito "Il nome della rosa" stanotte. Ogni volta che lo rileggo trovo qualcosa di nuovo. Umberto Eco era un genio.',
      null,
      now() - interval '2 hours'
    ),
    (
      'a1000001-0000-0000-0000-000000000002',
      uid_marco,
      'Questo passaggio mi ha fatto fermare a riflettere per almeno dieci minuti.',
      h1,
      now() - interval '1 day'
    )
  on conflict (id) do nothing;

  -- Post di Sofia
  insert into public.posts (id, user_id, body, highlight_id, created_at) values
    (
      'a1000001-0000-0000-0000-000000000003',
      uid_sofia,
      'Sto leggendo "Americanah" di Chimamanda Ngozi Adichie. Non riesco a smettere. È uno di quei libri che ti cambiano il modo di vedere le cose.',
      null,
      now() - interval '5 hours'
    ),
    (
      'a1000001-0000-0000-0000-000000000004',
      uid_sofia,
      'Condivido questo highlight perché descrive esattamente come mi sono sentita durante il lockdown.',
      h2,
      now() - interval '2 days'
    )
  on conflict (id) do nothing;

  -- Post di Luca
  insert into public.posts (id, user_id, body, highlight_id, created_at) values
    (
      'a1000001-0000-0000-0000-000000000005',
      uid_luca,
      'Tre libri in parallelo questa settimana. La lettura lenta sta diventando un lusso che non posso permettermi, ma non riesco a smettere di iniziarne di nuovi.',
      null,
      now() - interval '3 hours'
    ),
    (
      'a1000001-0000-0000-0000-000000000006',
      uid_luca,
      'Seneca che parla del tempo come se scrivesse nel 2024. Incredibile.',
      h3,
      now() - interval '3 days'
    )
  on conflict (id) do nothing;

  -- Post di Elena
  insert into public.posts (id, user_id, body, highlight_id, created_at) values
    (
      'a1000001-0000-0000-0000-000000000007',
      uid_elena,
      'Prima riunione della Jam "Classici del 900" domani sera. Ho riletto "La metamorfosi" e ho mille cose da dire.',
      null,
      now() - interval '6 hours'
    ),
    (
      'a1000001-0000-0000-0000-000000000008',
      uid_elena,
      'Questo di Calvino è uno dei passaggi che preferisco in assoluto. La leggerezza come valore letterario.',
      h4,
      now() - interval '4 days'
    )
  on conflict (id) do nothing;

  -- Post di Davide
  insert into public.posts (id, user_id, body, highlight_id, created_at) values
    (
      'a1000001-0000-0000-0000-000000000009',
      uid_davide,
      'Marginalia mi ha fatto riscoprire 40 highlight che avevo completamente dimenticato. È come ricevere lettere da se stessi del passato.',
      null,
      now() - interval '1 hour'
    ),
    (
      'a1000001-0000-0000-0000-000000000010',
      uid_davide,
      'Pavese. Sempre Pavese.',
      h5,
      now() - interval '5 days'
    )
  on conflict (id) do nothing;

end $$;
