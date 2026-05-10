# Marginalia — Architecture

> Documento vivo. Aggiornalo quando prendi decisioni architetturali significative.
> Decisioni prese: data + motivazione. Non cancellare mai le decisioni superate, aggiungi "SUPERATA" e perché.

---

## 1. Panoramica sistema

```
┌──────────────────────────────────────────────────────────────────┐
│                         UTENTE FINALE                            │
│                                                                  │
│       iPhone / iPad                    Kindle (WiFi sync)        │
│       ┌──────────────────┐            ┌──────────────────┐       │
│       │   iOS App        │            │  Amazon Cloud    │       │
│       │   (Swift/SwiftUI)│◄──────────►│  read.amazon.com │       │
│       │   WidgetKit      │  WKWebView │  /kp/notebook    │       │
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
  Windows → git push → GitHub Actions (macOS runner) → build IPA → TestFlight → iPhone
                    │  Realtime           │
                    │  Edge Functions     │
                    └─────────────────────┘
```

---

## 2. Componenti

### 2a. iOS App (`ios/`)
- **Tecnologia**: Swift 5.10+, SwiftUI, SwiftData, WidgetKit
- **Target**: iOS 17.0+
- **Architettura**: MVVM leggero (View + ViewModel + Repository)
- **Persistenza locale**: SwiftData (offline-first, cache locale di tutto)
- **Sync**: SupabaseSync service, pull on app open + background refresh
- **Widget**: pre-calcola highlight notturno via background task

### 2b. Web App (`web/`)
- **Tecnologia**: Next.js 14+ (App Router), TypeScript, Tailwind CSS
- **Deploy**: Vercel (free tier — zero costo)
- **Scopo**: 
  - Companion app per utenti senza iPhone (o che preferiscono browser)
  - Dashboard per gestire Jam, vedere highlights in browser
  - Tool per il founder (Vittorio) per vedere tutto funzionare da Windows
  - Upload manuale My Clippings.txt
- **Auth**: Supabase Auth (magic link / email)

### 2c. Supabase (`supabase/`)
- **DB**: PostgreSQL con RLS (Row Level Security)
- **Auth**: email + magic link. OAuth (Google) in roadmap.
- **Storage**: bucket `clippings` per i file .txt, bucket `avatars`
- **Edge Functions**: `parse-clippings` — triggered su upload file, parsa e importa
- **Realtime**: canali Jam per aggiornamenti live highlights condivisi
- **Free tier**: 500MB DB, 1GB storage, 200 connessioni realtime — ok per MVP

### 2d. ~~Script Kindle sync~~ — SUPERATA 2026-05-10
**Sostituita da**: Amazon WKWebView sync diretto nell'app iOS.
Il kindle-sync.py (USB) è stato rimosso dal repo. Vedi sezione "Flusso Amazon sync" sotto.

### 2d. CI/CD — GitHub Actions + TestFlight
- **Trigger**: push su `main`
- **Runner**: `macos-14` (Apple Silicon, GitHub hosted)
- **Tool**: fastlane + fastlane match (certificati in repo privato)
- **Output**: build IPA caricato su TestFlight → installabile su iPhone in ~15 min
- **Costo**: incluso in GitHub Free (200 min macOS/mese, build ~5-8 min → ~25-40 build/mese)
- **Config**: `.github/workflows/testflight.yml` + `ios/fastlane/Fastfile`
- **Prima volta**: richiede setup su Mac reale (vedi `docs/SETUP_MAC.md`)

---

## 3. Schema database

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
    
    └── clippings_imports (log degli upload)
```

### Decisioni schema

**2026-05-10 — highlights.is_public**
Highlights sono privati di default (`is_public = false`). Quando condividi un highlight in un Jam, si crea una riga in `jam_highlights` e quell'highlight diventa visibile ai membri del Jam. Non serve `is_public` = true globalmente. I membri del Jam vedono solo gli highlight esplicitamente condivisi, non tutti gli highlight del libro.

**2026-05-10 — jam_highlights vs highlight.visibility**
Scelto `jam_highlights` (join table esplicita) invece di un campo `visibility` sull'highlight. Motivazione: un highlight può essere condiviso in più Jam diversi, con visibilità indipendente per ognuno. La join table lo permette naturalmente.

**2026-05-10 — book dedup**
I libri sono per-utente (non globali). Due utenti con lo stesso libro = due righe in `books`. Potremmo fare una tabella `book_catalog` globale in futuro (ottimizzazione), ma per MVP è prematuro.

---

## 4. Flusso Amazon Kindle Sync (senza USB)

```
[Kindle device] ──WiFi──► [Amazon Cloud / read.amazon.com]
                                       │
                              (sync automatico Amazon)
                                       │
[iPhone apre Marginalia]               ▼
        │                  ┌─────────────────────────┐
        │                  │  read.amazon.com        │
        └─────────────────►│  /kp/notebook           │
          WKWebView         │  (pagina highlights)    │
          (Amazon login)    └─────────────┬───────────┘
                                         │
                               JavaScript injection
                               estrae highlights dal DOM
                                         │
                                         ▼
                              ImportService → SwiftData
                                         │
                              (opzionale) sync → Supabase
