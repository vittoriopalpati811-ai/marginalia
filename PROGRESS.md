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
