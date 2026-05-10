# Progress Log

> Diario delle sessioni. Claude aggiorna questo file a fine sessione.
> Sessioni più recenti IN ALTO. Le task completate restano qui per storico.

---

## 📌 Stato attuale del progetto

**Fase**: Foundation completata (Swift + Web), pronta per setup Supabase
**Sprint corrente**: Sprint 1 - Foundation (COMPLETATO al 90%)
**Prossima task**: TASK-W01 (setup progetto Supabase e deploy web su Vercel)
**Branch attivo**: main (prima sessione, non ancora branch separati)
**Build status iOS**: ⚪ blind compile (non verificabile da Windows — necessita Mac)
**Build status Web**: 🟡 pronto per deploy, manca solo `.env.local` con chiavi Supabase

---

## Sessioni

### Sessione 1 — 2026-05-10
**Durata**: ~3h
**Branch**: main (prima sessione di setup)
**Commit**: vedi git log
**Mac access in questa sessione?**: NO

#### Fatto

**Architettura e struttura (TASK-001 ✅)**
- Monorepo ios/ + web/ + supabase/ + scripts/
- ARCHITECTURE.md creato con decisioni complete
- CLAUDE.md aggiornato con nuovo stack e vincoli
- .gitignore monorepo

**Database Supabase (TASK-DB ✅ — nuovo)**
- `supabase/migrations/001_initial_schema.sql` — schema completo
- `supabase/migrations/002_rls_policies.sql` — RLS per tutti i dati
- `supabase/functions/parse-clippings/index.ts` — Edge Function parsing (Deno)

**Web companion Next.js (TASK-WEB ✅ — nuovo)**
- Setup completo: package.json, tsconfig, tailwind, env.example
- Auth: magic link Supabase, middleware protezione routes
- Libreria: lista libri, book detail con highlights
- Import: upload My Clippings.txt drag&drop, polling risultato
- Jam: lista jam, creazione, join via codice, condivisione highlights
- Design: palette seppia/bianco caldo implementata in Tailwind

**iOS Swift (TASK-002, TASK-003, TASK-004, TASK-005, TASK-006, TASK-007, TASK-008, TASK-009, TASK-010 ✅)**
- Package.swift con targets Marginalia + MarginaliaWidgets
- Modelli SwiftData: Book, Highlight, Tag, Jam (con relazioni corrette + @Relationship)
- MyClippingsParser: IT/EN/FR, BOM, bookmark filter, dedup
- ImportService: dedup, idempotente
- Viste: LibraryView, BookDetailView, HighlightDetailView, SearchView, SocialView, RootView
- TabView con 4 tab (Libreria, Cerca, Jam, Impostazioni)
- Color(hex:) extension

**Fixture e test (TASK-003 ✅)**
- `ios/Tests/Fixtures/sample_clippings.txt` con 9 blocchi, 3 lingue, bookmark, dedup, nota
- ParserTests: 9 test cases che coprono tutti i casi del fixture

**Kindle sync Windows/Mac (TASK-SYNC ✅ — nuovo)**
- `scripts/kindle-sync.py` — polling drive, rilevamento My Clippings.txt, upload Supabase
- `scripts/requirements.txt` + `.env.example`

#### In progress
- Nessuna task aperta

#### Bloccato / domande
- Vedi QUESTIONS.md

#### Prossimo accesso Mac
Cose da verificare in ordine di priorità (per confidence sul codice):
1. **BASSA confidence**: `@Relationship` SwiftData su Tag (M:M) — sintassi non verificabile da Windows
2. **BASSA confidence**: `FetchDescriptor` con predicate annidato in BookDetailView (`$0.book.id`) — relazioni nested in `#Predicate` sono fragili
3. **MEDIA confidence**: `debounceTask` in SearchView (Task cancellation pattern) — corretto ma non testato
4. **ALTA confidence**: Parser, ImportService, Modelli base, Web app

#### Note per la prossima sessione
- Prima cosa: setup Supabase (crea progetto, esegui migrations, configura bucket)
- Seconda cosa: deploy Vercel con `.env.local` compilato → Vittorio può vedere tutto funzionare
- Terza cosa: testare upload My Clippings.txt dal web → Edge Function parsing
- iOS: rimanda a Mac access per compilazione reale

---

<!--
TEMPLATE per sessioni future. Copia/incolla SOPRA questa riga.

### Sessione N — [DATA]
**Durata**: ~Xh
**Branch**: feature/...
**Commit**: N (hash: abc123, def456, ...)
**Mac access in questa sessione?**: SÌ / NO

#### Fatto
- TASK-XXX: descrizione breve di cosa hai effettivamente prodotto
  - File toccati: ...
  - Test scritti: N

#### In progress
- TASK-YYY: a che punto sei, cosa manca

#### Bloccato / domande
- Vedere QUESTIONS.md voci [DATA]

#### Errori di compile/runtime trovati (solo se sessione su Mac)
- ...

#### Note per la prossima sessione
- Cosa guardare per primo
- Eventuali rischi tecnici emersi

-->
