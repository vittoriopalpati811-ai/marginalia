# Marginalia — Architecture

> Documento vivo. Aggiornalo quando prendi decisioni architetturali significative.
> Decisioni superate: aggiungi "SUPERATA" e il motivo, non cancellare.

---

## 1. Panoramica sistema

```
┌──────────────────────────────────────────────────────────────────┐
│                         UTENTE FINALE                            │
│                                                                  │
│       iPhone / iPad                    Kindle (WiFi sync)        │
│       ┌──────────────────┐            ┌──────────────────┐       │
│       │  Flutter App     │            │  Amazon Cloud    │       │
│       │  (iOS build)     │◄──────────►│  read.amazon.com │       │
│       │  Isar (offline)  │  WebView   │  /kp/notebook    │       │
│       └────────┬─────────┘  + JS      └──────────────────┘       │
│                │                                                  │
└────────────────┼──────────────────────────────────────────────────┘
                 │
      ┌──────────▼──────────┐
      │     SUPABASE        │
      │  Auth               │
      │  PostgreSQL DB      │
      │  Storage            │
      │  Realtime (Jam)     │
      └─────────────────────┘

Distribuzione:
  Windows → git push → Codemagic (macOS cloud) → build IPA → TestFlight → iPhone
```

---

## 2. Componenti

### 2a. Flutter App (`lib/`)
- **Framework**: Flutter 3.22+, Dart 3.3+
- **Target primario**: iOS 17+ (distribuito via App Store / TestFlight)
- **Development**: Windows desktop / Chrome (`flutter run -d windows`)
- **Architettura**: Feature-first con Riverpod providers
- **Persistenza locale**: Isar 3.x (offline-first, NoSQL embedded)
- **Navigation**: go_router con ShellRoute (bottom nav 4 tab)
- **Animazioni**: flutter_animate + Impeller engine
- **Tipografia**: google_fonts (Lora serif per highlights, system-ui per UI)

### 2b. ~~iOS App Swift~~ — SUPERATA 2026-05-10
**Rimossa**: il founder sviluppa su Windows → impossibile compilare Swift.
**Sostituita da**: Flutter (cross-platform, gira nativamente su Windows per development).

### 2c. ~~Web Companion Next.js~~ — SUPERATA 2026-05-10
**Rimossa**: il prodotto è un'app iOS, non un sito web.

### 2d. Supabase (`supabase/`)
- **DB**: PostgreSQL con RLS
- **Auth**: email + password. Magic link in roadmap.
- **Storage**: bucket `clippings` per file .txt, bucket `avatars`
- **Edge Functions**: `parse-clippings` (Deno) — parsa My Clippings.txt server-side
- **Realtime**: canali Jam per highlight condivisi in real-time
- **Free tier**: 500MB DB, 1GB storage, 200 connessioni realtime — ok per MVP

### 2e. CI/CD — Codemagic
- **Trigger**: push su `main`
- **Runner**: macOS cloud (Codemagic gestisce macchine Apple Silicon)
- **Certificati**: Codemagic gestisce il keychain automaticamente (integrazione App Store Connect)
- **Output**: IPA → TestFlight → installabile su iPhone in ~20 min
- **Costo**: 500 min/mese gratis (build ~8-10 min → ~50 build/mese)
- **Config**: `codemagic.yaml` nella root del repo

### 2f. ~~GitHub Actions + fastlane~~ — SUPERATA 2026-05-10
**Rimosso**: sostituito da Codemagic che è specializzato Flutter e non richiede fastlane.

---

## 3. Schema database (Supabase — invariato)

```
auth.users (Supabase managed)
    │
    ├── profiles (1:1)
    │
    ├── books (1:N)  ─── highlights (N:1) ─── highlight_tags (N:M) ─── tags
    │                        │
    │                        └── jam_highlights (N:M) ─── jams (N:1) ─── jam_members (N:M)
    │                                                          │
    └─────────────────────────────────────────────────────────┘ (owner)
    
    └── clippings_imports (log upload)
```

Vedi `supabase/migrations/001_initial_schema.sql` per DDL completo.
Vedi `supabase/migrations/002_rls_policies.sql` per RLS.

---

## 4. Schema Isar locale

Il database locale (Isar) è una cache offline. Supabase è la fonte di verità per i dati sociali.

```
Book
  id (Isar autoincrement)
  supabaseId (UUID, usato per sync)
  userId
  title, author, coverUrl
  lastSyncedAt
  → highlights (IsarLinks<Highlight> via @Backlink)

Highlight
  id (Isar autoincrement)
  supabaseId (UUID, nullable prima del sync)
  content, note, location, addedAt, color, isFavorite
  userId
  → book (IsarLink<Book>)
  → tags (IsarLinks<Tag>)

Tag
  id, name, userId
  (highlights accessibili via query, non link diretto)

Jam (cache locale di Supabase, dati sociali completi sempre da Supabase)
  id, supabaseId, name, inviteCode, ownerId
  memberIds (List<String> — UUIDs)
```

