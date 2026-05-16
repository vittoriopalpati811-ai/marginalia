# Progress Log

> Diario delle sessioni. Claude aggiorna questo file a fine sessione.
> Sessioni più recenti IN ALTO. Le task completate restano qui per storico.

---

## 📌 Stato attuale del progetto

**Fase**: Flutter foundation completa, infrastruttura cloud parzialmente operativa
**Sprint corrente**: Sprint 1 (Flutter) — Foundation completata
**Prossima azione founder**: iscriversi all'Apple Developer Program (€99/anno) — vedi QUESTIONS.md
**Branch attivo**: main
**Build status Flutter/Windows**: 🟡 pronto — esegui `dart run build_runner build` poi `flutter run -d windows`
**Build status iOS (TestFlight)**: 🔴 bloccato — Apple Developer Program non attivo (vedi QUESTIONS.md)

**Infrastruttura cloud**:
- Supabase `marginalia`: ✅ operativo (`https://ibucvloawkfwobaelwbr.supabase.co`)
- Codemagic: ✅ app creata, repo connesso, tipo Flutter impostato
- App Store Connect API key: 🔴 manca (richiede Developer Program)

---

## Sessioni

### Sessione 7 — 2026-05-16
**Durata**: ~1.5h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Fix encoding caratteri accentati — definitivo (✅)**
- Root cause: `utf8.decode(bytes, allowMalformed: true)` sostituiva silenziosamente i byte Latin-1 invalidi con U+FFFD invece di fare fallback
- Fix `library_screen.dart`: nuovo metodo `_decodeClippings(Uint8List)` → strip BOM (0xEF 0xBB 0xBF) → `utf8.decode()` strict → catch FormatException → `latin1.decode()` come fallback sicuro (copre tutti i 256 valori byte)
- Kindles moderni usano UTF-8; vecchi firmware Latin-1 / Windows-1252 — ora entrambi gestiti

**5 dummy user per test social (✅)**
- `supabase/migrations/004_profile_reading_social.sql`: aggiunge `currently_reading_title`, `currently_reading_author`, `bio` ai profili; colonna `role` a `jam_members`; crea `jam_highlight_reactions`, `jam_highlight_comments`, `follows` con RLS
- `supabase/seed_dummy_users.sql`: script idempotente da eseguire nel SQL Editor del dashboard Supabase — 5 utenti (Marco Rossi, Sofia Bianchi, Luca Ferrari, Elena Conti, Davide Russo), 7 libri con citazioni italiane reali, 2 Jam (Libri di Settembre / Classici del 900), highlight condivisi, follow reciproci
- Sezione commentata in fondo per collegare il proprio account reale ai dummy users

**Feed sociale (✅)**
- `lib/features/social/feed_tab.dart` (nuovo, ~290 righe): `feedProvider` → `svc.fetchFeed()` → join client-side con profili; `FeedTab` con stati loaded/empty/notLoggedIn; `_FeedCard` con avatar gradiente, timestamp relativo, badge Jam tappabile, accent strip colore Kindle, estratto highlight 240 chars; animazione staggered fadeIn + slideY
- `SupabaseService.fetchFeed()`: query `jam_highlights` filtrata su `followingIds`, join `highlights(books)` e `jams`, poi fetch profili in parallelo e merge

**Profilo utente pubblico (✅)**
- `lib/features/profile/user_profile_screen.dart` (nuovo, ~380 righe): provider family per profilo, statistiche, highlight condivisi, isFollowing; `SliverAppBar(expandedHeight: 260)` con avatar gradiente; `_StatsRow` (Highlight/Condivisi/Seguiti/Follower); bottone Segui/Smetti (nascosto per se stessi); griglia 2 colonne di `_SharedCell` con gradiente e badge Jam
- `SupabaseService`: aggiunti `fetchPublicProfile`, `fetchUserStats`, `fetchUserSharedHighlights`

