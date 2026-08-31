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
- Latest green iOS build: **TestFlight run #130, commit `a9c41f6`** (build
  number = unix timestamp). Latest APK: **`Scripta_1.1.0.apk` on the Desktop**,
  smoke-tested on the emulator. Suite is now **118 tests** (was 45) — green.
  ⚠️ CI note: run #129 shows "failure" but was **cancelled**, not broken —
  `concurrency.cancel-in-progress` on `github.ref` means a second push kills the
  run the first one was still queueing. GitHub can take 30+ minutes to start a
  run; pushing again to "re-trigger" destroys it. Wait.
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

### Play Console — app setup COMPLETE (2026-08-27)
The 11-item "Completa la configurazione dell'app" checklist is **done** and has
disappeared from the app dashboard; App content shows "Non hai niente in
sospeso". Everything below is saved server-side and queued in *Panoramica della
pubblicazione*, waiting only for the founder to submit.
- **Data Safety** (all 5 steps): encrypted in transit **yes**; account deletion
  **yes** → `https://get-scripta.app/delete-account/`; **nothing shared** with
  third parties. 11 data types declared *collected, non-ephemeral*:
  - Nome / Indirizzo email / ID utente → required · *Funzionalità dell'app* +
    *Gestione dell'account*
  - Altri messaggi in-app / Foto / Cronologia ricerche in-app / Altri contenuti
    generati dagli utenti → optional · *Funzionalità dell'app*
  - Log arresti anomali / Dati diagnostici / Interazioni con l'app → required ·
    *Analisi* (Sentry is the only such SDK — see `pubspec.yaml`)
  - ID dispositivo o altri ID → required · *Funzionalità dell'app* + *Analisi*
    (push tokens + Sentry install id)
  Health/cycle/sleep stay undeclared on purpose: they never leave the device.
- **Store settings**: App → *Libri e consultazione*; public contacts
  `support@get-scripta.app` + `https://get-scripta.app`.
- **Main store listing** (en-US, the app's default language): name, short (64/80)
  and full (1418/4000) description from the handoff doc, 512 icon, a **rebuilt**
  1024×500 feature graphic, and **6 real screenshots captured from the running
  app** (2026-08-27), in this order: library · bookshelf · book + highlights ·
  Review · search by meaning · profile.
  - The first feature graphic hid "READING CIRCLES" under the app icon. The
    replacement is generated by `Desktop/Scripta/PlayStore_Assets/make_feature_graphic.py`,
    which RESERVES the icon column and shrinks any string that outgrows the text
    column instead of letting it slide underneath — so the collision cannot come
    back. EB Garamond + Manrope are fetched from Google Fonts at run time.
  - The old screenshots were marketing mock-ups (a phone render under a caption).
    The founder asked for the real thing, so these are `adb exec-out screencap`
    captures off the `scripta-play` AVD signed into the demo account (43 books,
    905 highlights), with SystemUI demo mode on (9:41, full battery, no
    notifications). A raw Pixel capture is 1080×2400 = 1:2.22, which is MORE
    elongated than the 9:16 Play accepts, so `pad_shots.py` pads the width to
    **1350×2400** — exactly 9:16, no rescaling, both sides ≥1080 (the threshold
    for being eligible for Play promotion).
  - Play does NOT let you reorder screenshots (no cdkDrag in the DOM): order is
    insertion order, so to control it you delete them all and add ONE at a time.
- Declared **minimum age 18+** — changing it means redoing the content-rating
  questionnaire.
- **Automating this console is painful** and the notes are worth keeping:
  - It is *slow*: a dialog can take 10–25 s to render, and `Runtime.evaluate`
    times out at 45 s while the renderer catches up. Fixed `wait` actions +
    a screenshot checkpoint beat any in-page polling loop (a JS wait loop can't
    run while the main thread is blocked, so it just burns the timeout).
  - **JS `.click()` does not dirty an Angular form** — the value flips but
    *Salva* stays disabled. Recipe that works: one **real** click on the first
    checkbox ("Raccolti"), then JS for every follow-up radio/checkbox.
  - Text inputs are the opposite: set `.value` through the native setter and
    dispatch `input`, then send one real keystroke to clear the stale
    "required" error.
  - Asset upload: there is **no `input[type=file]`** in the DOM and `fetch()` to
    `localhost` is blocked. What works is injecting an `<input type=file>`,
    filling it with the `file_upload` browser tool, then moving its `File`s into
    a `DataTransfer` and dispatching `dragenter`/`dragover`/`drop` on the
    `assets-holder`. **The holder must be scrolled into view first** or the drop
    is silently ignored.

**Library greeting was Italian-only** and it is the FIRST line of the app's main
screen, so every English reader was welcomed in a language they had not chosen
(caught while shooting the store screenshots — the emulator runs en-US, and the
header still said "Di nuovo qui tra le righe"). `_LibraryGreetings` now carries
a second 26-line English set (`_phrasesEn`, same length so the day-of-year
rotation lands on the matching mood) and `forToday()` takes an `english` flag
from `Localizations.localeOf(context)`. They are two curated lists, NOT ARB
entries: a greeting has to sound written rather than translated, and the Italian
lines carry masculine/feminine participles that English simply does not have.
Verified on device: the header reads "Here again between the lines, Scripta
Demo?". `Desktop/Scripta.aab` was rebuilt on this fix (37.4 MB, upload key
SHA1 `DF:DE:F3:04:…:8A:D5`) so the binary matches the screenshots.

