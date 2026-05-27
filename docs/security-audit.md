# Security audit — 2026-05-27

Scope: Supabase database (RLS policies, RPC functions, views), Flutter client
code (secret handling, URL launching, content rendering), Edge Functions.

## Summary

| Sev | Issue | Status |
|-----|-------|--------|
| **P0** | `create_notification()` callable by any authenticated user — phishing/spam vector | **Fixed** (migration 028) |
| **P0** | `create_group_conversation()` lets attacker add arbitrary users without consent | **Fixed** (migration 028) |
| P1 | View `books_finished_v` had implicit (non-invoker) security | **Fixed** (migration 028) |
| P1 | No length caps on user-content columns (storage abuse) | **Fixed** (migration 028) |
| P2 | 3 dead tables (`clippings_imports`, `tags`, `highlight_tags`) with RLS but no policies | Documented; safe to drop later |
| P3 | Anon key hardcoded in `lib/main.dart` | Acceptable (Supabase anon keys are public by design — RLS is the protection) |

No issues found in: SQL injection (all queries parametrized via PostgREST/Supabase client), XSS (no HTML/Markdown rendering of user content), URL injection (all `launchUrl` calls hit hardcoded domains or use `Uri.encodeQueryComponent`).

---

## Detailed findings

### [P0] create_notification() phishing vector

**File**: pre-existing notifications migration (now superseded by 028).

**Issue**: The function was marked `SECURITY DEFINER` with `EXECUTE` available
to `PUBLIC` (which `authenticated` inherits). Any logged-in user could call:

```dart
await supabase.rpc('create_notification', params: {
  'p_user_id': victim_uuid,
  'p_type': 'system',
  'p_title': 'Your account has been suspended',
  'p_body': 'Tap here to verify: https://attacker.example',
});
```

Result: arbitrary phishing notifications delivered to any user.

**Fix** (migration 028):
- Added runtime guard inside the function: throws if `current_user` is
  `authenticated` or `anon`.
- Added `SET search_path = 'public'` to prevent search-path hijack.
- Revoked `EXECUTE` from `PUBLIC`, `anon`, `authenticated`.

Result: only triggers (which call as the table owner) and `service_role`
(Edge Functions with the service key) can create notifications.

### [P0] create_group_conversation() unsolicited DM vector

**Issue**: Function accepted an arbitrary array of UUIDs and inserted them as
conversation members with no consent / relationship check. Attacker could:

```dart
await supabase.rpc('create_group_conversation', params: {
  'p_member_ids': [random_user_1, random_user_2, ...],
  'p_group_name': 'Spam group',
});
```

And then `messages.insert` to broadcast.

**Fix** (migration 028): added a relationship guard requiring the creator
to **mutually follow** every proposed member (same trust threshold the app
already uses for direct DMs). Self is exempt. Limit of 100 members per
group added. Also moved to `SECURITY DEFINER` with explicit `search_path`.

### [P1] View `books_finished_v` — security_invoker

Supabase advisor flags views without explicit `security_invoker = true`.
The underlying `reading_sessions` table has RLS that already scopes to
the calling user, so practical impact was nil — but advisor compliance
matters for App Store / GDPR audit.

**Fix**: `alter view ... set (security_invoker = true)`.

### [P1] Length caps on user-content columns

No upper bound on `posts.body`, `post_comments.content`,
`book_notes.notes`, `messages.content`. An abusive client could insert
megabyte-sized rows to fill storage / break UI rendering.

**Fix** (migration 028): added `CHECK` constraints — 4000 chars for posts
& messages, 2000 for comments, 10000 for book notes. All values are
generous enough not to constrain legitimate use.

### [P2] Dead tables

`clippings_imports`, `tags`, `highlight_tags` have RLS enabled but **zero
policies** → deny-by-default for all roles, including authenticated. They
are not referenced anywhere in `lib/`. No data leakage risk; just dead
schema.

**Recommendation**: drop in a future migration after confirming no other
service references them.

### [P3] Anon key in source

```dart
const _supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIs...';
```

This is **by design** — Supabase anon keys are JWTs with role `anon` and
limited claims, equivalent to public API keys. The protection model is
that RLS policies gate every table. Verified the key payload encodes
only `role: anon` (no service role leak).

No fix needed. Same model as Firebase web SDK keys.

---

## Things explicitly checked and OK

- **No SQL injection**: all queries go through Supabase client / PostgREST
  which parametrizes. No raw string concatenation in any query.
- **No XSS surface**: no `Html()` / `Markdown()` widgets rendering user
  content. The only HTML output is via `export_service` which serializes
  to a file for download (and uses `htmlEscape` on values).
- **URL launching safe**: all `launchUrl` calls hit either hardcoded
  domains (privacy policy, Amazon search, OpenMeteo) or use
  `Uri.encodeQueryComponent` on user-controlled fragments (Amazon book
  search). No raw URL injection possible.
- **Auth flows**: email + password via Supabase Auth (handles its own
  hashing/rate-limiting). No custom auth.
- **Edge Functions**: `widget-highlight` reads via service role server-side
  (no key exposed to client), accepts only validated query params with
  `clampInt` / `sanitizeWeather` bounds.

## Follow-ups for later

1. Drop the 3 dead tables once confirmed unused by any background worker.
2. Add a rate-limit on `posts` / `messages` insert (currently unlimited)
   via either a trigger or Edge Function front-door.
3. Consider rotating the anon key (current `iat` is 2026-04-22, `exp` is
   2036-04-22) — long expiry is fine for an anon key but you should rotate
   if you ever suspect leakage.

Last audited: 2026-05-27. Re-run after any DDL change (`get_advisors` MCP
or this audit's queries).