**SocialScreen a 3 tab (✅)**
- Feed (index 0) → Jam (index 1, default) → Amici (index 2)
- `TabController(length: 3, initialIndex: 1)` — apre sempre sul Jam
- FAB "crea Jam" appare solo nella tab Jam

**AmiciTab — righe tappabili (✅)**
- `_UserRow` wrappato in `GestureDetector` → `context.push('/user/$uid')` su tap della card
- Import `go_router` aggiunto ad `amici_tab.dart`

**Route `/user/:id` (✅)**
- `app.dart`: GoRoute `path: '/user/:id'` con `parentNavigatorKey: _rootNavigatorKey` → `UserProfileScreen(userId: id)` con transizione `SharedAxisTransition` horizontal

#### Prossima azione founder
1. Esegui migration `004_profile_reading_social.sql` nel SQL Editor Supabase
2. Esegui `seed_dummy_users.sql` — poi decommentare la sezione in fondo con il tuo UUID
3. `flutter run -d windows` o `-d chrome` per smoke test Feed + Profili

---

### Sessione 6 — 2026-05-16
**Durata**: ~2h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Instagram share card — stile Spotify (✅)**
- `lib/core/services/share_card_service.dart`: `ShareCardService.show()` apre un bottom sheet con preview della card 4:5 e due pulsanti
- Card: gradiente scuro (variante per colore Kindle), Lora italic corsivo, virgoletta decorativa 130px, wordmark "MARGINALIA" top-right, badge "marginalia.app", info libro + autore
- Bottoni: "Copia" (clipboard) + "Condividi immagine" → `RepaintBoundary.toImage(pixelRatio: 3.0)` → file PNG in temp → `Share.shareXFiles`
- Testo share: include excerpt + autore + link `https://marginalia.app` ("Apri in Marginalia →")
- Web fallback: `kIsWeb` → `Share.share()` text-only
- Conditional import `share_file_helper.dart` → `_native.dart` (dart:io) / `_web.dart` (stub)
- `HighlightDetailScreen`: share icon usa ora `ShareCardService.show()` invece di `Share.share(content)`

**Fix bug: IsarLink book non caricato (✅)**
- `highlights_provider_native.dart`: `highlightByIdProvider`, `searchResultsProvider`, `allHighlightsProvider` ora caricano tutti i link libro con `Future.wait(results.map((h) => h.book.load()))`
- Prima di questo fix: `h.bookTitle` e `h.bookAuthor` erano sempre null in HighlightDetailScreen e nella library strip

**SearchScreen modernizzata (✅)**
- Header con gradiente scuro (come SocialScreen), gestisce notch via `MediaQuery.of(context).padding.top`
- Search bar traslucida (bianco 22% alfa) embedded nel gradiente
- `_SearchResultCard`: accent strip colorato (basato su colore Kindle), titolo libro + autore sopra l'excerpt
- `_NoResults` estratto come widget separato

**Pull-to-refresh LibraryScreen (✅)**
- `RefreshIndicator` wrappa `CustomScrollView`, `onRefresh` chiama `_invalidateAfterImport()`
- Colore indicator: `MarginaliaColors.sienna`

#### Prossima azione founder
- `flutter run -d windows` o `flutter run -d chrome` per smoke test visivo delle nuove card di ricerca e share
- Testare share immagine su device iOS reale (via TestFlight) per verificare il file PNG temporaneo

---

### Sessione 5 — 2026-05-16
**Durata**: ~2h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Fix encoding caratteri speciali — round 2 (✅ definitivo)**
- Root cause identificata: UUID dell'highlight era basato sul `content` → re-import con content corretto generava UUID diverso → dedup by location trovava match → `continue` impediva l'upsert → dati corrotti restavano in Supabase
- Fix `import_service_web.dart`:
  - UUID basato su `(bookId, location)` invece che `(bookId, content)` — stabile tra re-import
  - Rimosso `continue` sul path dedup: upsert gira sempre, aggiorna automaticamente content corrotto
  - `isDuplicate` calcolato PRIMA dell'upsert, contatori `deduplicated`/`added` separati correttamente
