# Progress Log

> Diario delle sessioni. Claude aggiorna questo file a fine sessione.
> Sessioni più recenti IN ALTO. Le task completate restano qui per storico.

---

## 📌 Stato attuale del progetto

**Fase**: Flutter MVP — Airbnb redesign completo + Jam 2.0 + i18n + notifiche
**Sprint corrente**: Sprint 1 (Flutter) — Foundation + UX + Social + Monetizzazione + i18n + Jam 2.0
**Prossima azione founder**:
  1. Applicare **024_favorite_books.sql** in Supabase SQL Editor
  2. Applicare migrations **020–023** in ordine (se non già fatto)
  3. Eseguire `flutter pub get && flutter gen-l10n`
  4. (Opzionale) Deploy push notifications: `supabase secrets set APNS_*` + `supabase functions deploy send-push-notification`
  5. Creare account RevenueCat → inserire API key in `subscription_service.dart`
**Branch attivo**: master
**Build status Flutter/Windows**: 🟡 pronto — esegui `dart run build_runner build` poi `flutter run -d windows`
**Build status iOS (TestFlight)**: 🔴 bloccato — Apple Developer Program non attivo (vedi QUESTIONS.md)

**Infrastruttura cloud**:
- Supabase `marginalia`: ✅ operativo (`https://ibucvloawkfwobaelwbr.supabase.co`)
- Codemagic: ✅ app creata, repo connesso, tipo Flutter impostato
- App Store Connect API key: 🔴 manca (richiede Developer Program)

**Migrations da applicare (in ordine)**:
- ⚠️ `017_realtime_messages.sql` — abilita Realtime su messages + conversations
- ⚠️ `018_comment_likes_replies.sql` — like commenti, risposte threading, fix bucket comment-images
- ⚠️ `019_*` — (se presente)
- ⚠️ `020_jam_book_voting.sql` — tabelle book proposals + votes + `is_jam_member()` helper
- ⚠️ `021_jam_challenges.sql` — tabelle challenges + progress
- ⚠️ `022_jam_highlight_polls.sql` — tabelle polls + candidates + votes
- ⚠️ `023_notifications.sql` — tabelle notifications + device_tokens

---

## Sessioni

### Sessione 18 — 2026-05-24
**Durata**: ~1h
**Branch**: master
**Commit**: `c0fff9a`

#### Fatto

**Home tab — Redesign Airbnb-style discovery (✅)**

`lib/features/social/home_tab.dart` completamente riscritto. La vecchia home (FeedTab) sostituita con 3 sezioni editoriali:

**§1 — Frase di oggi**
- `_todayHighlightProvider`: deterministico, cambia 4× al giorno (bucket orario `hour ~/ 6` = notte/mattina/pomeriggio/sera)
- Lista highlights ordinata per `addedAt` → indice `(dayOfYear * 4 + bucket) % count` — stabile per tutta la sessione
- Hero card con gradiente matcha (`MarginaliaDecorations.heroCard`), EB Garamond italic crema, hairline rule, attribution
- Tag contestuale (🌤 mattina / ☀️ pomeriggio / 🌆 sera / 🌙 notte) in pill verde accanto al titolo sezione

**§2 — Frasi recenti**
- `_recentHighlightsProvider`: ultimi 12 highlights ordinati per `addedAt` desc
- Scroll orizzontale, card 192×150 con sfondo lievemente tintato dal colore Kindle (yellow/blue/pink/orange → alpha 38)
- Tinting con `Color.alphaBlend(kindleColor.withAlpha(38), surface)` — funzionale non decorativo
- EB Garamond italic, titolo libro in ALL CAPS faint in basso

**§3 — Torna a sfogliare (libri consigliati)**
- `_recommendedBooksProvider`: algoritmo content-based TF-IDF-like, puro Dart, nessuna AI:
  1. Prende i 20 highlight più recenti → "interessi attuali"
  2. Estrae le top-15 parole tematiche (≥5 chars, filtro stop-word IT+EN)
  3. Raggruppa tutti gli highlight per titolo libro (platform-agnostic: usa `bookTitle` non Isar ID)
  4. Assegna uno score ad ogni libro NON letto di recente: quante parole tematiche compaiono nei suoi highlight
  5. Restituisce top-5 ordinati per score
