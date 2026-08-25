-- ─── The welcome email for the waiting list ─────────────────────────────────
--
-- Hung off the ROW, not off the landing page's JavaScript. The page inserts
-- straight into `waitlist_signups` with the anon key, so a fetch fired from
-- there would cover that one form only — and would die silently the day the
-- page unloads mid-request, or somebody signs up by another route.
--
-- pg_net QUEUES the call rather than making it, so the insert commits whatever
-- the email provider is doing. Somebody leaving their address must never see an
-- error because a mail server was slow; the worst case here is a missing
-- welcome, never a lost subscriber. The function itself returns 200 with
-- {"skipped":"no api key"} until RESEND_API_KEY is set, so the plumbing could
-- be verified end-to-end before the key existed — and it was.
--
-- No duplicate welcomes: `waitlist_signups_email_key` is unique on
-- lower(email), so a repeat sign-up never becomes a row and never fires this.
create extension if not exists pg_net with schema extensions;

-- The shared secret that lets the edge function tell this trigger apart from
-- anyone who finds its URL. Seeded out of band, never in this file:
--   insert into public.admin_secrets (name, value)
--   values ('waitlist_hook_token', encode(gen_random_bytes(24),'hex'))
--   on conflict (name) do nothing;

create or replace function public.notify_waitlist_welcome()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_catalog'
as $$
declare
  hook_token text;
begin
  select value into hook_token
  from public.admin_secrets where name = 'waitlist_hook_token';

  if hook_token is null then
    return new;  -- not configured; never block the sign-up
  end if;

  perform net.http_post(
    url     := 'https://ibucvloawkfwobaelwbr.supabase.co/functions/v1/waitlist-welcome',
    headers := jsonb_build_object(
                 'content-type', 'application/json',
                 'x-hook-token', hook_token),
    body    := jsonb_build_object('email', new.email, 'locale', new.locale)
  );
  return new;
exception when others then
  -- A failed notification is not worth losing a subscriber over.
  return new;
end $$;

drop trigger if exists waitlist_welcome_trigger on public.waitlist_signups;
create trigger waitlist_welcome_trigger
  after insert on public.waitlist_signups
  for each row execute function public.notify_waitlist_welcome();
