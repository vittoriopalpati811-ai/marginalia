# Project: Marginalia (working title)

> App iOS nativa + web companion per riscoprire gli highlight Kindle attraverso widget intelligenti, cerchie di lettura sociali (Jam) e sync automatico.

---

## ⚠️ Nota meta-importante per Claude

Questi file (CLAUDE.md, BACKLOG.md, PROGRESS.md, QUESTIONS.md, e quelli in `.claude/`) sono stati scritti dal founder come bozza iniziale insieme a un'altra istanza di Claude. **Sono base di partenza, non vangelo.**

Sei autorizzato — anzi, incoraggiato — a:
- **Riorganizzare** i file se trovi una struttura migliore
- **Aggiungere** sezioni mancanti che ti renderebbero più efficace
- **Correggere** incoerenze o ambiguità che noti leggendo
- **Spezzare** un file in più file se è troppo monolitico
- **Unire** file se sono ridondanti

L'unica regola: **prima di una riorganizzazione strutturale**, scrivi in `QUESTIONS.md` cosa vuoi cambiare e perché, e procedi solo dopo l'OK del founder. Per modifiche piccole (typo, chiarimenti, esempi aggiuntivi) procedi pure in autonomia e segnala nel commit.

Non sei limitato dalla mia immaginazione su come strutturare il lavoro. Se hai un'idea migliore, dilla.

---

## 1. Contesto e principi

### Cosa sto costruendo
App nativa iOS che importa highlight da Kindle (`My Clippings.txt`) e li ripropone all'utente attraverso widget home/lockscreen, ricerca, e feature AI.

### Target utente
Lettori avidi (Kindle owners) che soffrono il "ho letto 40 libri e non ricordo niente". Sovra-rappresentazione su iOS, gusto estetico curato, disposti a pagare €25/anno per un'app fatta bene.

### Filosofia di prodotto
- **Rituale, non database.** L'app deve far venire voglia di aprirla, non sembrare un Excel di citazioni.
- **Estetica giapponese minimalista.** Bianchi caldi, tipografia da libro, niente skeumorfismi, nessuna gamification rumorosa.
- **Offline-first.** Tutto deve funzionare senza rete. AI è un layer opzionale, non il core.
- **Privacy first.** Zero account obbligatorio per le feature base. iCloud sync opzionale.

### Stack tecnico (DECISIONE PRESA — cambiamenti richiedono QUESTIONS.md)

**iOS App** (`ios/`)
- Swift 5.10+ / SwiftUI — iOS 17.0+
- SwiftData (persistenza locale, offline-first)
- WidgetKit
- Supabase Swift SDK (sync con backend)

**Web Companion** (`web/`)
- Next.js 14+ (App Router), TypeScript, Tailwind CSS
- Deploy: Vercel (free tier)
- Scopo: vedere tutto funzionare da Windows, social Jam, upload highlights

**Backend** (`supabase/`)
- Supabase: PostgreSQL + RLS + Storage + Realtime + Edge Functions
- Tier: free (sufficiente per MVP)
- AI post-lancio: Claude Haiku 4.5 + OpenAI text-embedding-3-small

**Kindle Sync** (`scripts/`)
- Python 3.10+ + psutil + supabase-py
- Rileva Kindle USB su Windows/Mac, carica My Clippings.txt automaticamente

**Paywall (post-MVP)**: RevenueCat
**Analytics (post-MVP)**: TelemetryDeck

### Vincoli (aggiornati 2026-05-10)
1. iOS only fino a 1000 utenti paganti, poi si valuta Android
2. Nessuna feature AI nell'MVP. Si aggiungono dopo il lancio.
3. ~~Nessun account obbligatorio~~ → **Account obbligatorio** (richiesto dalle Jam sociali). Highlight locali restano in SwiftData offline, ma Jam e sync richiedono identità.
4. Tempo budget founder: massimo 5 ore/settimana
5. Monorepo: `ios/` + `web/` + `supabase/` + `scripts/` in un unico repo

---

## 2. ⚠️ Setup tecnico del founder (LEGGI ATTENTAMENTE)

Questo è un caso particolare che cambia come lavoriamo.

### La realtà
- **Il founder usa un PC Windows** come macchina principale
- **Tu (Claude) giri nell'app desktop Claude per Windows**, tab Code o Cowork
- **Per compilare e testare un'app iOS serve macOS + Xcode** (non aggirabile, è un vincolo Apple)
- **Il founder NON ha (al momento) un Mac fisico**

### Cosa significa concretamente
Tu puoi:
- ✅ Scrivere tutto il codice Swift/SwiftUI corretto
- ✅ Strutturare il progetto Xcode (file `.xcodeproj`/`.xcworkspace` sono editabili anche da Windows)
- ✅ Scrivere i test
- ✅ Gestire git, fare commit, push, PR
- ✅ Mantenere CLAUDE.md, BACKLOG.md, PROGRESS.md aggiornati

Tu NON puoi:
- ❌ Compilare il codice (serve `xcodebuild`, solo macOS)
- ❌ Lanciare il simulatore iPhone (solo macOS)
- ❌ Eseguire test che richiedono iOS runtime (ne saprai solo che sono scritti, non se passano)
- ❌ Fare archive e pubblicare sull'App Store

### Strategia operativa

**Fase 1 — Sviluppo "blind compile" (settimane 1-6)**
- Tu scrivi codice Swift di alta qualità seguendo best practice rigorose
- Compensi l'assenza di feedback compiler con: linting concettuale, doppio controllo type, riferimenti continui alla documentazione Apple ufficiale
- Quando hai dubbi su API specifiche (firma di un metodo SwiftUI, comportamento di un modificatore), invece di indovinare consulta Apple Developer Documentation tramite web search
- Scrivi unit test esaustivi, anche se non possiamo eseguirli ora