- Scroll orizzontale, card 124px con `BookEditorialCover` + titolo + badge "N parole in comune"
- Sezione nascosta se score = 0 su tutti i libri (utente ha un solo libro, ecc.)

**Architettura provider**
- Tutti e 3 i provider sono `autoDispose`, derivano da `allHighlightsProvider` + `booksProvider` (nessuna query Isar extra)
- Pull-to-refresh invalida tutti e 5 i provider (inclusi quelli base)
- Skeleton loading per ogni sezione; empty state con `"` decorativo per §1 e §2
- Platform-agnostic: algoritmo usa `bookTitle` (disponibile su Isar native e Supabase web join)
- Stop-word list integrata: 80+ termini italiani + inglesi comuni

---

### Sessione 17 — 2026-05-24
**Durata**: ~1h
**Branch**: master
**Commit**: `d3e3f27`

#### Fatto

**Profilo — Post Instagram-style (✅)**
- `profile_shared_widgets.dart` (nuovo file): widget pubblici condivisi tra `MyProfileScreen` e `UserProfileScreen`:
  `FavBooksGrid`, `FavBookTile`, `FavTileSize`, `PostsGrid`, `PostGridTile`, `PostDetailSheet`
- Post ora visualizzati come griglia 3 colonne quadrate (stile Instagram), non più card verticali Twitter
- `PostGridTile`: background colorato con tinta da `kPostBgColors`, preview text in basso, freccia chevron, tap → `PostDetailSheet`
- `PostDetailSheet` generica: timestamp, body text, highlight snippet (box stilizzato), immagine, like count

**Profilo — Pulsante "Scrivi" post (✅)**
- Intestazione POST ha ora pulsante pill "Scrivi" in alto a destra
- Tap apre `CreatePostSheet` (importato da `feed_tab.dart`); su `onCreated` invalida `_myPostsProvider` per refresh immediato

**Profilo — Pull-to-refresh (✅)**
- `RefreshIndicator` (sienna) avvolge il `CustomScrollView`
- `onRefresh` invalida: `_myProfileProvider`, `_myBooksProvider`, `_myStatsProvider`, `_myPostsProvider`, `_mySpotlightProvider`
- Resetta anche `_favBooksProvider` a `[]` perché il listener di `_myProfileProvider` lo ri-popola dal server

**Profilo pubblico — Libri del cuore (✅)**
- `UserProfileScreen` legge `profile['favorite_books']` e mostra `FavBooksGrid(favBooks: favs)` read-only prima della sezione POST
- Nascosto automaticamente se la lista è vuota o assente