- Aggiunto `deleteAllUserData()` a `SupabaseService` — nuclear option per dati già corrotti
- Aggiunto "forza re-importazione" in `LibraryScreen` (long-press su import): cancella tutti i dati e reimporta

**Redesign UI — design_course template (✅)**
- `LibraryScreen`: griglia 2 colonne (SliverGrid), strip highlight recenti orizzontale, FilterChips animati, header editoriale senza AppBar
- `BookDetailScreen`: stack hero 300px + DraggableScrollableSheet stile CourseInfoScreen, stat boxes, floating back button
- `highlight_native.dart`: aggiunti getter cross-platform `bookTitle`, `bookAuthor`, `bookId`

**Bottom nav floating pill (✅)**
- `app.dart` completamente riscritto: `AnimatedPositioned` pill indicator, `AnimatedSwitcher` icon/label, `HapticFeedback`, `extendBody: true`
- Transizioni push: `SharedAxisTransition` horizontal (package `animations`) — 380ms avanti, 320ms back
- Transizioni modal: `FadeTransition` + `SlideTransition(Offset(0, 0.06))` — 420ms easeOutCubic
- Transizioni tab: `AnimatedSwitcher` + `FadeTransition` keyed su `routePath` — 220ms

**SocialScreen — Spotify-inspired (✅)**
- Griglia 2×2 Jam card con cover art gradient, initial letter, JAM badge
- Share invite via `share_plus` (codice invito + link download)
- FAB create + pulsante join nel header
- Sheets `_CreateJamSheet` e `_JoinJamSheet` estratti come StatelessWidget

**JamDetailScreen — Spotify-inspired (✅ questa sessione)**
- `_TrendingSection`: strip orizzontale dei 3 highlight più recenti, card con gradiente scuro, badge #1/#2/#3
- Invite code visibile direttamente nell'header espanso (pill tappabile → copia negli appunti)
- Share icon in `SliverAppBar.actions` → `share_plus` con messaggio formattato
- `_MembersStrip` migliorato: avatar con gradiente personalizzato per utente, dot "📖" se sta leggendo, `Tooltip` con titolo libro, bordo dorato per owner
- `_EmptyJamHighlights` potenziato: CTA primaria + card codice invito con pulsanti Copia / Condividi
- `_SharePickerSheet` completamente ridisegnato: search bar con clear button, list raggruppata per libro con header colorati (Taupe), contatore highlight per libro
- `SupabaseService.fetchJam(jamId)` aggiunto per recuperare invite_code e metadata Jam
- Padding bottom 120px su tutti gli screen per clearance floating nav

#### Prossima azione founder
- `dart run build_runner build` dopo qualsiasi modifica ai modelli Isar
- `flutter run -d windows` o `flutter run -d chrome` per smoke test

### Sessione 4 — 2026-05-11
**Durata**: ~1h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Codemagic setup (✅)**
- Onboarding completato: GitHub connesso, repo `marginalia`, tipo Flutter
- Bloccato su App Store Connect API key (account non iscritto ad Apple Developer Program)

**Flutter Web + GitHub Pages (✅)**
- `web/index.html` + `web/manifest.json` aggiunti (PWA-ready, palette sepia)
- `.github/workflows/deploy-web.yml`: build Flutter web + deploy su ogni push a `main`
- URL risultante: `https://vittoriopalpati811-ai.github.io/marginalia/`
- `AmazonLoginScreen` aggiornato con `kIsWeb` guard — su web mostra messaggio + redirect a import manuale

#### Prossima azione founder (1 click)
GitHub → repo marginalia → Settings → Pages → Source → "GitHub Actions" → Save
Poi fai un push qualsiasi su main e l'app web è live in ~3 minuti.

---

### Sessione 3 — 2026-05-10
**Durata**: ~3h
**Branch**: main
**Commit**: vedi git log

