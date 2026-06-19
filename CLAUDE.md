# Scripta — project guide & session handoff

> iOS-first Flutter app that turns Kindle highlights into a daily ritual:
> smart home-screen widgets, spaced-repetition "Ripasso", reading social
> circles ("Jam"), and a reading tracker. Formerly **Marginalia** (the repo,
> bundle id `io.marginalia.app`, and folder name still say "Marginalia" — only
> the user-facing brand is **Scripta**).

This file is the **single source of truth for a new AI session**. Read it fully
before touching anything. It is kept accurate; if you change how the project
works, update this file in the same commit.

---

## 0. STANDING FOUNDER INSTRUCTIONS (always in effect — verbatim)

- **"fai tutto tu, non chiedermi niente"** — do everything autonomously, don't
  ask. Don't stop to confirm; pick the sensible option and proceed.
- **"prima iphone poi apk"** — iOS is the priority. Always ship the iOS build
  first, then rebuild the Android APK.
- Production-ready, **zero-bug, no "AI slop"**. Verify before reporting ("prima
  di rimandarmi le cose controlla che funzionino") — claims must be backed by
  `flutter analyze` + tests + (where possible) live DB checks.
- **English-predominant** UI; founder communicates in Italian.
- **Ultracode is ON**: use the Workflow tool for substantive tasks (parallel
  investigation + adversarial verification). Solo only for trivial edits.
- When a build is green, send a recap as a **Gmail draft** (not auto-sent) to
  **vittoriopalpati811@gmail.com**.

Founder develops on **Windows, no Mac**. Everything must build without a Mac.

---

## 1. CURRENT STATUS (2026-06-11)

- **Live in production.** ~87 users, ~1115 highlights, ~215 posts (real usage).
- **App is FREE** — all paywall/premium code was removed (see §6). No gates.
- Latest green iOS build: **TestFlight run #72, commit `1700007`** (build number
  = unix timestamp). Latest APK: **`Scripta_1.1.0.apk` on the Desktop**.
