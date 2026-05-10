# Marginalia

iOS app per riscoprire i propri highlight Kindle attraverso widget intelligenti.

## ⚠️ Setup particolare di questo progetto

- **Founder lavora da Windows** con app desktop Claude (tab Code / Cowork)
- **App è iOS nativa** (Swift, SwiftUI, SwiftData)
- **Compilazione e test reali avvengono su Mac**, accesso periodico
- **Strategia**: blind-compile da Windows, validazione periodica su Mac

Vedi `CLAUDE.md` sezione 2 per dettagli.

## Per Claude

Leggi nell'ordine prima di toccare codice:
1. `CLAUDE.md` — regole del progetto, stack, vincoli, **inclusa autorizzazione a riorganizzare i file**
2. `BACKLOG.md` — cosa fare, in che ordine
3. `PROGRESS.md` — cosa è stato fatto finora
4. `QUESTIONS.md` — domande aperte
5. `LESSONS-LEARNED.md` — errori già visti su Mac, da non ripetere

## Per il founder

- Sera: aggiorna sezione "Brief sessione corrente" in `BACKLOG.md`
- Mattina: lancia Claude (app desktop, tab Code o Cowork), incolla prompt da `.claude/start-session.md`
- Sera: review `PROGRESS.md`, rispondi a `QUESTIONS.md`, prepara prossimo brief
- Periodicamente (ogni 2-3 settimane): accesso a Mac, fix errori reali, popola `LESSONS-LEARNED.md`

## Stack

iOS 17+, Swift, SwiftUI, SwiftData, WidgetKit. Backend (post-MVP): Supabase.
