-- ─── Mark conversation read — server-side RPC ──────────────────────────────
--
-- Root cause discovered while debugging "badge doesn't clear without
-- refresh": the original client-side update on conversation_members
-- silently failed because migration 014 only added SELECT + INSERT RLS
-- policies, never UPDATE. PostgREST returned 204 (no rows affected)
-- and the client's try-catch swallowed the absence of an error,
-- leaving last_read_at unchanged.
--
-- Fix path chosen: a SECURITY DEFINER RPC. This gives us two wins:
--   • Bypasses the missing UPDATE policy without weakening RLS for
--     other operations (we don't want generic UPDATEs allowed).
--   • Uses server-side now(), eliminating any client clock skew that
--     could make last_read_at < message.created_at and leave the
--     conversation looking unread even after marking.

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ts  timestamptz := now();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Defensive: only mark if the caller is actually a member.
  -- Without this, a malicious client could mark someone else's read state.
  if not exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation_id
      and user_id = uid
  ) then
    raise exception 'not a member of this conversation';
  end if;

  update public.conversation_members
  set last_read_at = ts
  where conversation_id = p_conversation_id
    and user_id = uid;

  return ts;
end;
$$;

grant execute on function public.mark_conversation_read(uuid)
  to authenticated;
