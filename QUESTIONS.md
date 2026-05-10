# Open Questions

> Dubbi architetturali / di prodotto che richiedono una decisione del founder.
> Claude scrive QUI invece di inventare. Il founder risponde quando torna.
> Una volta risposta, la domanda resta come decision log (non si cancella).

**Convenzione status:**
- 🔴 BLOCCANTE — fermo tutto finché non rispondi
- 🟡 PROCEDIBILE — ho preso una decisione provvisoria, ma confermami
- ⚪ INFORMATIVA — solo per tua awareness, non serve risposta urgente
- ✅ RISOLTA — la lascio qui come decision log

---

## 2026-05-11 (sessione 4) - Apple Developer Program non attivo
**Status**: 🔴 BLOCCANTE per build iOS / TestFlight

**Problema**: L'account `vittoriopalpati811@gmail.com` non è iscritto all'Apple Developer Program.
App Store Connect ha risposto: *"devi essere un individuo o un componente di un team di Apple Developer Program"*.

**Cosa serve**: iscriversi all'Apple Developer Program su [developer.apple.com/enroll](https://developer.apple.com/enroll) — €99/anno.

**Cosa ho completato comunque** (sessione 4):
- Codemagic connesso a GitHub (`vittoriopalpati811-ai/marginalia`) ✅
- App creata su Codemagic come tipo Flutter ✅
- `codemagic.yaml` già presente nel repo ✅
- Manca solo: App Store Connect API key (richiede Developer Program attivo)

