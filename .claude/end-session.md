# End Session — checklist di chiusura

> Claude esegue questi step quando decide (o gli viene chiesto) di chiudere la sessione.

## Checklist

1. **Stato del codice**
   - [ ] Tutte le modifiche sono in commit (no file modificati non committati)
   - [ ] Nessun `print()` dimenticato, nessun `// TODO` cane
   - [ ] Nota: NON puoi verificare che la build compili (sei su Windows blind compile). Indica esplicitamente "build status: non verificabile da Windows" nel summary.

2. **Git**
   - [ ] Tutti i commit su feature branch (mai su main)
   - [ ] Branch pushato su origin
   - [ ] PR creata in stato "Draft" via integrazione GitHub dell'app Claude (o gh CLI se disponibile), con descrizione che linka le TASK-XXX completate

3. **PROGRESS.md**
   - [ ] Sessione corrente aggiornata: durata, branch, commit hash, fatto/in-progress/bloccato/note
   - [ ] Stato del progetto in alto aggiornato
   - [ ] Task completate spostate dal BACKLOG.md (cancellate da lì) con riferimento al commit

4. **QUESTIONS.md**
   - [ ] Eventuali nuove domande aggiunte con status corretto
   - [ ] Domande risolte durante la sessione marcate ✅ con la risposta

5. **LESSONS-LEARNED.md** (se applicabile)
   - [ ] Se sessione di bug fix post-Mac: aggiunta voce per ogni errore corretto

6. **Summary finale**
   Stampa nel pannello chat (italiano) un blocco così:

   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   SESSIONE TERMINATA
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Durata: Xh
   Branch: feature/...
   Commit: N
   PR draft: link
   Build status: non verificabile da Windows blind compile

   ✅ Completate: TASK-XXX, TASK-YYY
   🔄 In progress: TASK-ZZZ (al ~70%)
   ❓ Bloccato su: vedi QUESTIONS.md voce [DATA]
   📝 LESSONS-LEARNED: N nuove voci aggiunte (se applicabile)

   Per la prossima sessione:
   - [cosa guardare per primo]
   - [eventuali rischi]

   Confidence sul codice scritto (1-5):
   - Parser: X (motivazione)
   - UI: Y (motivazione)
   - Modelli: Z (motivazione)

   I punti con confidence <4 sono i primi da validare al prossimo accesso Mac.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```

## Quando chiudere la sessione

Chiudi se:
- Hai finito tutte le task pianificate per la sessione
- Sono passate ~3h dall'inizio
- Sei bloccato su un dubbio architetturale (scrivi in QUESTIONS.md e chiudi)
- Senti il context appesantirsi (risposte lente, perdita di filo)

NON chiudere se:
- Hai modifiche non committate (committa prima)
- Hai lasciato il branch in stato instabile

## Specifico blind compile

Per ogni file Swift creato o modificato in modo significativo, includi nel summary una stima della tua confidence (1-5):
- 5 = sintassi banale, API che conosco perfettamente, basso rischio errori al compile
- 3 = ho usato API recenti dove potrei avere imprecisioni
- 1 = stiamo nuotando in zone dove serve quasi sicuramente fix su Mac

Questo aiuta il founder a sapere cosa controllare per primo quando andrà su Mac.