#### Fatto

**Pivot Swift → Flutter (✅ completo)**
- Rimosso tutto il codice Swift (`ios/` rimosso via git rm)
- Rimosso GitHub Actions + fastlane
- Aggiornato `.gitignore` per Flutter

**Flutter foundation (✅)**
- `pubspec.yaml`: tutte le dipendenze Flutter
- `lib/main.dart`: entry point con Supabase.initialize + Isar.open + ProviderScope
- `lib/app.dart`: MaterialApp.router con go_router (ShellRoute per bottom nav)
- `lib/core/theme.dart`: design tokens completi (palette, typography, ThemeData)

**Modelli Isar (✅)**
- `Book`, `Highlight`, `Tag`, `Jam` — tutti annotati con `@collection`
- Relazioni: Book→Highlights (IsarLinks + @Backlink), Highlight→Book (IsarLink), Highlight→Tags (IsarLinks)

**Parser (✅)**
- `lib/core/parser/my_clippings_parser.dart`: port completo da Swift
- Supporto EN/IT/FR, dedup, filtro bookmark, ordine cronologico

**Servizi (✅)**
- `ImportService`: parsing → dedup → scrittura Isar in transazione
- `AmazonSyncService`: stesso JavaScript extractor, adattato per `webview_flutter`
- `SupabaseService`: auth, books, highlights, jams, realtime, file upload

**Provider Riverpod (✅)**
- `isarProvider`, collections
- `authStateProvider`, `currentUserProvider`, `isAuthenticatedProvider`
- `booksProvider`, `highlightsByBookProvider`, `favoriteHighlightsProvider`, `randomHighlightProvider`
- `searchQueryProvider`, `searchResultsProvider`, `highlightFavoriteNotifierProvider`

**Screens (✅)**
- `LibraryScreen`: lista libri + card highlight del giorno + import file
- `BookDetailScreen`: lista highlight con color badge + condivisione
- `HighlightDetailScreen`: lettura full con tipografia Lora + toggle preferito
- `SearchScreen`: ricerca in-memory con highlighting del testo
- `SocialScreen`: Jam list + create + join + realtime
- `SettingsScreen`: account + sync Kindle + import manuale
- `AmazonLoginScreen`: WebView Amazon + extractor JS + stati (browsing/extracting/done/error)

**CI/CD (✅)**
- `codemagic.yaml`: build iOS cloud → TestFlight (no Mac richiesto)

**Documentazione (✅)**
- `CLAUDE.md`: aggiornato per Flutter pivot
- `ARCHITECTURE.md`: aggiornato, decisioni Swift marchiate SUPERATA
- `QUESTIONS.md`: dubbi SwiftData risolti, nuova entry 🔴 per setup Supabase+Codemagic

**Test (✅)**
- `test/parser/my_clippings_parser_test.dart`: 8 test case (EN/IT, dedup, bookmark filter)

#### Da fare (prossima sessione)
- Founder: setup Supabase + chiavi in `lib/main.dart` (vedi QUESTIONS.md)
- Founder: setup Codemagic (vedi QUESTIONS.md)
- `flutter run -d windows` per primo smoke test locale
- Auth screen (login/signup con Supabase)
- Widget home screen (WidgetKit → Flutter home widget via `home_widget` package)
- Supabase sync bidirezionale Isar↔cloud

#### Problemi incontrati
- `webview_flutter` non supporta Windows desktop: l'Amazon sync non è testabile su Windows.
  Per test locale su Windows, usare import da file `My Clippings.txt` invece.

### Sessione 1 — 2026-05-10
**Durata**: ~3h
**Branch**: main (prima sessione di setup)
**Commit**: vedi git log
**Mac access in questa sessione?**: NO

#### Fatto

**Architettura e struttura (TASK-001 ✅)**
- Monorepo ios/ + web/ + supabase/ + scripts/
- ARCHITECTURE.md creato con decisioni complete
- CLAUDE.md aggiornato con nuovo stack e vincoli
- .gitignore monorepo

