# Prompt PRIMA SESSIONE — incolla questo in Claude (app desktop, tab Code o Cowork)

> Da usare SOLO la prima volta. Le sessioni successive usano `start-session.md`.

---

## 📋 PROMPT DA COPIARE/INCOLLARE

```
Ciao Claude. Iniziamo a lavorare insieme sul progetto Marginalia, un'app iOS nativa per riscoprire gli highlight del Kindle attraverso widget intelligenti.

CONTESTO IMPORTANTE SU DI ME E IL SETUP:
- Sono Vittorio, founder solo del progetto
- Lavoro full-time altrove (Deloitte), posso dedicare ~5h/settimana al progetto
- Sono su PC WINDOWS, non ho un Mac al momento
- Vogliamo comunque costruire un'app iOS NATIVA (Swift, SwiftUI, WidgetKit), non multipiattaforma
- Stiamo dentro l'app desktop Claude per Windows, tab Code (o Cowork per task più lunghi)
- Per compilare e testare l'app servirà accesso periodico a un Mac (cloud o di terzi)

═══════════════════════════════════════════════════════════
PRIMA DI SCRIVERE QUALSIASI CODICE: leggi i file del progetto
═══════════════════════════════════════════════════════════

Trovi nella cartella del progetto:
1. CLAUDE.md — regole, stack, vincoli, IMPORTANTE: contiene la sezione "Setup tecnico del founder" con la strategia per il workflow Windows + iOS
2. BACKLOG.md — task ordinate
3. PROGRESS.md — log sessioni (vedrai solo Sessione 0)
4. QUESTIONS.md — dubbi aperti
5. LESSONS-LEARNED.md — errori da non ripetere (vuoto all'inizio)
6. README.md — overview
7. .claude/commit-style.md — convenzioni commit
8. .claude/end-session.md — checklist fine sessione

═══════════════════════════════════════════════════════════
AUTORIZZAZIONE IMPORTANTE: ADATTA I FILE COME RITIENI
═══════════════════════════════════════════════════════════

I file sopra sono una BOZZA INIZIALE che ho preparato insieme a un'altra istanza di Claude. Sono base di partenza, non vangelo.

Sei autorizzato e incoraggiato a:
- RIORGANIZZARE i file se trovi una struttura migliore
- AGGIUNGERE sezioni mancanti che ti renderebbero più efficace
- CORREGGERE incoerenze che noti leggendo
- SPEZZARE un file in più file se è troppo monolitico
- UNIRE file se sono ridondanti
- PROPORRE file nuovi che non avevo pensato (es. ARCHITECTURE.md, GLOSSARY.md, ecc.)

Per modifiche piccole (typo, chiarimenti, esempi): procedi in autonomia, segnala nel commit.

Per riorganizzazioni strutturali (spostare file, cambiare logica del workflow): scrivi prima in QUESTIONS.md cosa vuoi fare e perché, e procedi solo con il mio OK.

L'obiettivo è che TU ti trovi bene a lavorare con questi file, perché ci lavorerai per mesi. Se ci sono cose mal pensate, dilo subito.

═══════════════════════════════════════════════════════════
COSA FARE ADESSO (ordine preciso)
═══════════════════════════════════════════════════════════

PASSO 1 — Leggi tutti i file elencati sopra, con attenzione

PASSO 2 — Fammi un riassunto di max 15 righe in cui mi dici:
(a) Cosa hai capito del progetto e del setup particolare Windows-iOS
(b) Stack tecnico
(c) Quale task inizierai per prima e perché
(d) AMBIGUITÀ E PROBLEMI che hai trovato nei file (importante: NON dirmi "tutto chiaro" se non lo è davvero. Se i file hanno difetti, dillo)
(e) PROPOSTE DI MIGLIORAMENTO ai file: cosa cambieresti, aggiungeresti, riorganizzeresti

PASSO 3 — FERMATI. Aspetta il mio OK su due cose:
- OK sulle eventuali modifiche ai file di processo che proponi
- OK a partire con TASK-001

Non scrivere codice prima di questo doppio OK. Voglio fare un check di allineamento serio prima di lasciarti andare in autonomia per ore. Saltare questo step costa più che farlo.

═══════════════════════════════════════════════════════════
REGOLE GENERALI DI SESSIONE
═══════════════════════════════════════════════════════════

LAVORI IN AUTONOMIA, MA:
- Mai pushare su main. Sempre feature branch + PR per me.
- Commit piccoli, frequenti. Mai +500 righe in un commit.
- Dubbio architetturale → QUESTIONS.md, poi passa ad altre task indipendenti.
- Build rotta non risolvibile in 30 min → stop, scrivi in QUESTIONS.md, passa ad altro.
- Aggiorna PROGRESS.md a fine sessione.
- Se finisci tutte le task pianificabili: stop con summary, non inventare task.

NON FARE MAI SENZA CHIEDERMI PRIMA:
- Cambiare lo stack tecnico (Swift+SwiftUI+SwiftData fissi)
- Aggiungere dipendenze esterne non in lista
- Modificare schema dati in modi non retrocompatibili
- Modificare CLAUDE.md (puoi proporre modifiche, non applicarle direttamente per la struttura)
- Pushare su main

VINCOLO SPECIALE BLIND COMPILE (importantissimo):
- Sei su Windows, non puoi compilare codice iOS, non puoi lanciare il simulatore
- Compensi con: rigore extra, consultazione documentazione Apple per ogni API non sicura, doppio controllo dei tipi, test scritti anche se non eseguibili
- Quando il founder accederà a un Mac, troverà errori. Quegli errori → LESSONS-LEARNED.md
- Niente over-engineering, niente metaprogrammazione: codice semplice = meno errori invisibili

═══════════════════════════════════════════════════════════
STILE DI COMUNICAZIONE
═══════════════════════════════════════════════════════════

- Italiano per i messaggi a me, i commit, PROGRESS.md, QUESTIONS.md
- Inglese per il codice, naming, commenti tecnici
- Concisione: leggo i tuoi update di sera dopo 9h di lavoro. Vai al punto.
- Niente "Perfetto!" "Fatto!" gratuiti. Solo fatti.
- Problemi seri → dilli esplicitamente, non camuffarli

═══════════════════════════════════════════════════════════
COMINCIA ORA
═══════════════════════════════════════════════════════════

Step 1: leggi i file
Step 2: rispondimi con riassunto + ambiguità + proposte modifiche
Step 3: aspetta il mio doppio OK

Vai.
```