**Widget Scriptable — Carta Invecchiata redesign (✅)**
- Tema completamente rifatto: sfondo crema caldo (#F6EFDF → #EDE4CC), inchiostro scuro (#1C1008), accento sienna (#8B4515)
- Nessun pannello glass: il testo `Georgia-Italic` scuro si appoggia direttamente sulla carta
- Opening quote `"` in sienna su ogni size; greeting `Georgia-Italic` molto sbiadito (faint) sul medium/large
- Hairline rule sienna (0.22 alpha) tra quote e attribution
- Mantenuti: `localGreeting()` con giorno-settimana, `fetchWeather()`, refresh 45 min

#### Prossima azione founder
- ⚠️ Applicare `supabase/migrations/024_favorite_books.sql` nel SQL Editor (se non già fatto)

---

### Sessione 16 — 2026-05-24
**Durata**: ~2h
**Branch**: master
**Commit**: `b9af21f`

#### Fatto

**Libreria — Saluti contestualizzati (✅)**
- `contextualGreeting(name, {hour})` computa frase in base all'orario del dispositivo:
  "Così presto", "Buongiorno", "Prenditi una pausa", "Buon pomeriggio", "Buonasera", "Buonanotte"
- `_myDisplayNameProvider` FutureProvider per il nome dell'utente (riusa `fetchPublicProfile`)
- `_EditorialHeader` aggiornato: riceve `userName` dal provider e lo passa a `contextualGreeting`

**App nav — Jam tab + Liquid glass (✅)**
- Outline Jam tab (index 2): 1.8pt verde (`MarginaliaColors.primary`) + semi-trasparente quando inattivo
- Liquid glass zoom su nav pill: `LayoutBuilder` → `Float64List(16)` matrice 4×4 scale 1.12× centrata,
  composita con `ImageFilter.blur(22,22)` — effetto iOS 26

**Status bar — Fix notch (✅)**
- `main.dart`: `SystemChrome.setEnabledSystemUIMode(edgeToEdge)` + overlay style globale dark icons
- `jam_detail_screen.dart`: `systemOverlayStyle` light su `SliverAppBar` + scrim top → status bar sempre visibile

**Profilo — 6 Libri del cuore (✅)**
- `_FavoriteBooksSection`: header "LIBRI DEL CUORE" + pulsante Scegli/Modifica
- `_FavBooksGrid`: griglia masonry Pinterest — riga 1: big left (55%) + 2 stacked mediums (45%);
  riga 2: tre small uguali
- `_FavBookTile`: `BookEditorialCover` + overlay gradiente + testo adattato per tile size (large/medium/small)
- `_openFavBooksSheet` + `_FavBooksSheet`: picker con mini cover, checkbox animato circolare,
  contatore animato 0/6→6/6
- `SupabaseService.updateFavoriteBooks()`: persiste la lista a Supabase
- Migration **024** `favorite_books` (jsonb, default `[]`) — **applicare manualmente in SQL Editor**

**Widget Scriptable — Liquid glass + saluto locale (✅)**
- `localGreeting()`: saluto calcolato live dal clock del dispositivo + giorno settimana
  (Buon lunedì, Buon weekend, ecc.) — non più stale
- Refresh ridotto da 4h a **45 min** (meteo + saluto sempre aggiornati)
- Glass panel: frosted card attorno alla citazione con `backgroundColor = Color(0.10 alpha)` +
  edge speculare top da `Color(0.18 alpha)` — evoca iOS 26 liquid glass

#### Prossima azione founder
- ⚠️ Applicare `supabase/migrations/024_favorite_books.sql` nel SQL Editor
- ⚠️ Applicare migrations 020–023 (se non già fatto)

---

### Sessione 15 — 2026-05-23
**Durata**: ~1.5h
**Branch**: master
**Commit**: `c570226`

#### Fatto

**Airbnb redesign — Nav bar (✅)**
- `_FloatingNavBar` (pill matcha verde, floating) sostituito con `_AirbnbNavBar` (flat, bianco, bordo top 0.5px)
- `_ScaffoldWithNav` downgradato da `StatefulWidget` a `StatelessWidget` — rimossi `AnimationController`, `scroll-hide`, `SingleTickerProviderStateMixin`
- Ogni tab: icona 24px + gap 3px + label 9px Manrope — selected = `primary` matcha, unselected = `inkFaint`
- `AnimatedSwitcher` sull'icona con scale 0.82→1.0 ease-out-cubic + FadeTransition
- `AnimatedDefaultTextStyle` sul label (180ms, ease-out) per color interpolation
- Aggiunte label ai tab: 'Home', 'Libreria', 'Cerca', 'Jam', 'Messaggi', 'Profilo'

**Airbnb redesign — Tipografia globale (✅)**
- Barlow + BarlowCondensed → Manrope in tutti i 18 screen (rimossi 0 riferimenti residui)
- EB Garamond → Manrope per UI chrome (AppBar title, empty state heading, sheet title) in:
  - jam_book_voting_screen.dart, jam_challenge_screen.dart, jam_poll_screen.dart, notifications_screen.dart
- **Preservato** EB Garamond per contenuto letterario: italic highlight quotes in jam_poll, quote display in feed/chat/widget_preview/share_card
- AppBar titles: w800 letterSpacing -0.5; empty states: w700 -0.3; sheet titles: w800 -0.4
- `theme.dart` aggiornato (Sessione 14): Manrope per tutto UI, EB Garamond solo per highlightBody/quoteDecor

#### Note tecniche
- `_AirbnbNavBar` usa `SafeArea(top: false)` + `SizedBox(height: 52)` — compatibile con iPhone home indicator
- `extendBody: true` preservato nel Scaffold per evitare problemi con FAB nelle tab
- Font import google_fonts aggiunto in app.dart per `GoogleFonts.manrope()` nel nav bar

---

### Sessione 14 — 2026-05-23
**Durata**: ~2h
**Branch**: master
**Commit**: `cbe5613`

#### Fatto

**Jam 2.0 — Feature 4: Member profile sheet (✅)**
- Tap avatar in `_MembersStrip` → `DraggableScrollableSheet` con profilo membro
- Mostra avatar (gradiente + iniziale), owner badge dorato, display name, @username
- Card "In lettura" con titolo + autore (se disponibili)
- Bottone "Visualizza profilo" → push `/user/:id` con Navigator.pop + context.push
- Callback `onTapMember` aggiunto a `_MembersStrip` (breaking change interno, solo uso locale)

**Jam 2.0 — Feature 5: Notifiche (✅)**
- `notifications_screen.dart`: lista notifiche con dot non-letti, mark-as-read al tap, "Segna tutto come letto" in AppBar
- Bell icon + dot rosso unread nel SliverAppBar di `JamDetailScreen` → push `/notifications`
- `unreadNotificationCountProvider` watchato nel build per badge live
- TODO documentato in `app.dart` per device token registration (richiede plugin nativo APNs)

**Jam 2.0 — Integrazione feature cards (✅)**
- Row "ATTIVITÀ" con 3 card animate (fadeIn + slideX staggerato) in `JamDetailScreen`
- Card: 📖 Libro del mese → `/jam/:id/voting`, 🏆 Sfide → `/jam/:id/challenges`, 🗳 Sondaggi → `/jam/:id/polls`
- Navigazione via `context.push()` (go_router)

**Router (✅)**
- 5 nuove route in `app.dart`: `/jam/:id/voting`, `/jam/:id/challenges`, `/jam/:id/polls`, `/notifications`
- Tutti usano `_pushPage` (shared axis horizontal transition)

**i18n (✅)**
- 13 nuove chiavi ARB in IT + EN: `jamFeature*` (6 chiavi), `jamMemberCurrentlyReading`, `notifications*` (4 chiavi)
- Total ARB keys: ~120 per locale

#### Note tecniche
- `is_jam_member()` SQL function creata in migration 020, riutilizzata in 021 + 022 — applicare in ordine
- APNs push via Edge Function Deno con ECDSA P-256 JWT — documentato in `supabase/functions/send-push-notification/index.ts`
- RevenueCat non integrato (skip su richiesta founder — darà errori se non si ha la API key)

#### Azioni da fare (founder)
1. `flutter gen-l10n` (13 nuove chiavi)
2. Applicare migrations 020–023 in Supabase SQL Editor in ordine
3. Opzionale: `supabase secrets set APNS_TEAM_ID=… APNS_KEY_ID=… APNS_PRIVATE_KEY=… APNS_BUNDLE_ID=…`
4. Opzionale: `supabase functions deploy send-push-notification`

---

### Sessione 13 — 2026-05-23
**Durata**: ~1h
**Branch**: master
**Commit**: `fd3f91e`

#### Fatto

**Language selection pre-step in onboarding (✅)**
- Nuova schermata mostrata PRIMA del PageView a 7 step — l'utente sceglie la lingua al primo avvio.
- `_LanguageStep`: wordmark EB Garamond 44px, riga sottile, prompt Barlow "Choose your language" — tutto con `flutter_animate` fadeIn + slideY staggerato (100–600ms delay).
- `_LangCard`: carte animate con `AnimatedContainer` scale (1.04 selected, 0.96 disabled, 1.0 idle) + `AnimatedOpacity` (0.35 disabilitato). Flag emoji 36px + nome nella propria lingua + sottotitolo nell'altra.
- `AnimatedSwitcher` con `FadeTransition` + `SlideTransition(Offset(0, 0.04))` per transizione morbida lingua → onboarding.
- `HapticFeedback.lightImpact()` al tap + 160ms delay per rendere visibile la press-state prima del cambio.

**Locale infrastructure (✅)**
- `lib/core/services/locale_service.dart`: persiste il codice lingua in `.marginalia_locale` nella app documents directory (dart:io, stesso pattern di OnboardingService).
- `lib/core/providers/locale_provider.dart`: `StateProvider<Locale>` inizializzato via `ProviderScope.overrides` al launch.
- `lib/core/storage/app_startup_native.dart`: aggiunto `LocaleService.getLocale()` al `Future.wait` parallelo (zero overhead — gira in parallelo con Isar open + onboarding check).
- `lib/app.dart`: watch `localeProvider` → `locale:` passato a entrambi i `MaterialApp`.

#### Prompt per sessioni future (da usare come base per i prossimi Claude)

**Prompt 1 — Paywall gates** (nota: `subscription_service.dart`, `subscription_provider.dart`, `paywall_screen.dart` esistono già — solo i gate mancano):
- Gate ImportService: se `highlightCount >= 200` e non premium → push PaywallScreen
- Gate JamCreationScreen: se non premium → show paywall prima del form
- Gate Jam messaging/post creation: se non premium → show paywall

**Prompt 2 — Jam 2.0** (⚠️ migration deve iniziare da `020_jam_book_club.sql` — `019` già usato):
- Feature 1: Book of the month voting
- Feature 2: Reading Challenge
- Feature 3: Weekly highlight poll
- Feature 4: Member profile sheet
- Feature 5: In-app notifications

#### Azioni da fare (founder)
1. `flutter pub get && flutter gen-l10n`
2. In `lib/app.dart` decommentare le due righe ★ (import + delegate AppLocalizations)
3. `flutter run -d windows` per smoke test

---

### Sessione 12 — 2026-05-23
**Durata**: ~2h
**Branch**: master
**Commit**: `8b874a5`

#### Fatto

**i18n — sostituzione stringhe hardcoded (✅)**
- Creato `lib/core/l10n/l10n_extension.dart`: extension `BuildContext.l10n` che espone `AppLocalizations.of(context)!` come `context.l10n`
- Aggiunti 4 nuovi ARB key a IT + EN: `libraryNoFavorites`, `libraryNoFavoritesBody`, `libraryImportClippings`, `libraryTryDemo`
- Screen aggiornate con `context.l10n.*`:
  - **`search_screen.dart`**: titolo "Persone", sottotitolo "lettori · autori", hint barra, empty state, no-results
  - **`amici_tab.dart`**: sezioni "SEGUITI"/"SUGGERITI", bottoni "Segui"/"Smetti", empty state "Nessun amico ancora"
  - **`library_screen.dart`**: header sezione, empty state libro + preferiti, CTA import + demo
  - **`settings_screen.dart`**: "Modifica profilo", "Esci dall'account", schermata non-autenticata
  - **`feed_tab.dart`**: schermata non-autenticata, "Nessun commento ancora"
  - **`messages_screen.dart`**: titolo header, "Nessuna conversazione"
  - **`social_screen.dart`**: "Nessuna Jam ancora", schermata non-autenticata
  - **`my_profile_screen.dart`**: schermata non-autenticata
- `lib/app.dart`: commento aggiornato con istruzioni in 3 step per attivare `AppLocalizations.delegate`

**Stato i18n**: infrastruttura completa (ARB 80+ chiavi IT+EN, extension, delegate pronto).
Rimane da fare (1 comando): `flutter pub get && flutter gen-l10n` + decommentare delegate + import in `app.dart`.
Stringhe NON ancora localizzate: `paywall_screen.dart` (hardcoded per ora — le chiavi ARB esistono), `jam_detail_screen.dart`, `book_detail_screen.dart`, `highlight_detail_screen.dart`, `user_profile_screen.dart` (follow/unfollow button), `auth_screen.dart`.

#### Azioni da fare (founder)
1. `flutter pub get && flutter gen-l10n`
2. In `lib/app.dart`, aggiungere import `package:flutter_gen/gen_l10n/app_localizations.dart` e decommentare `AppLocalizations.delegate`
3. `flutter run -d windows` per verificare compilazione

---

### Sessione 11 — 2026-05-22
**Durata**: ~3h
**Branch**: master
**Commits**: `dfadf5b` → `e52287d` (6 commit)

#### Fatto

**Fix messaggi duplicati in chat (✅)**
- Root cause: messaggi ottimistici in `_localMessages` non venivano rimossi dopo invio con successo
- Fix: `_localMessages.removeWhere(...)` nel path di successo; dedup filtra solo messaggi con prefisso `optimistic_` non ancora confermati dal server
- Realtime Supabase aggiunto: canale Postgres sul tavolo `messages` per la conversazione corrente — i messaggi in arrivo appaiono istantaneamente senza refresh manuale

**Fix badge non letti (✅)**
- Il pallino era visibile per tutte le conversazioni con messaggi; ora compare solo se `last_message.created_at > my_last_read_at` e il mittente non è l'utente corrente
- Testo anteprima in grassetto + colore più scuro per conversazioni non lette
- `markConversationRead()` chiamato all'apertura della chat via `addPostFrameCallback`
- `fetchConversations()` arricchito con `my_last_read_at` e `current_user_id`

**Invio foto in chat (✅)**
- `FilePicker` seleziona immagine dalla galleria → `uploadMessageImage()` carica su bucket `message-images` → URL inviato come `imageUrl` nel messaggio
- `uploadMessageImage()` aggiunto a `SupabaseService`

**GIF picker (✅ — 3 iterazioni)**
- v1: GIPHY con public beta key → v2: Reddit JSON API (fallito: Reddit converte GIF in MP4/APNG non animabili da Flutter) → v3: **Tenor v2 con `LIVDSRZULELA`** (chiave pubblica documentata da Tenor, nessuna registrazione)
- `giphy_picker.dart` (rinominata funzione pubblica `showGifPicker`): trending alla apertura, ricerca su `tenor.googleapis.com/v2/search`, `tinygif` per thumbnail animate nella griglia, `gif` full-res da inviare
- Picker condiviso tra chat e commenti post
- Sostituzione Tenor vecchio in `feed_tab.dart` (rimossa classe `_GifPickerSheet` + `_kTenorApiKey`)

**Migration 017 — Realtime (✅)**
- `ALTER PUBLICATION supabase_realtime ADD TABLE messages` + `conversations`
- Resa idempotente con DO $$ block che controlla `pg_publication_tables`

**Like ai commenti (✅)**
- `comment_likes` table con RLS (SELECT autenticati, INSERT/DELETE proprio utente)
- `_CommentBubble` → `ConsumerStatefulWidget` con toggle ottimistico cuore + contatore
- `likeComment()` / `unlikeComment()` in `SupabaseService`
- `fetchPostComments()` restituisce `like_count` e `has_liked` per ogni commento (parallel fetch likes + profiles)

**Risposte ai commenti (✅)**
- `parent_comment_id` aggiunto a `post_comments` (FK self-referential)
- UI: commenti top-level + risposte indentate 40px sotto il padre
- Banner "Rispondendo a [nome] ×" sopra l'input con hint dinamico nel campo testo
- `addPostComment()` accetta `parentCommentId` opzionale

**Fix immagini commenti non caricavano (✅)**
- `errorBuilder` sostituisce `SizedBox.shrink()` con icona broken-image visibile
- `loadingBuilder` mostra spinner durante caricamento
- Migration 018 re-imposta bucket `comment-images` come pubblico con policy SELECT esplicita (era la causa principale)

**Migration 018 — Comment likes + reply threading (✅)**
- `parent_comment_id` su `post_comments`
- Tabella `comment_likes` con RLS
- Re-assert policy storage `comment-images` (idempotente)

#### Azioni da fare (founder)
1. **SQL Editor Supabase** → esegui `supabase/migrations/017_realtime_messages.sql`
2. **SQL Editor Supabase** → esegui `supabase/migrations/018_comment_likes_replies.sql`
3. `flutter run -d windows` per smoke test

---

### Sessione 10 — 2026-05-21
**Durata**: ~3h
**Branch**: main
**Commit**: `1d52522`

**Fix critici**:
- ✅ **Errore RLS conversations (42501)**: fix chicken-and-egg tra conversations e conversation_members. Creato SECURITY DEFINER RPC `create_direct_conversation` e `create_group_conversation` — il Dart ora chiama l'RPC invece di inserire direttamente.
- ✅ **Security hardening completo**: migration 016 con RLS granulari per TUTTI i tavoli (highlights, books, posts, post_comments, post_likes, follows, profiles, conversation_members). Author-only UPDATE/DELETE su posts a livello DB.
- ✅ **Indici DB**: aggiunto indexes su posts, likes, comments, follows, highlights per ridurre query plan cost.

**Nuove feature**:
- ✅ **Post 3-dot menu**: autore vede "Modifica" + "Elimina" (con conferma dialog), altri vedono "Segnala". Edit funziona inline via dialog.
- ✅ **Reading status sui post**: accanto al nome utente nei post appare "· [icona libro] [titolo libro]" se l'utente ha impostato `currently_reading_title`.
- ✅ **Email Marginalia-branded**: template HTML personalizzati per reset password e conferma signup (niente riferimenti a Supabase). File in `supabase/email_templates/`.
- ✅ **Reset onboarding (DEV)**: opzione nascosta nelle settings, visibile solo in `kDebugMode`, che cancella il marker file e ripresenta l'onboarding.

**Stress test**:
- ✅ Script Python asyncio in `stress_test/stress_test.py`: simula 500 utenti reali in 10 minuti (signup, profilo, post, follow, like, commenti, DM). MAX_CONCURRENCY=80, stagger distribuito. Cleanup opzionale via service role key.

**Da fare prima del prossimo sprint**:
1. **Applicare migration 016** nel Supabase Dashboard → SQL Editor (incolla `supabase/migrations/016_security_hardening.sql`)
2. **Email templates**: Dashboard → Authentication → Email Templates → incolla HTML da `supabase/email_templates/`
3. **Test chat**: dopo migration 016, aprire una nuova conversazione deve funzionare senza errori
4. **Stress test**: `pip install httpx && python stress_test/stress_test.py`

---

### Sessione 9 — 2026-05-17
**Durata**: ~1.5h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Fix compilazione `svc._client` privato (✅)**
- `followers_screen.dart` accedeva a `svc._client` direttamente → non compilabile
- Aggiunto `fetchUserBooks(String targetId)` a `SupabaseService` come metodo pubblico
- `followers_screen.dart` aggiornato per usare il nuovo metodo

**Profilo: stats cliccabili + foto profilo/copertina (✅)**
- `my_profile_screen.dart`: `_StatsRow` ora accetta callback `onFollowers`, `onFollowing`, `onBooks` — tap apre `showProfileList` con il tipo corretto
- `_StatBox` con `onTap` → valore + label colorati di verde matcha quando tappabile
- `_ProfileHeader` completamente riscritta:
  - Se `cover_url` è settata mostra `Image.network` come sfondo, altrimenti il gradiente
  - Badge "Copertina" in basso a destra del cover → tap chiama `onCoverTap`
  - Avatar mostra `Image.network(avatarUrl)` se disponibile, altrimenti gradiente iniziale
  - Badge fotocamera (cerchio verde) in basso a destra dell'avatar → tap chiama `onAvatarTap`
- `_MyProfileScreenState`:
  - `_pickAndUploadAvatar()` / `_pickAndUploadCover()` via `FilePicker.platform.pickFiles(type: FileType.image)` → `svc.uploadAvatar/uploadCover` → `ref.invalidate(_myProfileProvider)`
  - Indicatori di caricamento mentre upload in corso

**Highlight in evidenza (pinned) sul profilo (✅)**
- Nuovo file `lib/features/profile/pinned_highlights_section.dart` (~280 righe):
  - `pinnedHighlightsProvider` (family<String>) → `svc.fetchPinnedHighlights(userId)`
  - `PinnedHighlightsSection` widget con header "IN EVIDENZA" + bottone "Modifica"
  - `_PinnedCard`: stessa card style del feed, accent strip colore Kindle
  - `_EditPinnedSheet` (`DraggableScrollableSheet`): lista di tutti gli highlight locali (solo quelli con `supabaseId`), checkbox interattivi, max 3 selezionabili, bottone Salva → `svc.updatePinnedHighlights(ids)` → invalidate provider
- Integrato in `my_profile_screen.dart` come sliver tra Spotlight e Libreria

**Feed: post reali + creazione post (✅)**
- `supabase/migrations/006_avatar_pinned_posts.sql`: tabelle `pinned_highlights`, `posts`, `post_likes` con RLS + index su `created_at`
- `supabase/seed_posts.sql`: 10 post dummy dai 5 utenti dummy (testo libero + highlight allegato, timestamp da 1h a 5gg fa)
- `SupabaseService.togglePostLike()` semplificato: insert/delete su `post_likes` + recompute count dal table count
- `feed_tab.dart` completamente riscritto:
  - `postsProvider` → `svc.fetchPosts()` (own + following, newest first)
  - `feedProvider` → `svc.fetchFeed()` (legacy shared highlights)
  - Due sezioni distinte: "POST" in testa, "HIGHLIGHT CONDIVISI" sotto
  - `_PostCard` (ConsumerStatefulWidget): avatar con `Image.network` se disponibile, body testo, highlight allegato con accent strip, bottone like con animazione ottimistica, timestamp relativo
  - `_CreatePostSheet`: bottom sheet con `TextField` multilinea, contatore 1000 chars, bottone "Pubblica" → `svc.createPost(body: text)` → invalidate provider
  - `_CreatePostFab`: FAB verde matcha "Scrivi" posizionato via `Positioned` dentro `Stack` (non in `Scaffold` per compatibilità con la shell nav)

#### Prossima azione founder
1. Esegui `supabase/migrations/006_avatar_pinned_posts.sql` nel SQL Editor Supabase
2. Esegui `supabase/seed_posts.sql` per vedere i post dummy nel feed
3. Per avatar/copertina: crea i bucket Storage `avatars` e `covers` (pubblici) dal dashboard Supabase
4. `flutter run -d windows` o `flutter run -d chrome` per smoke test

---

### Sessione 8 — 2026-05-17
**Durata**: ~1.5h
**Branch**: main
**Mac access in questa sessione?**: NO

#### Fatto

**Onboarding interattivo — primo avvio (✅)**
- `lib/core/services/onboarding_service.dart` + `_native.dart` + `_web.dart`: flag "onboarding completato" scritto come file marker `.onboarding_complete` in `getApplicationDocumentsDirectory()` su native; stub su web (sempre skip)
- `lib/core/providers/onboarding_provider.dart`: `StateProvider<bool>` inizializzato al launch via `ProviderScope.overrides`
- `lib/core/storage/app_startup_native.dart`: `Future.wait([Isar.open(...), OnboardingService.isComplete()])` in parallelo — aggiunto override `onboardingCompleteProvider`
- `lib/features/onboarding/onboarding_screen.dart` (~220 righe): schermata 3-slide con `PageView`, `AnimatedContainer` per gradiente di sfondo animato tra i colori delle slide, dot indicator con pill animata, animazioni `flutter_animate` (fadeIn + slideY staggered per icona/titolo/body), bottone "Avanti"→"Inizia a leggere", link "Salta" in alto a destra (nascosto sull'ultima slide)
  - Slide 1: Bentornato tra le pagine (gradiente seppia)
  - Slide 2: Importa in un tocco (gradiente foresta)
  - Slide 3: Leggi insieme / Jam (gradiente oceano)
- `lib/app.dart`: `MarginaliaApp` ora è `ConsumerWidget`; se `!onboardingComplete` mostra `MaterialApp(home: OnboardingScreen)`, altrimenti `MaterialApp.router` come prima. Flippare il provider causa rebuild automatico → router parte da `/` (LibraryScreen)

**Export Markdown degli highlight (✅)**
- `lib/core/services/export_file_writer.dart` + `_native.dart` + `_web.dart`: conditional export che isola `dart:io`; native scrive file `.md` in tmp e usa `Share.shareXFiles`; web usa `Share.share` text-only
- `lib/core/services/export_service.dart` (~180 righe, nessun `dart:io` diretto):
  - `buildBookSection(bookTitle, bookAuthor, highlights)` → sezione Markdown con quote block, metadata posizione/data, nota personale
  - `buildFullMarkdown(List<Highlight>)` → documento completo con header, totale highlight/libri, auto-grouped per bookTitle, ordinati cronologicamente; cross-platform grazie ai getter `bookTitle`/`bookAuthor` già presenti su entrambi i modelli (Isar + web)
  - `buildSingleBookMarkdown(...)` → export singolo libro con header dedicato
  - `exportAll(highlights)` e `exportBook(bookTitle, bookAuthor, highlights)` come API pubblica
- `lib/features/settings/settings_screen.dart`: nuovo `_SettingsTile` "Esporta in Markdown" → `_exportAllHighlights()` usa `allHighlightsProvider.future` (cross-platform, book links già caricati) + snackbar di loading + gestione errori
- `lib/features/library/book_detail_screen.dart`: bottone download sovrapposto all'hero (in alto a destra, stessa card del back button) → `ExportService.exportBook(...)` per libro singolo

#### Prossima azione founder
1. `flutter run -d windows` o `-d chrome` per smoke test onboarding (cancella `.onboarding_complete` dalla cartella docs per rivederlo)
2. Testare export su device iOS — il `.md` deve aprirsi in Obsidian / Notes / Files
3. Per resettare l'onboarding su Windows dev: cancella il file `.onboarding_complete` nella cartella documenti dell'app

---

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