**Fase 2 — Validazione su Mac (occasionale, 1-2 giorni)**
- Il founder periodicamente accederà a un Mac (servizio cloud tipo MacInCloud, oppure Mac di un familiare)
- In quei giorni: clone del repo, apertura in Xcode, fix di errori di compilazione veri, test reali sul simulatore
- Tu in quei giorni lavori in modalità "interattiva" (sessioni più brevi, supervisionate)
- Tutti gli errori di compilazione che emergono → diventano voci in un file `LESSONS-LEARNED.md` che crei e mantieni, così la fase blind successiva è meno cieca

**Fase 3 — Pre-lancio (Mac dedicato)**
- Quando si avvicina il lancio (~2 mesi prima), il founder valuterà: comprare Mac mini base (~700€) o noleggiare cloud Mac per il periodo finale
- Tutta la fase di rifinitura, screenshot App Store, archivio, submission richiede Mac dedicato

### Implicazioni sul tuo modo di lavorare

1. **Doppio del rigore sul codice.** Non hai il safety net del compiler. Ogni linea deve essere verosimilmente corretta. In caso di dubbio, consulta documentazione, non improvvisare.

2. **Test esaustivi anche se non eseguibili.** Scrivili comunque. Quando arriveranno su Mac e gireranno, troveremo i bug che adesso non vediamo.

3. **Niente over-engineering.** Codice semplice = meno superficie per errori invisibili. Pattern semplici, niente metaprogrammazione, niente trucchi.

4. **Documentazione interna ricca.** Per ogni file che crei, commenti chiari su cosa fa e perché. Quando torneremo su Mac e qualcosa non compila, vogliamo capire al volo perché era stato scritto così.

5. **`LESSONS-LEARNED.md` è critico.** Crealo dalla prima sessione. Ogni volta che il founder torna da Mac con errori, li annotiamo lì. Diventa la tua "memoria di realtà" del progetto.

---

## 3. Come Claude deve lavorare in questo repo

### Modalità di lavoro
Lavori in autonomia per sessioni di 2-4 ore (in tab Code o Cowork dell'app Claude). Quando finisci una sessione:
1. Fai commit con messaggio descrittivo
2. Aggiorni `PROGRESS.md` con: cosa hai fatto, cosa resta, problemi incontrati
3. Se hai dubbi importanti, scrivi in `QUESTIONS.md` e procedi su altre task

### Cosa fai in autonomia
- Implementare feature da `BACKLOG.md` seguendo l'ordine di priorità
- Scrivere unit test (target: 70% coverage sulle parti business logic)
- Refactoring locali quando il codice puzza
- Aggiornare documentazione tecnica in `docs/`
- Fare ricerche tecniche sulla documentazione Apple per API che non conosci

### Cosa NON fai mai senza conferma esplicita
- Cambiare lo stack o aggiungere dipendenze esterne
- Modificare lo schema database in modi non retrocompatibili
- Toccare il provisioning profile, certificates, App Store Connect
- Pushare su `main` (lavora sempre su feature branch + PR per il founder)
- Aggiungere chiamate API a servizi esterni non già in lista
- Fare commit che cambiano >500 righe in un colpo solo (spezza in commit logici)

### Stile di codice
- SwiftUI dichiarativo, niente UIKit se non strettamente necessario (widget esclusi)
- MVVM leggero: View + ViewModel + Repository. Niente architetture astronave.
- Naming in inglese, commenti in inglese tecnico
- Niente abbreviazioni: `clipping` non `clp`, `highlightCount` non `hCnt`
- Errori gestiti con `Result` o `throws`, mai con optional silenziosi
- **Doppio del rigore** rispetto al normale (vedi sezione 2)

### Stile messaggi di commit
Vedi `.claude/commit-style.md`

---

## 4. Architettura — vedi ARCHITECTURE.md

Struttura monorepo implementata:
```
Marginalia/
├── ios/                    # Swift app (SwiftData, SwiftUI, WidgetKit)
│   ├── Sources/Marginalia/ # Library: modelli, parser, services, views
│   ├── Sources/MarginaliaWidgets/
│   └── Tests/
├── web/                    # Next.js companion (Vercel)
│   ├── app/
│   ├── components/
│   └── lib/supabase/
├── supabase/               # Migrations + Edge Functions
│   ├── migrations/
│   └── functions/parse-clippings/
├── scripts/                # kindle-sync.py (Windows/Mac)
├── ARCHITECTURE.md         # Decisioni architetturali dettagliate
└── [file di processo]
```

Modelli implementati: `Book`, `Highlight`, `Tag`, `Jam` in `ios/Sources/Marginalia/Core/Models/`.

---

## 5. Convenzioni e gotchas

### Lingua
- UI in italiano (mercato primario) + inglese (secondario)
- Stringhe in `Localizable.xcstrings` (formato nuovo iOS 17)
- Commenti tecnici nel codice in inglese

### Performance
- Una libreria reale può avere 10.000+ highlight. Tutto deve scalare.
- Usa `@Query` con predicates limitate, mai caricare tutto in memoria
- Widget: budget memoria 30MB. Pre-calcola gli highlight da mostrare (background task notturno).

### Errori comuni che hai già fatto e che NON DEVI ripetere
*(Sezione che si popola nel tempo. Vuota all'inizio. Riempila tu quando ricevi feedback dal founder.)*

---

## 6. Chiusura sessione

Vedi `.claude/end-session.md` per la checklist completa.