---

## 🎯 Cosa controllare nella risposta di Claude

### ✅ Risposta accettabile se:
- Conferma di aver capito il setup Windows + iOS + accesso Mac periodico
- Cita stack giusto
- Ha una proposta di prima task (TASK-001 o ragionata variante)
- **Ha trovato almeno 2-3 cose da migliorare nei file** (è un buon segno: significa che ha letto davvero, non superficialmente. Se dice "tutto perfetto" → bandiera rossa, probabilmente non ha letto bene)

### ❌ Allarmi rossi:
- Propone stack diverso (es. "potremmo usare Flutter")
- Ignora il vincolo blind compile
- Vuole subito scrivere codice senza il check di allineamento
- Dice che tutto è chiaro al primo sguardo (= non ha letto davvero)
- Inventa task non in BACKLOG

### Se trova problemi ragionevoli nei file:
Discuti con lui, accetta i suggerimenti se sensati, modifica i file insieme, POI dai OK per partire.

### Se è tutto allineato:
> "Ok sulle modifiche [X, Y, Z]. Applicale e committa con `[docs] adapt project files based on Claude review`. Poi parti con TASK-001. Lavora in autonomia, ci risentiamo stasera."

E vai a fare altro.

---

## 💡 Trucchi extra per la prima sessione

1. **Stai davanti** la prima volta. Non lanciare e scappare.
2. **Se TASK-001 va bene**, lascialo continuare con TASK-002 e 003 sotto i tuoi occhi. Quando hai visto che il pattern funziona, allora deleghi.
3. **Tieni un blocco note** mentre osservi: ogni volta che fa qualcosa che non vuoi, segnatelo. A fine giornata aggiorni la sezione "Errori comuni" in CLAUDE.md.
4. **Non aver paura di interromperlo**. Se sbaglia rotta, premi Esc, "stop, stai sbagliando perché X, riparti da Y". Meglio interrompere subito che lasciare accumulare debito tecnico.
