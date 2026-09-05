-- ─── The welcome email has to know WHICH list you joined ────────────────────
--
-- 082 sends `{email, locale}` to `waitlist-welcome`, whose copy promises "when
-- there's a place for you, one email". That is the right thing to say to
-- somebody who joined the waiting list on the landing page. It is the wrong
-- thing to say to somebody who just volunteered to be an Android tester on
-- /android/: they are not waiting for a place, they are waiting for an
-- invitation link, and telling them to sit tight is how a volunteer quietly
-- stops being one.
--
-- `waitlist_signups.source` already records where the row came from
-- ('landing' or 'android-tester'). It just never reached the function. This
-- adds it to the payload; the branch on the other end lives in
-- supabase/functions/waitlist-welcome/index.ts.
--
-- Everything else is byte-for-byte 082: same security definer, same search
-- path, same swallow-everything exception block. A failed notification must
-- never cost somebody their row.
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
    body    := jsonb_build_object(
                 'email',  new.email,
                 'locale', new.locale,
                 'source', new.source)
  );
  return new;
exception when others then
  -- A failed notification is not worth losing a subscriber over.
  return new;
end $$;