- Active branch: **`feat/profile-ui-privacy`** (this is what CI builds — see §3).
- The free-app + admin console + Apple/Google sign-in + animated-onboarding batch
  is **SHIPPED green on both platforms** (iOS #72 + APK rebuilt).
- **Big founder-feedback batch (2026-06-11)** — auth-loop fix + login restyle,
  like-count fix + author hide-toggle, jam RLS/poll/palette/avatars/flame,
  visited-profile rebuild + private/public + remove-follower, custom-cover
  propagation + centred upload spinner + add-to-favourites, frase save-fix +
  story-cover, instant post publish, no tab/back animations, **Ripasso 2.0**
  (quiz merged in, end summary, once-a-day, day/week/month jam leaderboard with
  titles), chat header restyle, Scripta logo in iOS widgets, branded reset page
  + email templates, old buggy web build removed. Migrations `061–063`. All
  green (analyze 23/0, tests 45/45) + adversarially verified. See §9.

---

## 2. STACK (current, accurate)

- **Flutter 3.22.0** / Dart. iOS primary; Android secondary (free via Flutter).
  Local dev/test on Windows desktop + Chrome.
- **flutter_riverpod 2.x**, manual providers (no riverpod_generator).
- **Isar 3.x** local DB, offline-first. ⚠️ `*.g.dart` are gitignored and
  regenerated: `dart run build_runner build --delete-conflicting-outputs`.
- **Supabase** (Postgres + RLS + Storage + Realtime + Edge Functions).
  Project ref **`ibucvloawkfwobaelwbr`**. URL + anon key are committed in
  `lib/main.dart` (anon key is public by design).
- **go_router** ShellRoute for the bottom nav.
- **Amazon Kindle sync**: `webview_flutter` + JS injection on
  `read.amazon.com/.../notebook` (same approach as Readwise). Not supported on
  Windows desktop — use mock data locally.
- **google_fonts** (EB Garamond serif for editorial text, Manrope for UI).
- **flutter_animate 4.x** for motion; `lib/core/motion/airbnb_motion.dart` has
  the shared duration/curve constants (fast 180 / standard 280 / emphasis 380 /
  longForm 520; easeOutQuart enter).

### Conditional (web vs native) files — IMPORTANT
Several modules have `_native.dart` (iOS/Android, Isar/home_widget) and
`_web.dart` (Chrome stub) variants behind a conditional `export`:
`review_provider`, `widget_service`. **The analyzer resolves the `_web` stub by
default**, so if you add a field/method used by shared UI you MUST mirror it in
BOTH variants or `flutter analyze` breaks with "undefined getter". (Burned on
this twice — see §7.)

---

## 3. BUILD & SHIP PIPELINE (exact)

### iOS → TestFlight (no Mac)
- GitHub Actions: `.github/workflows/ios-testflight.yml`. Triggers on push to
  **`feat/profile-ui-privacy` | main | master**. Public repo → free macOS
  runners. Uses Codemagic's open-source `codemagic-cli-tools` for signing +
  `app-store-connect publish` (internal TestFlight, no Beta review).
- Build number = unix timestamp. App display name forced to **Scripta**
  (CFBundleDisplayName **and** CFBundleName via PlistBuddy).
- `flutter create --platforms=ios` regenerates the iOS shell each build, so the
  widget/watch Xcode targets are re-injected by `ios/scripts/add_widgets_extension.rb`
  + `add_watch_targets.rb`. **CI now FAILS if injection fails or if the widget
  `.appex` is missing from the IPA** (added this batch — an appex-less IPA
  silently freezes every home-screen widget).
- ⚠️ **Flaky-upload lesson**: a build can compile the IPA fine and fail ONLY at
  "Publish to TestFlight (internal)" (altool transient). **Re-push (fresh build
  number) fixes it** — it is NOT a code problem. Verify *where* it failed before
  assuming a code bug.

### Monitoring CI from Windows (no `gh` CLI installed!)
The repo is **public**, so poll the Actions API unauthenticated:
`https://api.github.com/repos/vittoriopalpati811-ai/marginalia/actions/runs?branch=feat/profile-ui-privacy&per_page=3`
Pattern that works well: a PowerShell `run_in_background` loop that polls every
45s and exits when the run for your SHA is `completed`, printing the conclusion.
To find WHY a run failed: `…/actions/runs/<id>/jobs` → inspect `steps[].conclusion`.

### Android APK
- Port lives at **`../Marginalia_ANDROID`** (sibling of `Marginalia/`).
- Sync: `robocopy <src>\lib <dst>\lib /MIR` (exit codes 0–7 = success). `pubspec`,
  `assets`, launcher-icons config are already in sync; the port keeps its OWN
  `flutter_launcher_icons.yaml` (android:true) — don't overwrite it. For a
  lib-only change, copying just the changed files is enough.
- Build env (from `Marginalia_ANDROID/run_android.ps1`):
  - JDK17 `C:\Users\User\Android\jdk17`, SDK `C:\Users\User\Android\Sdk`
  - `$env:JAVA_HOME`/`ANDROID_SDK_ROOT`/`ANDROID_HOME` then
    `flutter build apk --release`.
  - Kotlin "incompatible metadata 1.9.0 vs 1.7.1" lines are **non-fatal**
    warnings; the build still produces `app-release.apk` (~72 MB). First Gradle
    run on Windows can flake → re-run.
- Deliver to **`C:\Users\User\Desktop\Scripta_1.1.0.apk`**.

### Tooling paths (NOT on PATH — use absolute)
- Flutter: `C:\Users\User\AppData\Local\flutter-3.22.0\bin\flutter.bat`
- Run flutter from inside `Marginalia/` (working dir is the PARENT
  `Progetto 1/`). `gh` and `flutter` are NOT on PATH.
- Commit messages: PowerShell here-strings mangle special chars → write the
  message to a temp file and `git commit -F <file>`.
- `flutter analyze` baseline = **23 issues, 0 errors** (pre-existing infos +
  unnecessary-null-assertion warnings in profile/social files). "Back to 23, 0
  errors" = clean. `flutter test` = **45 tests, all pass**.

---

## 4. ARCHITECTURE MAP (where things live)

- `lib/main.dart` — bootstrap gate (optional subsystems are timeout-bounded so
  startup never hangs), Supabase init, Sentry (DSN via `--dart-define`, CI
  secret only).
- `lib/app.dart` — `ScriptaApp`, go_router routes, the **bottom nav**
  (`_ScaffoldWithNav` + `_LiquidGlassNavBar`): liquid-glass blur bar with a
  sliding sage indicator pill, and a direction-aware page transition (read
  `_direction` per-frame in the transitionBuilder — see §7).
- `lib/core/theme.dart` — `ScriptaColors` (sage `primary 0xFFC0CFB2`, cream
  `background/surfaceElevated`, `ink/inkMuted/inkFaint`, `sienna*`, red
  `0xFFB94A41`), `ScriptaDecorations`, `ScriptaTextStyles`.
- `lib/core/services/supabase_service.dart` — the big Supabase wrapper (auth,
  covers, jams, push triggers, `markReviewCompleted` RPC call…).
- `lib/features/`: `library/` (LibraryScreen, book_detail), `social/`
  (SocialScreen=Jam, feed_tab), `messages/`, `profile/`, `review/` (Ripasso),
  `quiz/`, `search/` (=Persone user search), `onboarding/`, `auth/`,
  `settings/`, `widget/`, `wrapped/`, `stats/`.
- `lib/core/branding/scripta_mark.dart` — **`ScriptaMark`** widget = the brand
  logo (`assets/brand/scripta_mark.png`, layered cream→sage cards + red bookmark).
  Single source for the badge everywhere (share cards, onboarding, etc.).
  The app icon comes from `assets/icon/app-icon.png` via flutter_launcher_icons.
- **Logo (refreshed 2026-06-19).** Master = the founder's `logo iphone.png`
  (4096², glassy 3-layer card + red bookmark) on the Desktop. Everything is
  derived from it: `app-icon.png` (opaque square, card fills frame, CI runs
  flutter_launcher_icons from it), `scripta_mark.png` (transparent badge, white
  bg flood-filled away), the Watch app icon (`ios/MarginaliaWatch/Assets.xcassets/
  AppIcon.appiconset/AppIcon.png`), and `docs/assets/*` (favicons/og/hero). The
  iOS **widget + Watch** logo is no longer drawn in SwiftUI — it's the same PNG
  embedded as a **base64 string** in `MarginaliaWidgets.swift` /
  `MarginaliaWatchApp.swift` (`scriptaLogoPNGBase64` → `UIImage`), so the
  per-build CI target regeneration can never drop it (no asset-catalog needed).
  To change the logo: drop a new master, re-run the derivation, re-embed base64.

---

## 5. BACKEND (Supabase) — what's there

- Storage buckets: `book-covers` (public-flag read, **no listing** — see
  migration `060`; owner write by `userId/` prefix),
  `avatars`, `covers`, `jam-covers`, `post-images`, `comment-images`,
  `message-images`, `clippings`.
- Per-user covers: table **`user_book_covers`** (PK `(user_id, book_key)`,
  `book_key = 'title|author'` lowercased), public-read RLS. This is the single
  source of truth for custom covers shown everywhere + to profile visitors.
- Ripasso → Jam: tables `jam_ripasso_results`, `jam_quiz_results`
  (unique `(jam_id, user_id, completed_on)`). The leaderboard reads
  `profiles.review_streak/review_best_streak/last_reviewed_on`.
  **RPC `mark_review_completed(p_cards int)`** (migration `059`) atomically
  bumps the profile streak AND upserts a `jam_ripasso_results` row for every jam
  the user is in (member OR owner), Europe/Rome day boundary. Called per graded
  card. This replaced fragile unawaited client mirrors that left streaks at 0.
- Edge functions: `send-push-notification` (APNs, server-derives recipient),
  `recommend-books`, `semantic-search`, `pick-daily-highlight`, `moderate-image`,
  `parse-clippings`, and **`admin-metrics`** (founder console — see §8).
  ⚠️ **`moderate-image` + `admin-metrics` are deployed-only — NOT in
  `supabase/functions/`** (source drift). `moderate-image` is a Guideline-1.2
  safety feature; pull its source into the repo so a from-repo redeploy can't
  silently drop image moderation.
- **Rate limiting (security hardening, 2026-06-11):** `check_rate_limit(action,
  max,window)` (mig 039) RAISES when a caller exceeds the budget. Live coverage:
  per-write antispam triggers on posts/comments/messages/follows/jam-comments
  (039) PLUS jams/reviews/jam-content (mig **064**), and a per-user throttle
  inside the expensive edge functions. **All four are now DEPLOYED with the
  per-user throttle** (semantic-search + pick-daily-highlight via MCP;
  recommend-books + send-push-notification via the dashboard Code editor,
  2026-06-11 — paste the repo source into Functions → Code → Deploy when the
  files are too large to hand-inline through the MCP). Mig 064 also
  adds length CHECKs on every user-text column and locks `amazon_sync_scripts`
  writes to service-role only.
- Migrations live in `supabase/migrations/NNN_*.sql`. Latest = `071`. When you
  apply something live via MCP, **also write the migration file** (drift bit us
  once — the live RPC existed but no migration captured it). Recent: `068`
  jam_highlights DELETE, `069` jam_poll_candidates UPDATE, `070` jams.theme_color,
  `071` captures `is_jam_member_or_owner` (was live-only — found by the audit).
- **Security audit (2026-06-17, hack test):** 13-agent penetration-style audit
  (RLS / edge fns / secrets / storage / auth / input) → **0 live-exploitable
  vulns**. 7 findings already fixed & re-verified live (notifications-insert 032,
  storage-upload 066, jam-cover IDOR is member-scoped, reviews authenticated-only
  044, jam_highlights-delete 068, jam_poll_candidates-update 069, RPC anon-grants
  043); 1 migration-drift fixed (`is_jam_member_or_owner` → mig 071); 1 residual
  **decision pending the founder**: profile privacy is still APP-LEVEL/soft (see
  §9 note) — a hard-RLS pass is feasible but risks breaking feed/search/post-author
  for live users, so do it as a dedicated, tested change only if he asks.
- Supabase MCP tools are available: `execute_sql`, `apply_migration`,
  `list/deploy_edge_function`, etc. Use them to verify live state.

---

## 6. DECISIONS & WHY

- **Swift → Flutter** (2026-05-10): founder is on Windows; Flutter builds iOS in
  cloud CI without a Mac.
- **Codemagic → GitHub Actions** for iOS: Codemagic free tier (500 min) ran out;
  public repo gets free uncapped macOS runners. Same signing CLI, identical IPA.
- **App is FREE / paywall removed** (this batch): purchases were always stubbed
  (RevenueCat key was a placeholder; `purchases_flutter` was disabled because its
  pod failed to compile on the CI Xcode). A visible-but-dead paywall is an App
  Store **Guideline 3.1.1** rejection risk, and the founder decided free for now.
  Deleted the screen, providers, services, route, and all `paywall*` l10n keys.
  There were **no real feature gates** to unlock — the "free tier" text was
  theatre.
- **Apple sign-in rendered FIRST** (before Google) per Apple HIG / Guideline 4.8
  (if you offer third-party login you must offer Sign in with Apple, equally
  prominent). Uses the Supabase OAuth **web flow** (`signInWithOAuth`) — no
  native `sign_in_with_apple`/`google_sign_in` packages, so **no new Apple
  entitlement and no signing risk**; the only prerequisite is dashboard config.
- **Admin metrics = static unlisted page + token-gated edge function**, not an
  in-app screen: zero App Store surface, founder-only, and the token never ships
  in the app binary.
- **Email confirmation via 6-digit OTP** (not magic link): typing a code is more
  reliable on mobile than a Safari deep-link round-trip. The screen
  (`email_otp_screen.dart`) already existed.

---

## 7. FAILED APPROACHES / GOTCHAS (don't repeat)

- **Widget "doesn't update" had TWO causes**: (a) the manual "update widget"
  button in the preview screen was a literal stub (`// In a real build this
  would call…`) that showed success without writing anything — now it really
  pushes via the same pipeline and reports the real error; (b) the App
  Group/kind names must match across Dart (`group.marginalia.widget`,
  `MarginaliaWidget`/`MarginaliaStats`), the Swift extension, and entitlements.
  If widgets still freeze after an update, **remove + re-add the widget** once
  (WidgetKit caches the old timeline).
- **Tab transition left-direction bug**: `_direction` was baked into the
  outgoing page's tween when it first built, so switching to a LEFT tab after a
  RIGHT one slid the wrong way. Fix: read `_direction` per-frame inside an
  `AnimatedBuilder` in the transitionBuilder (now correct both ways).
- **Navbar slider alignment**: `Alignment.x` maps over FREE space (bar − pill),
  so for n slots of width 1/n the slots are at `-1 + 2*i/(n-1)` — divide by
  **(n−1)**, not n (dividing by n mis-centres every non-middle tab).
- **Conditional web stub drift**: see §2 — mirror new state fields in both
  `*_native.dart` and `*_web.dart`.
- **Unawaited streak mirror** left `profiles.review_streak` at 0 → jam Ripasso
  section showed "ancora nessuna serie" even after a completed ripasso. Fixed
  with the server-side RPC.
- **Double-pop risk on auth**: the auth screen listens for `signedIn` to pop
  after social OAuth, but the EMAIL path also pops itself → guard with a
  `_socialFlowInFlight` bool so only the social flow reacts to the event.
- **Isar reads DateTime back as UTC** — always normalise to LOCAL date-only
  before comparing to "today" (a raw `!= today` silently reset streaks daily).
- **PostgrestException in poll vote**: upsert needed `onConflict`.
- **Permanent deletion is prohibited** by safety rules — when cleaning files
  (e.g. old APKs) move to Recycle Bin, never hard-delete.

---

## 8. ADMIN CONSOLE (founder metrics)

- Page: `docs/console-hl0591p7oc/` (unlisted, `noindex`, served at
  **https://get-scripta.app/console-hl0591p7oc/** after the next site deploy —
  `docs/` is the GitHub Pages root, custom domain `get-scripta.app` confirmed
  live). Nothing links to it; the slug is the obscurity layer.
- Auth: a 48-char random token, sent only in the **`x-admin-token` header**
  (header-only after this batch — query-param form was removed so it can't land
  in logs). 403 on mismatch. The token is **NOT in the repo** — it lives only in
  the deployed `admin-metrics` function and in the founder's Desktop file
  (`Scripta — Console e Credenziali.txt`, kept out of git).
- Data: edge fn `admin-metrics` → RPC `admin_metrics_snapshot()` (SECURITY
  DEFINER, EXECUTE granted only to service_role). Returns **aggregate counts
  only — no PII**: users (total/DAU/WAU/MAU/new/push-enabled), 7-day engagement,
  content totals, and computed revenue scenarios (2/5/10% of MAU × €19,99). Each
  metric has an Italian explanation in the UI.
- If asked to rotate the token: change `ADMIN_TOKEN` in the deployed function and
  update the Desktop file.

---

## 9. EXACT NEXT STEPS

1. **Founder-only dashboard toggles** (only the founder can do these — they live
   in his Supabase/Google/Apple accounts; the app code is wired and degrades
   gracefully until then). Step-by-step in the Desktop file
   `Scripta — Console e Credenziali.txt`:
   - Supabase → Auth → Email → enable **Confirm email** (the signup→OTP→onboarding
     flow is now fixed and handles it).
   - **Paste the new Scripta email templates** (Reset Password + Confirm signup)
     from the Desktop file `Scripta — Template email (da incollare su Supabase).html`
     — the old reset email still said "Marginalia" and pointed at the dead web app.
   - Configure **Google** OAuth (redirect
     `https://ibucvloawkfwobaelwbr.supabase.co/auth/v1/callback`).
   - Configure **Apple** OAuth (Services ID + .p8 key).
   - Supabase → Auth → URL Configuration → add redirect
     `io.supabase.flutter://login-callback/`.
2. **Verify social login end-to-end** on a real device once the providers are
   configured (the OAuth web flow + `_socialFlowInFlight` double-pop guard are in;
   the adversarial pass found the email signup/login loop fix SOLID — confirm the
   social deep-link return pops the auth screen on device).
3. **Visual polish pass** on device for the big batch: the auth-screen restyle,
   the rebuilt visited-profile sheet, the Ripasso 2.0 quiz/summary, and the new
   jam leaderboard tabs are logic-verified + analyze/test green, but screenshot
   feedback (the founder's usual loop) may want spacing/tweaks.
4. **`reset-password` page redirect**: `docs/app.html` is the branded reset/confirm
   page served at the SAME `…github.io/marginalia/app.html` URL the old reset
   emails point to, so existing links keep working; once the new email templates
   are pasted, links will point at `get-scripta.app/app.html` too.

### Notes for the next session (gotchas from the 2026-06-11 batch)
- **Ripasso lock is set ONLY at session end** (review_provider_native.dart). It
  used to be set per-graded-card, which replaced the in-flight session with the
  locked summary after the first answer (deck never finished, completion writes
  never ran). Don't reintroduce a per-card lock.
- **`profiles.is_private` gating is APP-LEVEL/soft in v1** (RLS still allows the
  read). The visited profile gates content only when it KNOWS the viewer is not a
  follower (loading/error ⇒ not gated). If you make privacy a real boundary,
  enforce it in RLS too.
- **Gender is a single source**: the Settings "personalization" gender now also
  mirrors to `profiles.gender` (female→f/male→m/unspecified→null) for the
  leaderboard titles. Onboarding also pushes it. Don't add a second selector.
- **`set_jam_cover` RPC** (migration 062): jam photo is now editable by any
  member/owner (was owner-only → 403). Storage policies on `jam-covers` widened
  to members too.

---

## 10. HOW TO WORK HERE (process)

- Pattern that works: **scout (parallel read-only Workflow agents) → implement →
  adversarial-verify (parallel Workflow agents) → analyze+test → ship**. Apply
  the verifier's blocker/warning findings before committing.
- Keep `flutter analyze` at the 23/0 baseline and `flutter test` at 45/45 green
  before every push.
- Don't change `pubspec.yaml` deps or do non-backwards-compatible Supabase schema
  changes without thinking about existing builds/users in production.
- Update this file whenever the build pipeline, branch, backend, or standing
  instructions change.
