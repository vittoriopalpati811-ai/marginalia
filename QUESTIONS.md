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
Il sync Amazon avviene tramite WKWebView + JavaScript injection su `read.amazon.com/kp/notebook`. L'utente si autentica con le sue credenziali su pagina Amazon autentica — Marginalia non vede le credenziali e non le conserva.

**Zona grigia ToS**: Amazon non espone una API pubblica per gli highlight. L'approccio è lo stesso usato da Readwise, Obsidian, Notion e decine di app con milioni di utenti. Amazon non ha mai preso provvedimenti contro queste app perché l'utente accede a dati suoi.

**Rischio principale**: Amazon può cambiare il markup di read.amazon.com senza preavviso, rompendo il sync. Soluzione: aggiornare i selettori JS in `AmazonSyncService.swift`. Non è un rischio di shutdown ma di manutenzione.

**Cosa fare**: niente di urgente. Se ti chiede un avvocato, puoi dimostrare che l'accesso è fatto dall'utente per conto proprio. Se Amazon dovesse rendere disponibile una API ufficiale (poco probabile), migriamo lì.

---

## 2026-05-10 - Dubbio tecnico: @Relationship M:M Tag↔Highlight in SwiftData
**Status**: 🟡 PROCEDIBILE — ho implementato con sintassi che ritengo corretta, da verificare su Mac

**Contesto**:
SwiftData gestisce le relazioni M:M con array su entrambi i lati e `@Relationship` con `deleteRule`.
Ho implementato `Tag.highlights: [Highlight]` e `Highlight.tags: [Tag]` con `@Relationship(deleteRule: .cascade, inverse: \Tag.highlights)`.
Non sono sicuro al 100% che la sintassi `inverse:` sia corretta per M:M (vs 1:N).

**Mia inclinazione**: la sintassi sembra corretta basandomi su documentazione Apple, ma è una delle zone più fragili del codice blind compile.

**Bloccante per**: niente subito (Tag non usati attivamente nell'MVP UI). Ma da verificare al primo accesso Mac.
**Cosa faccio nel frattempo**: Tag presenti nello schema ma UI di tagging non implementata (sprint 2).

---

## 2026-05-10 - Dubbio tecnico: FetchDescriptor con predicate su relazione nested
**Status**: 🟡 PROCEDIBILE

**Contesto**:
In `BookDetailView.swift` uso:
```swift
_highlights = Query(
    filter: #Predicate<Highlight> { $0.book.id == bookId },
    ...
)
```
Il predicate attraversa una relazione (`book.id`). In SwiftData i predicate su relazioni nested possono avere comportamenti non ovvi — in alcuni casi richiedono `.book?.id` con optional chaining.

**Mia inclinazione**: ho usato `$0.book.id` (non optional) perché la relazione è non-optional. Ritengo corretto ma confidence 3/5.

**Bloccante per**: BookDetailView (TASK-007). UI è scritta, ma potrebbe non compilare o dare risultati vuoti.
**Cosa faccio nel frattempo**: niente, il pattern è nel codice così com'è.

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
