# Lessons Learned

> File critico per il workflow Windows-blind-compile.
>
> Ogni volta che il founder accede a un Mac e trova errori di compilazione, di runtime, o comportamenti inattesi nel codice scritto da Claude su Windows: si annotano qui.
>
> Questo file è la "memoria di realtà" del progetto. Riduce gli errori della fase blind compile successiva.
>
> Claude consulta questo file prima di iniziare ogni sessione, dopo CLAUDE.md.

---

## Formato delle voci

### [DATA] - [Categoria] - Titolo breve dell'errore

**Cosa sembrava giusto sulla carta:**
[Descrizione di cosa Claude aveva scritto]

**Cosa è successo davvero:**
[Errore esatto: messaggio del compiler / runtime exception / comportamento inatteso]

**Causa radice:**
[Perché era sbagliato]

**Lezione applicabile in futuro:**
[Regola generale che eviterà l'errore in casi simili]

**Riferimento:**
[Link a doc Apple / commit fix / issue]

---

## Voci

*(Vuoto all'inizio. Si popolerà dopo i primi accessi a Mac.)*

---

## Categorie di errori che ci aspettiamo

Per orientamento, queste sono aree dove la fase blind compile è più rischiosa:

1. **API SwiftUI nuove (iOS 17+)**: SwiftData, Observable macro, nuovi modificatori di NavigationStack
2. **Concurrency (async/await, actors, MainActor)**: facili da scrivere "quasi giusti"
3. **WidgetKit**: limiti di memoria, TimelineProvider, Intent configuration
4. **App Group e shared container**: configurazione che richiede progetto Xcode reale
5. **Bundle resources**: path, localizzazione, asset catalog
6. **Swift Package Manager vs Xcode project**: dipendenze, target, schemas
7. **Code signing e capabilities**: tutto ciò che richiede provisioning profile

---

## Pattern da seguire dopo aggiunta voce

Quando aggiungi una voce qui:
1. Considera se aggiornare anche `CLAUDE.md` sezione "Errori comuni che hai già fatto"
2. Considera se la lezione richiede modifiche a `BACKLOG.md` (task aggiuntive di refactor)
3. Se la lezione è sistemica (affligge molti file), apri una task dedicata in BACKLOG.md
