# Backlog

> Task ordinate per priorità. Lavora SEMPRE dall'alto verso il basso.
> Una task = uno o più commit logici, mai un commit gigante.
> Quando completi una task, sposta la voce in `PROGRESS.md` con il commit hash.
>
> ⚠️ Vincolo speciale: il founder lavora da Windows, Claude non può compilare codice iOS.
> Tu scrivi codice di alta qualità "blind compile". Vedi CLAUDE.md sezione 2.

---

## 🎯 Brief sessione corrente

**Data**: —
**Focus**: —
**Vincoli specifici**: —
**Non fare**: —
**Note**: —

---

## ✅ Sprint 1 — Foundation (COMPLETATO sessione 1)

> Tutto il codice sotto è stato scritto in blind compile il 2026-05-10.
> Necessita validazione su Mac prima di considerarsi "funzionante".

### ✅ TASK-001: Monorepo + struttura progetto
**Criteri di successo:**
- File `.xcodeproj` o `Package.swift` creato con struttura cartelle definita in CLAUDE.md sezione 4
- Target iOS 17.0+
- `.gitignore` Swift/Xcode standard (DerivedData, xcuserdata, ecc.)
- README.md aggiornato

**Note speciali per Windows:**
Sei su Windows e non hai Xcode. Hai due opzioni:
- (A) Generare un `Package.swift` di Swift Package Manager + struttura cartelle, e rimandare la creazione del `.xcodeproj` vero al primo accesso al Mac
- (B) Generare manualmente i file `project.pbxproj` (formato testuale documentato), sapendo che potrebbero esserci errori che Xcode segnalerà al primo apertura

**Raccomandazione**: opzione A. È più pulita. Annota in LESSONS-LEARNED.md come decisione presa, così quando il founder accede al Mac, "convertirà" il SwiftPM in progetto Xcode con extension iOS / WidgetKit.

**Definition of Done:**
- [ ] Struttura cartelle creata
- [ ] `Package.swift` o pre-progetto Xcode predisposto
- [ ] `.gitignore` corretto
- [ ] Commit `[setup] init project structure for iOS app`

---

### TASK-002: Modelli SwiftData base
**Criteri di successo:**
- `Book.swift`, `Highlight.swift`, `Tag.swift` come da CLAUDE.md
- ModelContainer configurato in `App/MarginaliaApp.swift`
- Test base che istanzia gli oggetti e verifica relazioni (anche se non eseguibili da Windows, vanno scritti)

**Definition of Done:**
- [ ] 3 file model creati con commenti chiari
- [ ] Container inizializzato
- [ ] Test scritti
- [ ] Commit `[models] swiftdata schema base`

---

### TASK-003: Verifica fixture test
**Criteri di successo:**
- Verifica presenza file in `Tests/Fixtures/`
- Se mancano: scrivi in QUESTIONS.md "il founder deve fornire X fixture, ecco i formati che mi servono"
- Procedi su altre task nel frattempo

**Definition of Done:**
- [ ] Verifica fatta
- [ ] Eventuale richiesta scritta in QUESTIONS.md
- [ ] Nessun commit (solo verifica)

---

### TASK-004: MyClippingsParser
**Criteri di successo:**
- `Core/Parser/MyClippingsParser.swift`
- Funzione `parse(_ content: String) -> [ParsedClipping]`
- Struct `ParsedClipping { title, author, location, addedAt, content, type }`
- Gestisce: italiano + inglese (header diversi), encoding misto, separatori
- Filtra solo `Highlight` e `Note`, ignora `Bookmark`
- Dedup: highlight sovrapposti = tieni il più lungo
- Test scritti su tutti i fixture disponibili

**Note per Claude:**
Questa è la task più rischiosa "blind compile" perché c'è molta logica. Sii particolarmente rigoroso. Quando hai dubbi su API di Foundation (es. `String.split`, regex), consulta documentazione Apple.

**Definition of Done:**
- [ ] Parser implementato
- [ ] Test scritti per tutti gli edge case noti
- [ ] Documentazione interna ricca
- [ ] Commit `[parser] my clippings parser + tests`

---

