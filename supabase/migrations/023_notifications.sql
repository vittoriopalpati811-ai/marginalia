-- ─── Jam 2.0: In-app Notifications ───────────────────────────────────────────
--
-- Central notifications table for in-app alerts.
-- Push notifications (APNs) are sent by the Supabase Edge Function
-- `supabase/functions/send-push-notification/` which reads device_tokens.
--
-- SETUP REQUIRED by the developer:
--   1. Add APNs auth key to Supabase secrets:
--      supabase secrets set APNS_TEAM_ID=XXXXXXXXXX
--      supabase secrets set APNS_KEY_ID=XXXXXXXXXX
--      supabase secrets set APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
--      supabase secrets set APNS_BUNDLE_ID=com.yourcompany.marginalia
--   2. Deploy the edge function:
--      supabase functions deploy send-push-notification
--   3. Register device tokens from the Flutter app via the endpoint.
--
-- Run in Supabase SQL Editor.

-- ─── Device tokens (for push notifications) ──────────────────────────────────

create table public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  token       text not null,
  platform    text default 'ios' not null,  -- 'ios' | 'android'
  created_at  timestamptz default now() not null,
  unique(user_id, token)
);

create index device_tokens_user_idx on public.device_tokens(user_id);

-- ─── In-app notifications ─────────────────────────────────────────────────────

create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  type        text not null,     -- 'jam_new_highlight' | 'jam_new_member' |
                                 -- 'jam_book_vote' | 'jam_poll_new' |
                                 -- 'jam_challenge_update'
  title       text not null,
  body        text not null,
  data        jsonb,             -- arbitrary payload, e.g. {"jam_id": "...", "highlight_id": "..."}
  jam_id      uuid references public.jams(id) on delete cascade,
  is_read     boolean default false not null,
  created_at  timestamptz default now() not null
);

create index notifications_user_idx     on public.notifications(user_id);
create index notifications_unread_idx   on public.notifications(user_id, is_read)
  where not is_read;
create index notifications_created_idx  on public.notifications(user_id, created_at desc);

-- ─── RLS ──────────────────────────────────────────────────────────────────────

alter table public.device_tokens  enable row level security;
alter table public.notifications   enable row level security;

-- Device tokens: each user manages their own rows
create policy "device_tokens_all" on public.device_tokens
  for all using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Notifications: users read/update only their own
create policy "notifications_select" on public.notifications
  for select using (auth.uid() = user_id);

create policy "notifications_update" on public.notifications
  for update using (auth.uid() = user_id);

-- Service role inserts (Edge Function writes notifications on behalf of users)
create policy "notifications_service_insert" on public.notifications
  for insert with check (true);   -- Edge Functions use service-role key

-- ─── Helper: create notification + trigger push ───────────────────────────────
--
-- Call this from other Supabase triggers or Edge Functions:
--   select create_notification(user_id, 'jam_new_highlight', 'Title', 'Body', '{"jam_id":"..."}', jam_id);

create or replace function public.create_notification(
  p_user_id  uuid,
  p_type     text,
  p_title    text,
  p_body     text,
  p_data     jsonb default null,
  p_jam_id   uuid default null
)
returns uuid
language plpgsql security definer
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (user_id, type, title, body, data, jam_id)
  values (p_user_id, p_type, p_title, p_body, p_data, p_jam_id)
  returning id into v_id;
  return v_id;
end;
$$;

-- ─── Realtime ─────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.notifications;