---

## 5. Flusso Amazon Kindle Sync (senza USB)

```
[Kindle device] ──WiFi──► [Amazon Cloud / read.amazon.com]
                                       │
                              (sync automatico Amazon)
                                       │
[iPhone apre Marginalia → Sync Kindle]  ▼
        │                  ┌─────────────────────────┐
        │                  │  read.amazon.com         │
        └─────────────────►│  /kp/notebook            │
          WebView           │  (pagina highlights)     │
          (login Amazon)    └─────────────┬────────────┘
                                         │
                               JavaScript injection
                               (AmazonSyncService._extractorJs)
                               estrae highlights dal DOM → JSON
                                         │
                              ImportService → Isar (locale)
                                         │
                              (opzionale) sync → Supabase
```

**Dettaglio tecnico (Flutter):**
1. `AmazonLoginScreen` apre `WebViewWidget` su `read.amazon.com/kp/notebook`
2. Amazon gestisce il login (Marginalia non vede le credenziali)
3. Su `onPageFinished`, se URL è il notebook: `WebViewController.runJavaScriptReturningResult(js)`
4. JS estrae `{ bookTitle, bookAuthor, content, location, color }[]` → JSON
5. `amazonHighlightsToClippingsText()` converte in formato My Clippings.txt
6. `ImportService.importClippingsText()` processa, deduplica, salva in Isar

**Fragilità:** Amazon può cambiare selettori CSS/DOM. Se sync smette: aggiornare
`AmazonSyncService._extractorJs` e annotare in `LESSONS-LEARNED.md`.

**Note ToS:** l'utente accede a dati suoi, sulla pagina Amazon autentica. Stesso approccio di Readwise.

**Fallback manuale:** `LibraryScreen` ha import da file `My Clippings.txt` via FilePicker.

---

## 6. Flusso Jam (social)

```
Utente A crea Jam "Il Nome della Rosa"
    → riga in jams con invite_code univoco (generato da Supabase trigger)
    → condivide link: app.marginalia.io/jam/invite/[code]

Utente B apre link (iOS)
    → login (se non ha account, crea)
    → join Jam (riga in jam_members)
    → vede gli highlight che A ha condiviso in quel Jam

Utente A share highlight → riga in jam_highlights
    → Utente B riceve update via Supabase Realtime
    → SocialScreen si aggiorna

Utente A rimuove B dalla Jam
    → delete da jam_members
    → B non vede più gli highlight
    → La Jam è permanente (non sparisce al logout), revocabile (owner può dissolverla)
```

---

## 7. Design system

**Palette** (estetica giapponese minimalista — `lib/core/theme.dart`):
```
background:  #FAFAF8  (bianco caldo)
surface:     #F2F0EC  (carta)
text:        #1A1A18  (nero caldo)
textMuted:   #6B6862  (grigio caldo)
accent:      #8B7355  (seppia)
accentLight: #C4A882  (seppia chiaro)
border:      #E8E4DF  (bordo carta)
```

**Tipografia**:
- Highlight content: Lora (Google Fonts, serif)
- UI/labels: system-ui / SF Pro

---

## 8. Decisioni prese e perché

| Data | Decisione | Motivazione |
|------|-----------|-------------|
| 2026-05-10 | ~~Swift/SwiftUI~~ → Flutter | Founder su Windows: Flutter gira su Windows senza Mac |
| 2026-05-10 | ~~GitHub Actions + fastlane~~ → Codemagic | Specializzato Flutter, gestisce cert automaticamente, 500 min gratis |
| 2026-05-10 | Monorepo lib/ + supabase/ | Un solo repo, un solo git |
| 2026-05-10 | Supabase al MVP | Social Jam richiede backend subito |
| 2026-05-10 | Account obbligatorio | Jam incompatibili con no-account |
| 2026-05-10 | ~~Next.js/Vercel~~ SUPERATA | Rimossa: prodotto è app iOS, non sito web |
| 2026-05-10 | ~~Python kindle-sync.py USB~~ SUPERATA | Rimossa: sostituita da Amazon WebView sync |
| 2026-05-10 | Amazon sync via WebView + JS | No USB, stesso approccio di Readwise, credenziali non visibili |
| 2026-05-10 | Isar per storage locale | Veloce, offline-first, ottimo per highlights; richiede code gen |
| 2026-05-10 | Riverpod manuale (no generator) | Evita doppia dipendenza da build_runner; solo Isar la richiede |
