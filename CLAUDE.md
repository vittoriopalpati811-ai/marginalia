# Project: Marginalia

> App iOS nativa per riscoprire gli highlight Kindle attraverso widget intelligenti, cerchie di lettura sociali (Jam) e sync automatico con Amazon.

---

## ⚠️ Nota meta-importante per Claude

Questi file (CLAUDE.md, BACKLOG.md, PROGRESS.md, QUESTIONS.md) sono stati scritti con il founder. **Sono base di partenza, non vangelo.**

Sei autorizzato — anzi, incoraggiato — a:
- **Riorganizzare** i file se trovi una struttura migliore
- **Aggiungere** sezioni mancanti che ti renderebbero più efficace
- **Correggere** incoerenze o ambiguità che noti leggendo

L'unica regola: **prima di una riorganizzazione strutturale**, scrivi in `QUESTIONS.md` cosa vuoi cambiare e perché, e procedi solo dopo l'OK del founder.

---

## 1. Contesto e principi

### Cosa sto costruendo
App iOS che importa highlight da Kindle e li ripropone all'utente attraverso widget home/lockscreen, ricerca semantica, e feature social (Jam — cerchie di lettura).

### Target utente
Lettori avidi (Kindle owners) che soffrono il "ho letto 40 libri e non ricordo niente". Sovra-rappresentazione su iOS, gusto estetico curato, disposti a pagare €25/anno.

### Filosofia di prodotto
- **Rituale, non database.** L'app deve far venire voglia di aprirla.
- **Estetica giapponese minimalista.** Bianchi caldi (#FAFAF8), Lora serif, sepia accent (#8B7355).
- **Offline-first.** Tutto funziona senza rete. Supabase è un layer opzionale.

---

## 2. Stack tecnico (DECISIONE DEFINITIVA — 2026-05-10)

### ⚠️ Pivot da Swift a Flutter

**Motivo**: il founder sviluppa su Windows. Flutter compila e gira nativamente su Windows
(`flutter run -d windows`) senza nessun Mac. La qualità delle animazioni (Impeller engine)
è paragonabile a SwiftUI nativo.

### Stack corrente

**Framework**: Flutter/Dart
- Target primario: iOS (App Store)
- Development & test: Windows desktop + Chrome (`flutter run -d windows`)
- Animazioni: Impeller engine (60/120fps)

**State management**: flutter_riverpod 2.x
- Provider manuali (senza riverpod_generator per semplicità)

**Database locale**: Isar 3.x
- NoSQL embedded, offline-first
- ⚠️ Richiede code generation: `dart run build_runner build --delete-conflicting-outputs`
- I file `*.g.dart` sono in .gitignore (si rigenerano)

**Backend**: Supabase
- PostgreSQL + RLS + Storage + Realtime + Edge Functions
- Tier free sufficiente per MVP
- Auth: email + password (magic link in roadmap)

**Navigation**: go_router 13.x
- ShellRoute per bottom nav (Library, Search, Jam, Settings)
- Route full-screen per book detail, highlight detail, Amazon sync

**Amazon Kindle sync**: webview_flutter + JavaScript injection
- L'utente accede ad Amazon sul proprio account (credenziali non visibili all'app)
- JS iniettato su `read.amazon.com/kp/notebook` per estrarre highlights
- Stesso approccio usato da Readwise, Obsidian, Notion

**CI/CD**: Codemagic (free: 500 min/mese)
- Build iOS in cloud senza Mac → TestFlight → iPhone
- Config: `codemagic.yaml` nella root del repo

**Animazioni**: flutter_animate 4.x

**Tipografia**: google_fonts (Lora serif per highlights, system-ui per UI)

### Struttura monorepo
```
Marginalia/
├── lib/                    # Flutter source
│   ├── main.dart           # Entry point
│   ├── app.dart            # MaterialApp + router
│   ├── core/
│   │   ├── theme.dart
│   │   ├── models/         # Isar models (+ *.g.dart generati)
│   │   ├── parser/         # MyClippingsParser
│   │   ├── services/       # ImportService, AmazonSyncService, SupabaseService
│   │   └── providers/      # Riverpod providers
│   └── features/
│       ├── library/        # LibraryScreen, BookDetailScreen
│       ├── reader/         # HighlightDetailScreen
│       ├── search/         # SearchScreen
│       ├── social/         # SocialScreen (Jam)
│       ├── settings/       # SettingsScreen
│       └── onboarding/     # AmazonLoginScreen
├── supabase/               # Migrations + Edge Functions
│   ├── migrations/
│   └── functions/parse-clippings/
├── test/                   # Flutter tests
│   └── parser/
├── pubspec.yaml
├── codemagic.yaml
└── [file di processo]
```