```

**Dettaglio tecnico:**
1. Utente tocca "Sincronizza Kindle" in Impostazioni
2. `AmazonLoginView` apre WKWebView su `read.amazon.com/kp/notebook`
3. Amazon reindirizza al login se non autenticato (il form Amazon è nativo, Marginalia non vede le credenziali)
4. Dopo login, WebView torna su `/kp/notebook` con tutti gli highlight
5. `AmazonSyncCoordinator.extractFromWebView()` inietta JS nel DOM
6. JS interroga i selettori della pagina e restituisce JSON con highlights
7. `ImportService.importContent()` processa, deduplica, salva in SwiftData
8. Background refresh periodico ripete il flusso silenziosamente

**Fragilità:** Amazon può cambiare i selettori CSS/DOM senza preavviso. Se il sync smette di funzionare: aggiornare i selettori in `AmazonSyncService.amazonExtractorJS` e aggiungere voce in `LESSONS-LEARNED.md`.

**Note ToS:** l'utente accede a dati suoi, sulla pagina Amazon autentica, con le sue credenziali. Stesso approccio di Readwise, Obsidian, Notion per Kindle sync.

**Flusso alternativo (manuale):** `LibraryView` mantiene il DocumentPicker per import da file `My Clippings.txt` come fallback.

---

## 5. Flusso Jam (social)

```
Utente A crea Jam "Il Nome della Rosa"
    → genera invite_code univoco
    → condivide link: app.marginalia.io/jam/invite/[code]

Utente B (browser o iOS) apre link
    → login (se non ha account, crea)
    → join Jam (riga in jam_members)
    → vede gli highlight che A ha condiviso in quel Jam

Utente A share highlight → riga in jam_highlights
    → Utente B riceve update via Realtime
    → UI Jam si aggiorna

Utente A rimuove B dalla Jam
    → delete da jam_members
    → B non vede più gli highlight
    → La Jam è permanente (non sparisce al logout), revocabile (owner può dissolverla)
```

---

## 6. Struttura Package.swift (iOS)

La app iOS usa un approccio ibrido:
- **SwiftPM** per tutta la business logic (Marginalia library + MarginaliaWidgets)
- **Xcode project** (da creare al primo accesso Mac) per i target app + widget extension

Questo permette di testare e iterare la logica da qualsiasi macchina senza Xcode.

```
ios/
├── Package.swift          ← define library targets
├── Sources/
│   ├── Marginalia/        ← main library (models, parser, services, views)
│   └── MarginaliaWidgets/ ← widget timeline providers
└── Tests/
    ├── Fixtures/          ← sample My Clippings.txt
    └── MarginaliaTests/   ← unit tests
```

Quando il founder accede al Mac:
1. `File → New → Project` in Xcode → iOS App
2. `File → Add Package Dependencies` → aggiungi path locale `ios/`
3. Aggiungi Widget Extension target
4. Il codice SwiftPM è già scritto e testato

---

## 7. Design system

**Palette** (estetica giapponese minimalista):
```
Background:  #FAFAF8  (bianco caldo)
Surface:     #F2F0EC  (carta)
Text:        #1A1A18  (nero caldo)
TextMuted:   #6B6862  (grigio caldo)
Accent:      #8B7355  (seppia)
AccentLight: #C4A882  (seppia chiaro)
Border:      #E8E4DF  (bordo carta)
```

**Tipografia**:
- Contenuto highlight: Georgia serif
- UI/labels: system-ui / SF Pro
- Spaziatura generosa (line-height 1.7+ per il contenuto)

---

## 8. Decisioni prese e perché

| Data | Decisione | Motivazione |
|------|-----------|-------------|
| 2026-05-10 | Monorepo ios/ + web/ + supabase/ | Un solo repo, un solo git, più facile da gestire |
| 2026-05-10 | Supabase al MVP (non post-MVP) | Social Jam richiede backend; meglio iniziare subito con architettura finale |
| 2026-05-10 | Account obbligatorio | Social Jam incompatibile con no-account; highlight locali restano (offline-first), ma Jam richiede identità |
| 2026-05-10 | ~~Next.js su Vercel come web companion~~ SUPERATA | Rimossa: il prodotto è un'app iOS, non un sito web |
| 2026-05-10 | TestFlight via GitHub Actions | "Vercel per iOS": push → CI macOS → build → TestFlight → iPhone. Gratis entro i limiti GitHub Free |
| 2026-05-10 | ~~Python kindle-sync.py (USB)~~ SUPERATA | Rimossa: USB troppo scomodo, sostituita da Amazon WKWebView sync |
| 2026-05-10 | Amazon sync via WKWebView + JS injection | Sync diretto dai server Amazon senza USB. Stesso approccio di Readwise. Fragile ma standard del settore |
| 2026-05-10 | Package.swift per library, Xcode per app | Scrivibile da Windows, testabile da Windows, minima dipendenza da Xcode per la fase blind compile |
