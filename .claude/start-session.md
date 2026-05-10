# Start Session — prompt da incollare in Claude (app desktop, tab Code o Cowork)

> Per le sessioni dalla 2 in poi. Per la PRIMA sessione usa `first-session-prompt.md` (più lungo, fa allineamento iniziale).

---

## Prompt standard

```
Ciao Claude. Nuova sessione di lavoro su Marginalia.

Step iniziali (5 minuti, prima di scrivere codice):
1. Leggi PROGRESS.md per capire dove eravamo
2. Leggi il "Brief sessione corrente" in cima a BACKLOG.md
3. Leggi QUESTIONS.md per vedere se ho risposto a dubbi pendenti
4. Leggi LESSONS-LEARNED.md se ci sono nuove voci dall'ultima sessione

Poi:
5. Crea un branch nuovo `feature/task-XXX-descrizione-breve` per la prima task
6. Scrivi in PROGRESS.md una sezione "Sessione N — [data]" con stato "in corso"
7. Inizia a lavorare

Regole di sessione (le sai già, te le ricordo):
- Lavora autonomo per max 3 ore
- Commit piccoli, frequenti
- Mai pushare su main
- Dubbi importanti → QUESTIONS.md, poi passa ad altre task
- Build rotta non risolvibile in 30 min → stop, scrivi in QUESTIONS.md
- Ricorda che siamo in modalità blind compile (Windows). Doppio rigore.

Quando finisci sessione segui `.claude/end-session.md`.

Vai.
```

---

## Variante "task specifica"

```
Ciao Claude, sessione su Marginalia.

Override: voglio che lavori SOLO su TASK-XXX, ignorando l'ordine del backlog.

Vincoli aggiuntivi: [eventuali, es: "non toccare il parser, è già a posto"]

Segui le solite regole di sessione. Aggiorna PROGRESS.md a fine.
```

---

## Variante "fix bug post Mac access"

```
Ciao Claude, sessione di bug fixing su Marginalia.

Sono tornato da una sessione su Mac. Errori trovati:
1. [errore 1]
2. [errore 2]
...

Workflow:
1. Per ogni errore: aggiungi voce in LESSONS-LEARNED.md (formato del file)
2. Sistema il bug nel codice
3. Aggiorna eventuali altri file con lo stesso pattern errato
4. Commit `[fix] descrizione`
5. Aggiorna PROGRESS.md

Non fare nuove feature, oggi solo cleanup.
```

---

## Variante "review e refactor"

```
Ciao Claude, sessione di review su Marginalia.

Niente nuove feature. Solo:
1. Leggi tutto il codice in [path]
2. Identifica code smell, duplicazioni, naming inconsistenti, possibili bug nascosti (importante in modalità blind compile)
3. Scrivi un REVIEW.md con la lista, ordinata per gravità
4. NON fixare niente automaticamente, voglio decidere io

Ferma quando hai finito la review.
```

---

## Variante "Cowork mode"

Se usi Cowork invece di tab Code (per task che vuoi delegare in background):

```
Task: [descrizione concisa, es. "implementa MyClippingsParser come da TASK-004 in BACKLOG.md"]

Workspace: [percorso cartella progetto Marginalia]

Prima di iniziare: leggi CLAUDE.md, BACKLOG.md (TASK-004 specifica), QUESTIONS.md, LESSONS-LEARNED.md.

Vincoli:
- Non pushare su main, sempre feature branch
- Commit piccoli e descrittivi
- Modalità blind compile (no Mac, no compiler)
- Dubbi → QUESTIONS.md, poi prosegui

Termina quando: TASK-004 completa OR sei bloccato OR sono passate 3h.

A fine: aggiorna PROGRESS.md, lascia summary chiaro.
```