---

## 3. Setup del founder (Windows)

### Sviluppo locale

1. Installa Flutter SDK: https://docs.flutter.dev/get-started/install/windows
2. Clona il repo
3. `flutter pub get`
4. Genera schemi Isar: `dart run build_runner build --delete-conflicting-outputs`
5. Testa su Windows: `flutter run -d windows`
6. Testa su Chrome: `flutter run -d chrome`

### Build iOS (senza Mac)

Ogni push su `main` → Codemagic builda → TestFlight → iPhone in ~20 minuti.

Prima configurazione Codemagic (una sola volta, dal browser):
1. Crea account su codemagic.io
2. Connetti repo GitHub
3. Configura integrazione App Store Connect (API key)
4. Aggiungi certificati (Codemagic gestisce il keychain automaticamente)

Vedi `codemagic.yaml` per la config completa.

### ⚠️ Code generation obbligatoria

Prima di ogni `flutter run`, se hai modificato un modello Isar:
```
dart run build_runner build --delete-conflicting-outputs
```

I file `*.g.dart` non sono in git (sono in .gitignore) — si rigenerano localmente.

---

## 4. Come Claude deve lavorare in questo repo

### Modalità di lavoro
Sessioni autonome di 2-4 ore. A fine sessione:
1. Commit con messaggio descrittivo
2. Aggiorna `PROGRESS.md`
3. Dubbi importanti → `QUESTIONS.md`

### Cosa fai in autonomia
- Implementare feature da `BACKLOG.md`
- Scrivere test Flutter (`flutter test`)
- Aggiornare documentazione tecnica
- Refactoring locali

### Cosa NON fai senza conferma
- Cambiare stack o aggiungere dipendenze a `pubspec.yaml`
- Modificare schema Supabase in modo non retrocompatibile
- Pushare su `main`
- Commit > 500 righe (spezza in commit logici)

### Stile di codice
- Flutter dichiarativo, widget composabili e piccoli
- Provider Riverpod manuali (non riverpod_generator)
- Naming in inglese, commenti in inglese tecnico
- Niente abbreviazioni (clipping non clp, highlightCount non hCnt)
- Errori gestiti con try/catch + AsyncValue, mai silenziosi

### Stile commit
Vedi `.claude/commit-style.md`

---

## 5. Vincoli MVP

1. iOS primario. Flutter permette Android gratis, ma foco su iOS fino a 1000 utenti.
2. Nessuna AI nell'MVP. Si aggiunge post-lancio (Claude Haiku).
3. Account obbligatorio (richiesto dalle Jam). Highlight locali offline funzionano, Jam richiede identity.
4. Tempo founder: max 5h/settimana. Niente over-engineering.

---

## 6. Errori noti e gotchas

### Isar code generation
`*.g.dart` devono essere rigenerati dopo ogni modifica ai modelli. Se dimentichi:
`type 'Null' is not a subtype of type 'IsarCollection<Book>'` al runtime.

### Flutter Windows: webview_flutter non supportato
`webview_flutter` funziona su iOS/Android ma non su Windows desktop.
Per test locale su Windows, l'Amazon sync non funzionerà — usa mock data.

### Supabase constants
`lib/main.dart` ha `_supabaseUrl` e `_supabaseAnonKey` come placeholder.
Il founder deve sostituirli con i valori reali prima del primo build.

---

## 7. Decision log (riassunto)

| Data | Decisione | Motivazione |
|------|-----------|-------------|
| 2026-05-10 | Pivot Swift → Flutter | Founder su Windows: Flutter gira nativamente su Windows senza Mac |
| 2026-05-10 | Codemagic invece di GitHub Actions | Specializzato Flutter, gestisce certificati iOS automaticamente, 500 min gratis |
| 2026-05-10 | Riverpod manuale (no generator) | Evita dipendenza da code gen per i provider; solo Isar richiede build_runner |
| 2026-05-10 | Account obbligatorio | Jam sociali incompatibili con no-account |
| 2026-05-10 | Supabase al MVP | Social Jam richiede backend; meglio architettura finale subito |
| 2026-05-10 | Amazon WKWebView sync | No USB, stesso approccio di Readwise, credenziali non visibili all'app |