**Closed-test channel "Alpha"** (track id `4700201154477441116`): countries =
**all 177**, tester list **"Scripta - test chiuso"** attached (the founder's two
addresses so far), feedback address `support@get-scripta.app`, and the **app
bundle is uploaded** — dashboard reads *Completate 3 di 5*, Play parsed it as
`1 (1.1.0)`, API 26+, target 35, 14.4 MB install / 8 s download.

**Uploading a 37 MB bundle with a 10 MB tool limit**: `split -b 9437184` into
four chunks, `file_upload` each into an injected `<input type=file>`, absorb
each one's `arrayBuffer()` into a JS array, then `new File([...parts], ...)` and
assign it to Play's own `input[type=file][accept=".aab"]` via `DataTransfer`.
**Verify before handing it over** — the page computes `crypto.subtle.digest`
over the welded blob and refuses unless it matches the on-disk sha256; a
silently truncated upload would be far worse than a failed one.

**Health declaration now names the real categories** (founder's call,
2026-08-31: *"deve esserci la cosa del ciclo"*). The manifest requests exactly
four Health Connect permissions — `READ_STEPS`, `READ_EXERCISE`, `READ_SLEEP`,
`READ_MENSTRUATION` — and each is now covered by a ticked category:
*Attività fisica e fitness*, *Gestione del sonno*, **Monitoraggio del ciclo
mestruale**, plus *Altro* carrying the honest description ("Read-only
personalisation… nothing is stored or uploaded; declining any permission still
works"). The previous answer said "no health features are offered", which
contradicted requesting those permissions.
⚠️ Consequence to expect: Google now treats Scripta as a health app that reads
cycle data, and `READ_MENSTRUATION` is the permission it scrutinises most — a
follow-up request for justification or a demo video is likely.

⚠️ **The release cannot be confirmed — deadlock confirmed, not a missing
answer.** The review step reports *"Devi completare la dichiarazione relativa
all'integrità"* (link → `app-content/health`) even after the declaration was
re-answered, saved and re-validated. The mechanism is now proven: *App content*
says **"Non hai niente in sospeso"** (every declaration answered), and the
publishing overview lists **"App per la salute · Dichiarazione relativa alle app
per la salute completata"** among the changes **not yet submitted for review**.
So the declaration is complete but not yet IN EFFECT, the release validator
requires it in effect, and *Invia app per la revisione* — the only thing that
would put it in effect — is itself disabled until the dashboard checklist is
finished. Each waits on the other.
Ruled out while chasing it: it is NOT Play Integrity (that section moved to
*Protetto con Play*, whose only inactive item is the optional
"Impedisci le installazioni su dispositivi rischiosi"), NOT a stale validation
snapshot (going back to step 1 and forward re-runs it with the same result), and
NOT missing content. Nothing else can be done from the console; expect it to
clear once Play applies the saved declaration, otherwise it is a support case.

**Still founder-only**: add the remaining tester emails (Google needs **12
testers × 14 consecutive days** for a personal developer account), upload
`Desktop/Scripta.aab` (37.4 MB — over the 10 MB tool upload limit, so it has to
be dragged into the release by hand), then *Visualizza l'anteprima e conferma*
and *Invia la release a Google per la revisione*.

### Saved highlights (2026-08-28)
The bookmark on the highlight-detail screen had **never worked**. Every tap threw
`IsarError: Cannot perform this operation from within an active transaction`
inside `HighlightFavoriteNotifier.toggleFavorite`, and the old code wrapped the
write in a bare `catch (_) {}`, so the exception vanished and the icon simply
never changed — nothing on disk, nothing in Supabase (verified: 0 favourites
across 905 rows on the demo account).
- **Cause**: the async `IsarCollection.put()` has no `saveLinks` flag, so it
  ALWAYS writes the object's links back, and saving a link opens its own
  transaction. The detail screen calls `book.load()` before rendering, so the
  link was attached and the nested write blew up every time. The same
  `writeTxn` + `await put()` shape works elsewhere in the codebase only because
  those objects' links are not loaded.
- **Fix**: `isar.writeTxnSync` + `getSync` + `putSync(h, saveLinks: false)`.
  Nothing in this write touches links, so there is nothing to save.
- `toggleFavorite` now returns the value **re-read from Isar** (null = nothing
  was written) and logs instead of swallowing; both call sites show a snackbar,
  so a storage failure can never again look like a dead button.
- New **`favoriteHighlightsProvider`** (native + web twins) and
  `features/settings/saved_highlights_screen.dart` — the private "Saved" /
  "Salvati" list, first row in Settings. Private by construction: it renders the
  signed-in user's own rows and has no visited-profile variant, so there is no
  permission check to get wrong. Strings live in the ARBs
  (`savedHighlights*`), not in the inline `it ? … : …` ternaries.
- Verified on the emulator: icon fills, `[favorite] 846 -> true`, the row lands
  in Supabase (`is_favorite` = 2 rows), the list shows "2 saved highlights /
  Only you can see this list", un-saving from the list updates it to the
  singular form.

### App Store — SUBMITTED 2026-08-31
**iOS 1.0 is "In attesa di verifica"** (waiting for review; Apple quotes up to
48 h). Submitted build **1.1.0 (1788203346)** from commit `f91228d`, i.e. the
one carrying the bookmark fix, the Saved screen and the English greetings.
- ⚠️ The version record had build **1783726117 from July** still attached.
  Submitting it would have shipped the dead bookmark and two months of stale
  code. **Always check the attached build before submitting** — remove it by
  hovering the row (a red minus appears at the far right), then *Aggiungi build*
  → pick the new one → **Salva** (the review button stays greyed until the page
  is saved) → *Aggiungi alla verifica* → *Invia per la verifica*.
- Everything else on the version page was already in place: 7 screenshots,
  demo account `review@get-scripta.app`, IT+EN reviewer notes with the
  My Clippings.zip attachment, age 13+ (16+ in 2 regions), encryption and DSA
  answered.
- CI is healthy again — runs #140–#143 all green, so the Apple
  license-agreement block from 2026-07-11 is gone.

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
- **"The same book" is a NORMALISED match, never string equality**
  (`lib/core/services/import_match.dart`). The two doors into the library
  disagree by construction — `My Clippings.txt` writes `Il nome della rosa
  (Eco, Umberto)` with location `1234-1236`, while the Kindle web notebook
  gives `Umberto Eco` and location `1234` — so exact matching made the same
  book a second book and the same quote a second quote. This was ALREADY LIVE:
  two production accounts held "Il nome della rosa" (5 highlights) alongside
  "Il Nome della Rosa" (21), split by one capital letter. Making the sync
  automatic every 6h turned a nuisance into something that compounds unattended.
  Rules: `bookMatchKey()` = lowercased/whitespace-collapsed title + author
  reduced to a SORTED WORD SET (so "Eco, Umberto" == "Umberto Eco");
  `isSameHighlight()` = identical normalised text, OR same starting location AND
  one text contains the other (the "Kindle re-issued it with more words around
  it" case). It deliberately errs towards keeping both — a duplicate is visible
  and complainable, a wrongly merged highlight is a sentence that silently
  disappears. Used by the native importer, the web variant, `restoreFromCloud`,
  and the Amazon serialiser; `_mergeBookInto` folds already-split books together
  at import time. ⚠️ Never key a persisted identity on `String.hashCode` —
  `contentFingerprint()` (sha1) exists because Dart does not promise hashCode is
  stable across SDK releases, and that value is compared on every later sync.
- **The importer holds the library in memory for one import.** It used to run
  two Isar queries per clipping (4000 queries for a 2000-line file) AND could
  only ask exact-equality questions. Now it loads the user's books once and
  matches in Dart, which is both faster and the only way to ask "which book has
  this normalised key".
- **`highlights` had NO unique constraint** despite a code comment asserting
  "the server enforces UNIQUE(user_id, content_hash)". It had a primary key and
  two foreign keys, full stop — so the only thing preventing cloud duplicates
  was the deterministic row id, which a differently-capitalised book bypassed.
  Migration **080** adds the index for real (verified creatable first: 2051/2051
  rows had a hash, 0 conflicts). Don't trust a comment about a constraint —
  query `pg_constraint`.
- **`highlights.book_id` is ON DELETE CASCADE.** Move highlights BEFORE deleting
  a book row, or they go with it.
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

- Page source: **`admin-console/index.html`**, published by
  **`deploy_site.ps1`** onto a secret path read from **`.console-slug`**
  (gitignored). Nothing links to it.
- ⚠️ **The old slug is BURNED — do not reuse `console-hl0591p7oc`.** It lived in
  `docs/`, which GitHub Pages serves, and this repo is PUBLIC: the folder name
  advertised the "secret" path to anyone browsing the repository, and it is
  still visible in three commits of history, which removing the folder does not
  undo. Rotated 2026-08-25. The obscurity layer is a speed bump, never the
  lock — the token checked by `admin-metrics` is the actual gate.
- ⚠️ **`get-scripta.app` IS NOT GITHUB PAGES.** The apex is a **Cloudflare Pages**
  project called `scripta` with **no git integration**, so a push publishes
  NOTHING there — it has to be uploaded with `deploy_site.ps1`. Nobody had for a
  month, which is why the live privacy policy sat a version behind the repo and
  the console stayed stale while GitHub Pages served a newer copy. Verified by
  fetching both origins at once and getting different bytes.
- GitHub Pages still serves `docs/` and **must keep doing so**: `app.html` is the
  password-reset page that already-sent emails point at.
- Cloudflare has **Email Address Obfuscation** on for the zone, so `curl` of a
  live page shows `__cf_email__` / `data-cfemail` instead of the address. The
  page is fine — grep the deployment URL (`<id>.scripta-bub.pages.dev`), which
  bypasses Scrape Shield, before concluding an address is missing.
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
- **Waiting list** (`waitlist_signups`, migration 073, fed by the form on
  `docs/index.html`). Its RLS grants INSERT to anon and **no SELECT policy at
  all**, so the list is unreadable with the public anon key — by design. The
  console reads it via `admin-metrics?section=waitlist` (service role): the
  COUNT rides along with the ordinary metrics, but the addresses are a separate,
  explicit request, so personal data travels because someone pressed a button
  rather than on every page load. The panel offers "Copia tutte le email"
  (comma-separated, the shape a recipients box wants) and a CSV download
  (quoted, UTF-8 BOM so Excel handles accents).
- **`admin-metrics` lives in the repo and matches production byte for byte**
  (`supabase/functions/admin-metrics/index.ts`). It could not before, because
  the token was a constant in the source and the repo is public — so the source
  drifted out of version control, which CLAUDE.md §5 already listed as a
  problem. The token moved to **`public.admin_secrets`** (migration 081): RLS
  on, NO policies, all grants revoked, so it is unreachable through PostgREST
  for anon and authenticated and only the service role the function runs as can
  read it. An `ADMIN_TOKEN` env var still wins if one is ever set, so adopting
  Supabase secrets later needs no code change. An EMPTY expected token is
  rejected outright — a missing secret must never become an open door.
- **Waiting-list welcome email** (`supabase/functions/waitlist-welcome/`,
  migration **082**). Hung off the ROW via a pg_net trigger, not off the landing
  page's JavaScript: the page inserts straight into `waitlist_signups`, so a
  fetch fired from there would cover that one form only and would die silently
  when a page unloaded mid-request. pg_net QUEUES the call, so a slow email
  provider can never delay or fail somebody's sign-up.
  ⚠️ The copy is load-bearing. The sign-up form promises **"no spam, just one
  email when it's your turn"** — a welcome email is therefore already the SECOND
  one, and it earns itself only by restating that promise instead of quietly
  breaking it ("Not a newsletter, not a countdown…"). Don't add another campaign
  to this address without changing the form's promise first.
  No duplicate welcomes: `waitlist_signups_email_key` is unique on lower(email),
  so a repeat sign-up never becomes a row. Verified end-to-end BEFORE the API key
  existed — insert → trigger → function → `200 {"skipped":"no api key"}` in
  `net._http_response`. That graceful skip is deliberate: a missing key must
  never look like a crash.
- **Sending is set up on Resend** (account `vittorio.scripta@gmail.com`, domain
  `get-scripta.app`, region **Ireland/eu-west-1**, added 2026-08-25). DNS records
  live and confirmed against 8.8.8.8:
  `resend._domainkey` TXT (DKIM) · `send` MX → `feedback-smtp.eu-west-1.amazonses.com` (10)
  · `send` TXT → `v=spf1 include:amazonses.com ~all` · `_dmarc` via Cloudflare
  DMARC Management (`p=none` + rua to Cloudflare's report collector).
  Receiving is untouched: the three root MX and the root SPF are intact.
  ⚠️ **Email Routing LOCKS the zone's DNS records** ("DNS records: Locked" on the
  Email Routing overview). That is why MX records fight back in the dashboard —
  the add succeeds but often only after a retry, and the table lags. Always
  confirm with a real DNS query, never with the dashboard table.
  ⚠️ Resend's own domain status stays "Not Started" for a while after the records
  are live — its verification is asynchronous. Do not re-add records because of
  that badge.
  Click/open tracking is NOT configured on the domain, which is the right state
  for this product — no tracking subdomain, no pixel. TLS is "Opportunistic";
  "Enforced" would be stricter but silently drops mail to servers without TLS.
  STILL MISSING and founder-only: `RESEND_API_KEY` as a Supabase edge secret
  (the welcome function no-ops without it), and the SMTP settings for auth mail.
- **SENDING IS LIVE.** Resend domain `get-scripta.app` is **Verified**, and the
  waiting-list welcome email was delivered end-to-end on 2026-08-25: insert →
  trigger → function → Resend → `Delivered`, `FROM: Scripta
  <support@get-scripta.app>`, subject "Sei in lista" (Italian picked from the
  signup's locale). Test address is `delivered@resend.dev` — Resend's own sink,
  which never bounces and never touches sender reputation. Use it, never a fake
  domain.
  Debug order that worked, in case it breaks: the function LOGS Resend's exact
  error, so read `function_logs` rather than guessing — "API key is invalid"
  (400) and "domain is not verified" (403) are different problems with different
  fixes, and the pg_net response body only shows the status.
  ⚠️ Resend's domain badge sits on "Not Started" until its checker runs; the
  `POST /api/trpc/domains.verify` call is what triggers it. Records being live
  in DNS is not enough on its own.
- ⚠️ **The "Reset password" auth template has the WHOLE template file pasted into
  it**, instruction header comments and all — not just BLOCCO A. Confirmed by
  reading its Source in the dashboard. Very likely BLOCCO B (the signup-code
  email) is in there too, which would make every reset email carry a second,
  irrelevant template with a confirmation code; the dashboard refused to scroll
  under automation so that half is UNVERIFIED. Clean, comment-free bodies are on
  the Desktop as `SOLO-A-reset-password.html` and
  `SOLO-B-conferma-registrazione.html`. "Confirm sign up" is already correct.
- **Cloudflare CANNOT send email.** Email Routing receives and forwards only —
  that is the product, not a misconfiguration. Proof: the zone's SPF authorises
  only `_spf.mx.cloudflare.net`, and no sending provider has a DKIM selector on
  the domain. `support@get-scripta.app` is the published contact address
  (privacy + terms, IT/EN) and receives today. To SEND as it: the Resend domain
  `get-scripta.app` (Ireland/eu-west-1, added 2026-08-25) needs its DNS records
  live, then `RESEND_API_KEY` as a Supabase edge secret, plus SMTP settings for
  auth mail. ⚠️ Driving the Cloudflare DNS dashboard by automation is BLOCKED —
  use Resend's own "Auto configure" or its per-record Copy buttons.
- **`admin_secrets` now holds two values**, neither in git: `console_token` and
  `waitlist_hook_token` (the shared secret between the trigger and its function).
- To rotate the token: `update public.admin_secrets set value = '<new>',
  updated_at = now() where name = 'console_token';` then update the founder's
  Desktop file. No redeploy — but the running instance caches the token for its
  lifetime, so the change lands on the next cold start (or redeploy to force it).
  There is no MCP tool for Supabase secrets, which is why the table exists.

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
