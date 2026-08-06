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
- Latest green iOS build: **TestFlight run #126, commit `ac53ba2`** (automatic
  Kindle sync; build number = unix timestamp). Latest APK: **`Scripta_1.1.0.apk`
  on the Desktop**, rebuilt from the same commit and smoke-tested on the emulator.
  Suite is now **68 tests** (was 45) — `flutter test` green.
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
  **WEB IS NOT A TARGET — do not re-add it.** The `web/` folder was deleted
  (2026-08-05) on the founder's instruction: "delistala, non deve essere
  accessibile da altri". `flutter build web` now fails at once, which is the
  point — the preview can no longer be published by accident. It had in any case
  been uncompilable since 2026-06-02, when the Kobo importer pulled in `sqlite3`
  (needs `dart:ffi`, absent in a browser). Verified before removal that nothing
  was live: no Flutter bundle on get-scripta.app (every such path returns the
  landing page, not JS) and `…github.io/marginalia/main.dart.js` is a 404.
  ⚠️ The `*_web.dart` conditional stubs STAY — the analyzer resolves those by
  default (see below), so deleting them would break `flutter analyze`.
  Local dev/test on Windows: use the Android emulator.
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
  **It runs BY ITSELF** (2026-08-05, founder: "a me non compila automaticamente
  il myclippings… rendi tutto più automatico"). Two halves:
  `core/services/kindle_auto_sync.dart` owns the WHEN (a `StateNotifier`: after
  the first manual sync the device is `connected`; opening or resuming the app
  re-syncs if the last run is older than `kKindleSyncInterval` = 6h), and
  `features/library/kindle_sync_host.dart` owns the HOW (a 1×1, opacity-0,
  pointer-ignoring WebView mounted in the app shell, built ONLY while a sync is
  in flight, 90s watchdog refreshed by each progress message). Safe unattended
  because the import is idempotent, the Amazon cookie outlives restarts, and an
  expired session fails SILENTLY into a `needsRelogin` flag that the Settings
  Kindle row (`_KindleTile`) surfaces — a background job must never hijack the
  screen. ⚠️ The host is a `Positioned` child of the shell `Stack` **on
  purpose**: a Stack sizes to its largest NON-positioned child, so mounting it
  loose collapsed the whole shell and the app booted to a blank cream screen.
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

### Android → Google Play (release, 2026-06-26)
- Play needs an **App Bundle (`.aab`)**, not an APK, and a **real upload key**.
  `Marginalia_ANDROID/android/app/build.gradle` now reads a release
  `signingConfig` from a gitignored `android/key.properties` (template:
  `android/key.properties.example`) and **falls back to the debug key** if it's
  absent (so dev `flutter run --release` still works). `targetSdk = 35` (Play
  mandate since 2025-08-31; compileSdk already 35).
- The founder creates the upload keystore **once** with `keytool` and fills
  `key.properties` — I do NOT create/own his signing key or enter passwords.
- Build the bundle with **`Marginalia_ANDROID/build_appbundle.ps1`** (does
  `flutter clean` + `flutter build appbundle --release`, copies
  `Scripta.aab` to the Desktop). Verified build = **35.4 MB**.
- Full publication handoff (keystore steps, Play Console, Data Safety, Health
  Connect declaration text, store copy, iOS final steps) lives in
  **`Desktop/Scripta/PUBBLICAZIONE - Play Store + ultimi passi App Store.md`**.
  Play assets (512 icon + 1024×500 feature graphic) in
  `Desktop/Scripta/PlayStore_Assets/`.
- **Privacy policy** now covers sleep + calendar + Android Health Connect
  (`docs/privacy/` EN+IT). Note: health/menstrual/sleep data is **on-device
  only → NOT declared as "collected"** in Play Data Safety; calendar event
  titles + city are the only personalization signals that leave the device.

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
- `lib/features/library/bookshelf_view.dart` — **`BookshelfView`**: the library
  drawn as spines standing on wooden boards, a second view mode beside the cover
  grid (toggle lives next to the TUTTI/PREFERITI chips; state in
  `_libraryViewModeProvider`). Spine colour = the book's OWN cover palette via
  `bookColorsFor()` in `book_cover.dart` (extracted with `bookArtSeed()` so the
  spine and the generated cover can never drift apart — do NOT re-inline that
  seed formula). Spine THICKNESS encodes highlight count; height is a stable
  per-book draw. Rows are packed greedily with **widow control** (books get
  pulled down so the bottom board is never left holding one lonely spine) and
  the last book leans when there is room. Title/author fitting is MEASURED with
  a TextPainter, not guessed from string length — that is what keeps titles from
  ellipsising. Covered by `test/widgets/bookshelf_view_test.dart` (overflow,
  no-book-lost-while-rebalancing, empty + single-book cases).
  ⚠️ **`Transform.rotate` does not take part in layout** — the leaning last book
  used to sweep straight THROUGH its neighbour (founder reported it).
  `_leanSweep()` computes the horizontal travel of the tilt and exactly that
  width is reserved beside it, so the head comes to REST on the neighbour while
  the foot slides away — which is what a real leaning book does. Don't
  "simplify" that spacer away. `scale:` shrinks the whole shelf proportionally
  (fonts, plank, padding); the shareable poster uses it.
- **The shelf is drawn inside a CABINET, not on floating planks**
  (`bookshelf_view.dart`): dark walnut carcass — uprights, top rail, plinth —
  with the interior in shade and boards jointed wall-to-wall. The books pack
  against the INTERIOR width (`maxWidth - 2*(_kStile + _kInnerPad)`), so any
  change to the carcass metrics automatically re-flows the rows. Pastel spines
  need the dark ground: on cream they drifted.
- **The profile shelf and the library shelf must lead to the SAME place.** They
  are the same widget in the same cabinet, so a reader expects the same
  behaviour — but the profile's spines come from Supabase and carry no local id
  (`ShelfEntry.bookId` is a local Isar int, null on that path), so it used to
  push `BookInfoScreen`, a Google-Books metadata page with literally no
  highlight code in it. Tapping a book there showed a cover, a title and nothing
  else (founder: "non fa vedere le frasi salvate"). Fixed both ways:
  `findLibraryBook(ref, title, author)` (promoted from private in
  `book_detail_screen.dart`) resolves the local book and pushes `/book/:id`, and
  `BookInfoScreen` is now a `ConsumerStatefulWidget` that renders the reader's
  own highlights ABOVE the metadata loading gate. ⚠️ Never "simplify" the
  profile tap to `context.push('/book/${e.bookId}')` — bookId is null there and
  the route degrades to "Libro non trovato". The match rule is the pure,
  tested `highlightBelongsToBook()`: exact title, case-folded — NOT a "core
  title" match, which would pull a sibling volume's phrases in.
- **The shelf poster shows the WHOLE library** (founder: "si devono vedere tutti
  in maniera leggibile", plus a "[n] libri letti" headline). Two mechanisms:
  `ShelfMetrics` makes spine sizes per-instance (`ShelfMetrics.poster` is
  slimmer than `.reading`, so tuning the poster can no longer shrink the reading
  shelf), and `posterDesignWidth()` SEARCHES for the design width whose cabinet
  proportions best match the room, because the FittedBox factor it maximises
  multiplies the title's point size directly. Measured: 43 books went from
  ~2.7pt to ~5.3pt. Two floors are structural, not taste — `minWidth >= 24` (the
  rotated title's line box overflows below ~21.5, which in an exported PNG means
  yellow-and-black stripes posted to Instagram) and `minHeight` is held at the
  reading value (dropping it buys 5% size and costs 1.5 characters of title).
  `test/widgets/shelf_poster_test.dart` locks all of it, including that the
  chosen width really is the best available.
- **"Condividi su Instagram" reuses plumbing that was already here**:
  `core/services/instagram_share.dart` + the `marginalia/instagram` MethodChannel
  in `AppDelegate.swift` + the `LSApplicationQueriesSchemes` already committed in
  `Info.plist`. No new dependency, no entitlement, no native code. The sheet
  captures TWO nested, both-painted RepaintBoundaries: a 9:16 story frame
  (360×640 ×3 = Instagram's native 1080×1920) for Instagram, which aspect-FILLS
  its background and would otherwise crop the top rail and the "Scripta"
  signature away, and the inner 4:5 card (×4) for the system sheet. Rasterising
  an OFF-screen widget is what silently produced blank shares before — keep both
  boundaries mounted. The button only renders when `instagramStoriesAvailable()`
  (false on Android, so no dead button) and falls back to the system sheet.
- **The shelf arrangement is public, and that needed a migration, not a button**
  (`078_shelf_arrangement.sql`). `books` has ONE select policy,
  `user_id = auth.uid()`, so a visitor could never read another user's books at
  all — `_ReadBooksSection` on a visited profile had never rendered for anyone.
  So: `user_shelf_layout` (one row per reader; `sort_mode` + a `manual_order`
  array of `title|author` keys — NOT book ids, which `deleteAllBooks` re-mints on
  every import) and `public_user_shelf(target_id)`, a SECURITY DEFINER window
  returning titles/authors/covers/COUNTS only, never highlight text, revoked from
  anon, honouring `profiles.is_private` internally. Verified live: direct select
  0 rows, RPC 53 rows with counts, private target + non-follower 0 rows.
  `fetchUserBooks` now goes through that RPC and the visited profile draws the
  same cabinet. One shared `applyShelfOrder()` in `profile_shared_widgets.dart`
  serves both profiles — "by colour" needs no schema at all, since a spine's hue
  is a pure function of title+author and every device derives it identically.
  ⚠️ Two defects the adversarial pass caught after this shipped green, both now
  fixed (migration **079** + `applyReorder`), both worth remembering:
  (1) `user_shelf_layout`'s read policy was `using (true)`. `manual_order` is
  NOT an opaque preference — the client writes EVERY book whatever the sort
  mode, so it is the reader's whole library, and an unfiltered
  `GET /rest/v1/user_shelf_layout` handed it to any signed-in caller, private
  accounts included. The gate was written carefully in `public_user_shelf` and
  left open in the table beside it. 079 gives the policy the identical
  predicate. Verified: private owner → 0 rows to a stranger, owner still reads
  their own.
  (2) `ReorderableListView` reports `newIndex` against the list BEFORE the item
  moves, so the documented `-= 1` correction is only valid if you REMOVE first.
  Doing both against the full-length list made every DOWNWARD drag land a slot
  early and a one-step drag down a silent no-op — and upward drags were fine,
  which is exactly why a quick check on a device said it worked. Use
  `applyReorder()`; it is locked by an exhaustive from×to test.
  Also: "Recenti" was a no-op (both queries ordered by title while the mode is
  the identity), so the source now orders by `imported_at desc` — a filter that
  silently returns alphabetical is worse than no filter.
- **Sharing is a picture, full stop.** A playable "guess the most-highlighted
  book" post was built, shipped and then REMOVED at the founder's call ("non mi
  piace questo livello di interazione") — migration **077** reverses 076, so
  there is no `posts.payload` and no `post_guesses` any more. Don't rebuild it.
  Two share paths, one poster (`shelf_poster.dart`, `ShelfPosterCard`, 4:5 for
  Instagram, signed bottom-right with the mark + "Scripta"):
  `showShelfShareSheet` publishes it to the feed as an ordinary image post, and
  `showShelfImageShareSheet` (button in the profile's LIBRERIA header) hands the
  PNG to the SYSTEM share sheet — which is how it reaches Instagram, with no
  IG-specific scheme or entitlement.
- `lib/features/library/shelf_share_sheet.dart` — **"Condividilo come post"**:
  renders the shelf as a 4:5 poster (RepaintBoundary → `toImage(pixelRatio: 3)`)
  → `uploadPostImage` → `createPost`, then invalidates `postsProvider`. The post
  is INTERACTIVE by carrying a question; the default ("indovina quale ho
  sottolineato di più") is playable because the shelf already encodes the answer
  in spine thickness, and the caption states that rule so the game is fair.
  The poster shows the 14 most-marked books re-sorted ALPHABETICALLY so the
  fattest spine isn't first and giving it away. Its shelf is laid out at a FIXED
  design width inside a `FittedBox` — laying it out against the live width would
  change the row count per device and overflow the fixed 4:5 card.
  The **profile** shows the shelf too (`my_profile_screen.dart`, replacing the
  old flat 3-column cover grid — `_BookCell` was deleted with it); its spine
  thickness comes from an embedded `highlights(count)` aggregate added to
  `fetchMyBooks()`, so it means the same thing there as in the library.
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
- **Security audit (2026-07-17):** found + fixed a **P0 unauthenticated IDOR**:
  `match_highlights(p_user_id, embedding, count)` is SECURITY DEFINER (bypasses
  the `highlights` RLS) and filtered by the caller-supplied `p_user_id` with no
  `auth.uid()` check, and was EXECUTE-granted to `anon`. So anyone with the public
  anon key (ships in the binary) + a target UUID (world-readable `profiles`) could
  read any user's private highlight text via `/rest/v1/rpc/match_highlights`, 50
  rows/call — **verified live** before the fix. The only legit caller is the
  `semantic-search` edge fn, which runs with SERVICE_ROLE and passes the verified
  caller id. Fix = migration **074** revokes anon/authenticated/PUBLIC EXECUTE,
  keeps service_role. Re-verified: anon call → 401 "permission denied"; legit
  search still returns results. Lesson: a SECURITY DEFINER fn that trusts an id
  PARAMETER must either check `auth.uid()` internally OR be revoked from
  anon/authenticated (service_role-only). Audited every other anon-callable
  DEFINER fn — all others scope to `auth.uid()`/membership correctly.
  Same 2026-07-17 pass (multi-agent fan-out + adversarial verify) also found &
  fixed 4 lower findings, all P3: (1) **send-push-notification** — client `data`
  was spread AFTER the server `aps` in `sendApns`, so a caller who shares a
  jam/conversation with the victim could pass `data.aps` and override the
  verified-sender title/body (clean impersonation). Fixed: strip reserved `aps`
  from `data`, spread `data` FIRST then `aps` (single choke point → all modes).
  Deployed v12, live source verified byte-perfect. (2) **moderate-image** lacked
  the per-user `check_rate_limit` every other expensive edge fn has → cost-abuse
  once Sightengine is enabled. Added a 300/hr throttle after the not-configured
  fail-open (deployed v5). (3) **`app-builds`** storage bucket was public=true
  with no policy + undocumented + empty (78 MB limit fits an app binary) → made
  private (mig **075**). (4) **docs/app.html** (password-reset page) loaded
  supabase-js from jsDelivr with a floating `@2` tag and no SRI → pinned to
  `@2.110.7/dist/umd/supabase.js` + `integrity` sha384 + `crossorigin`
  (verified the pinned+SRI script still loads the `supabase` global, no console
  errors). FOUNDER-ONLY residuals (I can't do these): revoke the old **Codemagic
  API token** in `cm_watch.py` (gitignored/local-only, unused since GitHub
  Actions, but unrotated); enable **Auth → leaked-password protection**
  (HaveIBeenPwned) in the Supabase dashboard. The 0028/0029 advisor warnings on
  the other anon/authenticated SECURITY DEFINER RPCs are advisor noise — they all
  scope to `auth.uid()`/membership (verified), and several are RLS helpers whose
  grants must NOT be narrowed.
- **Security audit (2026-06-17, hack test):** 13-agent penetration-style audit
  (RLS / edge fns / secrets / storage / auth / input) → **0 live-exploitable
  vulns**. 7 findings already fixed & re-verified live (notifications-insert 032,
  storage-upload 066, jam-cover IDOR is member-scoped, reviews authenticated-only
  044, jam_highlights-delete 068, jam_poll_candidates-update 069, RPC anon-grants
  043); 1 migration-drift fixed (`is_jam_member_or_owner` → mig 071); 1 residual
  **decision pending the founder**: profile privacy is still APP-LEVEL/soft (see
  §9 note) — a hard-RLS pass is feasible but risks breaking feed/search/post-author
  for live users, so do it as a dedicated, tested change only if he asks.
- **Groq model migration COMPLETE (2026-07-17).** The two Groq-backed
  functions are both live on the replacement models (old llama models are
  decommissioned 2026-08-16): `pick-daily-highlight` v12 = `openai/gpt-oss-120b`,
  `recommend-books` v30 = `openai/gpt-oss-20b` (deployed via MCP
  `deploy_edge_function` — a 32 KB accented file survives the MCP round-trip
  byte-perfect, verified by reading the live source back; E2E-tested with the
  demo-account JWT, reason "ok" + 5 personalised recs). gpt-oss are REASONING
  models: keep `max_completion_tokens` (not a tiny `max_tokens`) +
  `reasoning_effort: "low"`. `deploy_recommend_books.ps1` is now just a fallback.
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
- **gen-l10n orders generated params ALPHABETICALLY, not by placeholder order
  in the string.** `importSuccess` is "Importati {highlights} highlight da
  {books} libri" but the generated signature is `importSuccess(books,
  highlights)` — every call site passed `(highlightsAdded, booksAdded)` and the
  snackbar showed the numbers swapped ("1 highlight da 2 libri" for 2
  highlights/1 book). Import itself was always correct. Fixed 2026-07-17 (4
  call sites) + regression test `test/l10n/import_success_order_test.dart`
  that locks the slot order. Any new multi-placeholder ARB string: check the
  generated signature before calling it.
- **Kindle-synced highlights were being destroyed in SERIALISATION, not in the
  sync.** `toClippingEntry()` (amazon_sync_service.dart) wrote `location 0` for
  every highlight Amazon reports without one, and `ImportService` dedups on
  (book, location) — so a whole book collapsed to ONE highlight, silently, with
  a success message. Same function wrote a raw `DateTime.now()` that matches
  none of the parser's formats, so every Kindle highlight landed with a null
  date (reading stats derive from that date). Both fixed: content-hash fallback
  location + `DateFormat('EEEE, MMMM d, yyyy h:mm:ss a','en_US')` on
  `.toUtc()` (the parser does `DateFormat.parse(str, true)`, i.e. it reads the
  string AS UTC — format local time there and every timestamp shifts).
  Locked by `test/services/amazon_clipping_entry_test.dart`.
- **Permanent deletion is prohibited** by safety rules — when cleaning files
  (e.g. old APKs) move to Recycle Bin, never hard-delete.
- **`flutter create --platforms=ios .` PRESERVES the committed `ios/Runner/
  Info.plist`** (empirically verified: a probe key survives a re-run). So the
  Calendar (`NSCalendars*`), HealthKit (`NSHealthShare/Update`),
  `NSPhotoLibraryAddUsageDescription`, and `ITSAppUsesNonExemptEncryption` keys
  ship straight from the committed plist — they do **NOT** need CI re-injection,
  and you should NOT add PlistBuddy `Set` lines for them (that would clobber the
  committed wording with the CI string and create a divergence trap). The CI
  only re-injects CFBundleDisplayName/Name (committed value resolves via a build
  variable) and Camera/Photo. Don't "fix" a non-bug here — the purpose strings
  already reach the IPA. (Investigated 2026-06-26 during store-readiness.)

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
- **Daily-phrase personalization (2026-06-19)** — `daily_subtitle_provider` +
  `daily_highlight_provider` weave these ON-DEVICE signals (never uploaded; only
  an abstract "tone" word reaches the picker): steps, today's workout, **sleep
  last night** (HealthKit `SLEEP_ASLEEP`, morning only), **menstrual phase**
  (women only; inferred conservatively — needs ≥2 logged period starts + a
  current cycle ≤33d, else null; say "fase mestruale"/"del mese", never bare
  "ciclo"), native **calendar** events, and **event-approach** (`calm`/`focused`/
  `anxious`, onboarding step 12 → `EventApproachService`/`eventApproachProvider`,
  hydrated in app_startup_*). The **library greeting** (`_LibraryGreetings`)
  agrees with `genderProvider` (feminine/masculine/neutral). Onboarding is now
  **14 steps** (`_kTotalSteps`/`_kStepComplete=13`; EventApproach is step 12).

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