### TASK-005: ImportService
**Criteri di successo:**
- `Core/Services/ImportService.swift`
- Funzione `importClippings(from url: URL) async throws -> ImportSummary`
- `ImportSummary { booksAdded, highlightsAdded, duplicatesSkipped }`
- Match libri esistenti per `title + author` (no duplicati)
- Match highlight per `book + content hash` (no duplicati)
- Test idempotenza: re-import stesso file → 0 nuovi highlight

**Definition of Done:**
- [ ] Service implementato
- [ ] Test idempotenza scritto
- [ ] Commit `[import] service con dedup`

---

### TASK-006: LibraryView
**Criteri di successo:**
- `Features/Library/LibraryView.swift`
- Lista libri ordinati per `importedAt` desc
- Cella: titolo, autore, conteggio highlight, "cover" colorata
- Empty state
- Toolbar: bottone Import → DocumentPicker → ImportService
- Alert di summary post-import

**Definition of Done:**
- [ ] Vista implementata
- [ ] Empty state presente
- [ ] Flow import end-to-end definito
- [ ] Commit `[ui] library view + import flow`

---

### TASK-007: BookDetailView
**Criteri di successo:**
- `Features/Library/BookDetailView.swift`
- Header: titolo libro, autore, conteggio
- Lista highlight (preview troncato 4 righe), location, data
- Tap → push a `HighlightDetailView`
- Sort: per data o per posizione

**Definition of Done:**
- [ ] Vista funzionante
- [ ] Navigazione push funzionante
- [ ] Commit `[ui] book detail view`

---

### TASK-008: HighlightDetailView
**Criteri di successo:**
- `Features/Reader/HighlightDetailView.swift`
- Contenuto pieno (font serif, generoso)
- Metadata: libro, autore, location, data
- "La mia nota" editabile
- Bottoni: Copia, Condividi, Tag (stub)

**Definition of Done:**
- [ ] Vista funzionante
- [ ] Persistenza nota
- [ ] Commit `[ui] highlight detail view`

---

### TASK-009: SearchView con FTS
**Criteri di successo:**
- `Features/Search/SearchView.swift`
- TextField con debouncing 300ms
- `#Predicate` su content/title/author
- Risultati con highlight della parola
- Empty states corretti

**Definition of Done:**
- [ ] Ricerca funzionante
- [ ] Performance considerata in design
- [ ] Commit `[search] search view + predicate query`

---

### TASK-010: TabView root
**Criteri di successo:**
- `App/RootView.swift` con TabView (Libreria, Cerca, Impostazioni stub)
- Icone SF Symbols
- Stato persistente con @SceneStorage

**Definition of Done:**
- [ ] Tab funzionanti
- [ ] MVP-no-widget completo a livello di codice
- [ ] Commit `[ui] root tabview`
- [ ] Tag git: `mvp-no-widget-code-complete`
- [ ] **A questo punto: il founder pianifica primo accesso a Mac per validazione**

---

## 🟡 Sprint 2 — Widget (da fare DOPO validazione su Mac)

### TASK-011 ... TASK-014
*Dettagliate quando ci arriviamo, post primo Mac access*

Foreshadowing:
- Setup Widget Extension (richiede config Xcode, fattibile solo su Mac)
- Small/Medium/Lockscreen widget
- Background pre-calcolo highlight

---

## 🔵 Backlog futuro (NON toccare ora)

- Onboarding interattivo
- Tag manager
- Filtri widget
- Export markdown
- Sync iCloud
- Paywall RevenueCat
- AI features (post-lancio)
- Modalità rituale di chiusura libro
- Connessioni semantiche AI tra highlight

---

## 📝 Convenzioni backlog

- **TASK-NNN**: numero progressivo, mai riusato
- **Stato**: 🟢 in corso | 🟡 next | 🔵 backlog | ✅ done (in PROGRESS.md)
- Quando inizi una task, scrivi in `PROGRESS.md` "TASK-XXX iniziata"
- Quando finisci, sposta tutta la voce in `PROGRESS.md` con commit hash
- Se trovi una task mal definita: scrivi correzione in QUESTIONS.md, non procedere
