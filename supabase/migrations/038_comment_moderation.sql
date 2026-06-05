-- 038_comment_moderation.sql
--
-- Post-owner comment moderation.
--
-- A SINGLE SECURITY DEFINER RPC, `delete_post_comment_as_owner`, lets the
-- OWNER OF A POST delete ANY comment on that post (moderation) — in addition to
-- the existing "delete my own comment" path. NO table/column changes.
--
-- ⚠️ DO NOT APPLY BLINDLY FROM A MIGRATION RUNNER yet — the parent applies this
-- via the Supabase MCP / SQL Editor. It is written to be idempotent
-- (create or replace + guarded grants) so re-running is safe.
--
-- ───────────────────────────────────────────────────────────────────────────────
-- WHY AN RPC INSTEAD OF A CLIENT-SIDE DELETE
-- ───────────────────────────────────────────────────────────────────────────────
--   • The post_comments DELETE policy (migrations 013 + 016) is
--       FOR DELETE USING (user_id = auth.uid())
--     i.e. ONLY the comment's own author may delete it. A post owner trying to
--     delete someone else's comment via the client hits RLS and the statement
--     silently affects 0 rows.
--   • This function runs as the table owner (SECURITY DEFINER), derives the
--     post owner SERVER-SIDE from posts.user_id, and authorises the delete when
--     the caller is EITHER the comment author OR that post owner. The caller
--     cannot moderate comments on a post they do not own, and cannot delete
--     arbitrary comments — the check is enforced here, not trusted from the
--     client. (Same hardening rationale as migration 036's notify RPC.)


-- ═══════════════════════════════════════════════════════════════════════════════
-- delete_post_comment_as_owner(p_comment_id) — author OR post owner may delete
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- Called by SupabaseService.client.rpc(...) from the comments sheet when the
-- current user is the post owner (not the comment author). Deletes the comment
-- (its replies cascade via post_comments.parent_comment_id ON DELETE CASCADE,
-- and comment_likes cascade via their FK). Raises if the caller is neither the
-- comment author nor the post owner, so an unauthorized call fails loudly
-- rather than silently no-op'ing.

create or replace function public.delete_post_comment_as_owner(
  p_comment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_caller       uuid := auth.uid();
  v_comment_user uuid;
  v_post_id      uuid;
  v_post_owner   uuid;
begin
  -- Must be signed in.
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  -- Resolve the comment's author and its post. If the comment is already gone,
  -- treat as a no-op success (idempotent — the desired end state holds).
  select user_id, post_id
    into v_comment_user, v_post_id
    from public.post_comments
   where id = p_comment_id;

  if not found then
    return;
  end if;

  -- Resolve the post owner (the moderator authority).
  select user_id into v_post_owner
    from public.posts
   where id = v_post_id;

  -- Authorise: the comment author may delete their own comment; the post owner
  -- may delete ANY comment on their post.
  if v_caller <> v_comment_user
     and (v_post_owner is null or v_caller <> v_post_owner) then
    raise exception 'Not allowed to delete this comment';
  end if;

  delete from public.post_comments where id = p_comment_id;
end;
$$;

comment on function public.delete_post_comment_as_owner(uuid) is
  'Deletes a post comment when the caller is the comment author OR the owner of '
  'the post the comment belongs to (post-owner moderation). Post owner is '
  'derived server-side from posts.user_id; caller is auth.uid(). Raises if the '
  'caller is neither. Replies/likes cascade via existing FKs.';

-- Signed-in users may call this; anon may not. The function itself enforces
-- that the caller can only delete a comment they authored or that lives on a
-- post they own, so granting it to authenticated is safe.
revoke execute on function public.delete_post_comment_as_owner(uuid) from public;
grant  execute on function public.delete_post_comment_as_owner(uuid) to authenticated;

-- Reload PostgREST schema cache so the new RPC is callable immediately.
notify pgrst, 'reload schema';