**Passi dopo iscrizione** (~30 min, da browser):
1. Vai su [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users & Access → Integrations → App Store Connect API
2. Crea una nuova chiave con ruolo "App Manager" → scarica il file `.p8`
3. Vai su Codemagic → Settings → Integrations → Developer Portal → Connect
4. Inserisci: nome chiave, Issuer ID, Key ID, carica il file `.p8`
5. Sostituisci `APP_STORE_APPLE_ID: "1234567890"` in `codemagic.yaml` con l'ID numerico della tua app

**Bloccante per**: build iOS, TestFlight, distribuzione

---

## 2026-05-10 (sessione 3) - Setup Codemagic e Supabase
**Status**: 🟡 PROCEDIBILE — Supabase completato da Claude, Codemagic richiede credenziali Apple

**Supabase** ✅ FATTO DA CLAUDE (2026-05-11):
- Progetto `marginalia` creato: `https://ibucvloawkfwobaelwbr.supabase.co`
- Migration 001 (schema) e 002 (RLS) applicate — 9 tabelle attive
- Bucket `clippings` (privato) e `avatars` (pubblico) creati
- `lib/main.dart` aggiornato con URL e anon key reali

**Codemagic** ✅ APP CREATA (sessione 4):
- Account Codemagic connesso a GitHub (`vittoriopalpati811-ai`)
- App `marginalia` creata, tipo Flutter impostato
- Manca solo API key App Store Connect (bloccata da Apple Developer Program)

**GitHub Pages** ✅ CONFIGURATO (sessione 4):
- Workflow `.github/workflows/deploy-web.yml` aggiunto al repo
- Ogni push su `main` → build Flutter web → deploy automatico
- URL: `https://vittoriopalpati811-ai.github.io/marginalia/`
- **Una sola azione manuale**: vai su GitHub → repo marginalia → Settings → Pages → Source → seleziona "GitHub Actions"

**TestFlight / iOS** 🔴 BLOCCATO — richiede Apple Developer Program (€99/anno, vedi entry sotto)

---

## 2026-05-10 (sessione 3) - Pivot Swift → Flutter
**Status**: ✅ RISOLTA

**Decisione presa dal founder (chat, sessione 3)**:
Pivot da Swift/SwiftUI a Flutter perché il founder sviluppa su Windows e non ha accesso quotidiano a un Mac.

**Conseguenze**:
- Tutto il codice Swift rimosso (ios/ → git rm)
- Flutter: `flutter run -d windows` per sviluppo locale su Windows
- CI/CD: Codemagic (invece di GitHub Actions + fastlane) per build iOS cloud senza Mac
- Stack: Flutter + Riverpod + Isar + Supabase + go_router + flutter_animate

**Risposto da**: Vittorio
**Data risposta**: 2026-05-10

---

## 2026-05-10 (sessione 2) - Rimozione web, Amazon sync, TestFlight CI
**Status**: ✅ RISOLTA

**Decisioni prese dal founder (chat, sessione 2)**:
1. **Nessun Vercel / web app** — il prodotto è un'app iOS nativa. Web rimosso.
2. **Kindle sync = Amazon server** (non USB) — WKWebView login su read.amazon.com + JS injection
3. **"Come Vercel per iOS"** = TestFlight via GitHub Actions con macOS runner (gratis entro limiti Free)
4. **App Store mindset** — si sviluppa come se si andasse in produzione: fastlane, match, certificati, build automatiche

**Rationale**: autorizzato con "non voglio che ci sia bisogno di collegamento USB" + "deve essere un'app installabile da App Store".

**Risposto da**: Vittorio
**Data risposta**: 2026-05-10

---

## 2026-05-10 - Architettura espansa: social Jam + web companion + auto-sync
**Status**: ✅ RISOLTA (parzialmente superata dalla sessione 2)

**Contesto**:
Prima sessione. Il founder ha autorizzato una serie di cambiamenti significativi rispetto alla bozza iniziale.

**Decisioni prese dal founder (chat, 2026-05-10)**:
1. **Account obbligatorio** (revoca vincolo "no mandatory account") — le Jam sociali richiedono identità
2. **Supabase al MVP** (non post-MVP) — le Jam richiedono backend subito
3. **Web companion Next.js + Vercel** (free) — così il founder può vedere tutto funzionare da Windows
4. **Social Jam** — cerchie di lettura permanenti e revocabili, simile a Spotify Jam ma persistente
5. **Auto-sync Kindle** via script Python su Windows — rileva Kindle USB, carica My Clippings.txt
6. **Monorepo** ios/ + web/ + supabase/ + scripts/

**Rationale**: tutti i punti autorizzati con "fai ciò che devi" + specifiche esplicite.

**Risposto da**: Vittorio
**Data risposta**: 2026-05-10

---

## 2026-05-10 - Amazon sync: implicazioni ToS
**Status**: ⚪ INFORMATIVA — no risposta urgente, ma devi essere consapevole

**Contesto**:
Il sync Amazon avviene tramite WebView + JavaScript injection su `read.amazon.com/kp/notebook`. L'utente si autentica con le sue credenziali su pagina Amazon autentica — Marginalia non vede le credenziali e non le conserva.

**Zona grigia ToS**: Amazon non espone una API pubblica per gli highlight. L'approccio è lo stesso usato da Readwise, Obsidian, Notion e decine di app con milioni di utenti. Amazon non ha mai preso provvedimenti contro queste app perché l'utente accede a dati suoi.

**Rischio principale**: Amazon può cambiare il markup di read.amazon.com senza preavviso, rompendo il sync. Soluzione: aggiornare i selettori JS in `lib/core/services/amazon_sync_service.dart` (`_extractorJs`). Non è un rischio di shutdown ma di manutenzione.

**Cosa fare**: niente di urgente. Se ti chiede un avvocato, puoi dimostrare che l'accesso è fatto dall'utente per conto proprio. Se Amazon dovesse rendere disponibile una API ufficiale (poco probabile), migriamo lì.

---

## 2026-05-10 - Dubbi tecnici SwiftData M:M e FetchDescriptor
**Status**: ✅ RISOLTI — non più rilevanti dopo il pivot a Flutter

**Nota**: i dubbi su `@Relationship M:M` in SwiftData e `FetchDescriptor` su relazioni nested sono stati
superati dal pivot a Flutter/Isar (2026-05-10). Il codice Swift è stato rimosso dal repo.
In Isar, la relazione M:M Tag↔Highlight è gestita con `IsarLinks<Tag>` su Highlight — pattern
documentato e verificabile localmente su Windows.

---

## ESEMPIO RISOLTA - 2026-05-10 - Workflow Windows + iOS
**Status**: ✅ RISOLTA
**Topic**: Come gestire sviluppo iOS con macchina principale Windows

**Contesto**:
Il founder lavora su Windows ma vuole un'app iOS nativa. Compilazione e test richiedono macOS.

**Opzioni considerate**:
1. Cambiare progetto in qualcosa multipiattaforma (React Native, Flutter)
2. Sviluppare blind compile da Windows + accessi periodici a Mac per validazione
3. Comprare/noleggiare Mac dal giorno 1

**Decisione**: opzione 2 (blind compile + accessi periodici)
**Razionale**:
- Founder vuole tassativamente iOS nativo (qualità, widget)
- Investimento Mac troppo alto per fase validazione
- Claude può scrivere Swift di alta qualità senza compiler, con rigore extra
- Servizi cloud Mac (MacInCloud ~30€/mese) bastano per accessi periodici

**Risposto da**: Vittorio
**Data risposta**: 2026-05-10

---

## ESEMPIO BLOCCANTE - [DATA] - [topic breve]
**Status**: 🔴 BLOCCANTE per TASK-XXX

**Contesto**:
Spiegazione breve della situazione tecnica/di prodotto.

**Opzioni considerate**:
1. Opzione A — pro / contro
2. Opzione B — pro / contro
3. Opzione C — pro / contro

**Mia inclinazione**: opzione X perché Y
**Bloccante per**: TASK-NNN, TASK-MMM
**Cosa sto facendo nel frattempo**: lavoro su TASK-ZZZ che è indipendente

---

<!-- TEMPLATE da copiare quando hai un nuovo dubbio -->

<!--
## [DATA] - [topic breve]
**Status**: 🔴 / 🟡 / ⚪

**Contesto**:

**Opzioni considerate**:
1.
2.

**Mia inclinazione**:
**Bloccante per**:
**Cosa sto facendo nel frattempo**:
-->