**Database Supabase (TASK-DB ✅ — nuovo)**
- `supabase/migrations/001_initial_schema.sql` — schema completo
- `supabase/migrations/002_rls_policies.sql` — RLS per tutti i dati
- `supabase/functions/parse-clippings/index.ts` — Edge Function parsing (Deno)

**Web companion Next.js (TASK-WEB ✅ — nuovo)**
- Setup completo: package.json, tsconfig, tailwind, env.example
- Auth: magic link Supabase, middleware protezione routes
- Libreria: lista libri, book detail con highlights
- Import: upload My Clippings.txt drag&drop, polling risultato
- Jam: lista jam, creazione, join via codice, condivisione highlights
- Design: palette seppia/bianco caldo implementata in Tailwind

**iOS Swift (TASK-002, TASK-003, TASK-004, TASK-005, TASK-006, TASK-007, TASK-008, TASK-009, TASK-010 ✅)**
- Package.swift con targets Marginalia + MarginaliaWidgets
- Modelli SwiftData: Book, Highlight, Tag, Jam (con relazioni corrette + @Relationship)
- MyClippingsParser: IT/EN/FR, BOM, bookmark filter, dedup
- ImportService: dedup, idempotente
- Viste: LibraryView, BookDetailView, HighlightDetailView, SearchView, SocialView, RootView
- TabView con 4 tab (Libreria, Cerca, Jam, Impostazioni)
- Color(hex:) extension

**Fixture e test (TASK-003 ✅)**
- `ios/Tests/Fixtures/sample_clippings.txt` con 9 blocchi, 3 lingue, bookmark, dedup, nota
- ParserTests: 9 test cases che coprono tutti i casi del fixture

**Kindle sync Windows/Mac (TASK-SYNC ✅ — nuovo)**
- `scripts/kindle-sync.py` — polling drive, rilevamento My Clippings.txt, upload Supabase
- `scripts/requirements.txt` + `.env.example`

#### In progress
- Nessuna task aperta

#### Bloccato / domande
- Vedi QUESTIONS.md

#### Prossimo accesso Mac
Cose da verificare in ordine di priorità (per confidence sul codice):
1. **BASSA confidence**: `@Relationship` SwiftData su Tag (M:M) — sintassi non verificabile da Windows
2. **BASSA confidence**: `FetchDescriptor` con predicate annidato in BookDetailView (`$0.book.id`) — relazioni nested in `#Predicate` sono fragili
3. **MEDIA confidence**: `debounceTask` in SearchView (Task cancellation pattern) — corretto ma non testato
4. **ALTA confidence**: Parser, ImportService, Modelli base, Web app

#### Note per la prossima sessione
- Prima cosa: setup Supabase (crea progetto, esegui migrations, configura bucket)
- Seconda cosa: deploy Vercel con `.env.local` compilato → Vittorio può vedere tutto funzionare
- Terza cosa: testare upload My Clippings.txt dal web → Edge Function parsing
- iOS: rimanda a Mac access per compilazione reale

---

<!--
TEMPLATE per sessioni future. Copia/incolla SOPRA questa riga.

### Sessione N — [DATA]
**Durata**: ~Xh
**Branch**: feature/...
**Commit**: N (hash: abc123, def456, ...)
**Mac access in questa sessione?**: SÌ / NO

#### Fatto
- TASK-XXX: descrizione breve di cosa hai effettivamente prodotto
  - File toccati: ...
  - Test scritti: N

#### In progress
- TASK-YYY: a che punto sei, cosa manca

#### Bloccato / domande
- Vedere QUESTIONS.md voci [DATA]

#### Errori di compile/runtime trovati (solo se sessione su Mac)
- ...

#### Note per la prossima sessione
- Cosa guardare per primo
- Eventuali rischi tecnici emersi

-->
