# Commit style

## Formato
```
[area] descrizione breve in italiano, lowercase
```

## Aree valide
- `[setup]` — config progetto, dipendenze, CI
- `[models]` — modelli dati, schema, migrazioni
- `[parser]` — parsing My Clippings
- `[import]` — flusso import
- `[ui]` — viste SwiftUI
- `[widget]` — widget extension
- `[search]` — ricerca, FTS
- `[ai]` — feature AI (post-MVP)
- `[fix]` — bug fix
- `[test]` — solo test, no codice produttivo
- `[refactor]` — refactor senza cambio comportamento
- `[docs]` — solo documentazione

## Regole
- Massimo 72 caratteri sulla prima riga
- Verbo all'imperativo: "aggiungi" non "aggiunto"
- Niente punto finale
- Body opzionale dopo riga vuota, solo se serve spiegare il "perché"

## Esempi buoni
```
[parser] gestisci encoding UTF-16 con BOM
[ui] empty state libreria con CTA import
[fix] crash su highlight con location nil
[refactor] estrai BookCoverView da LibraryRow
[docs] adatta CLAUDE.md sezione blind compile
```

## Esempi cattivi (NON FARE)
```
update                                    # troppo vago
[ui] aggiunti vari miglioramenti          # cosa, di preciso?
[various] fix bug e refactor parser       # spezza in 2 commit
WIP                                       # mai sul branch principale
[parser] Aggiunta gestione encoding.      # caps + punto
```

## Granularità
Una task del backlog = 1-5 commit, mai 1 commit gigante.
Se stai per fare un commit con +500 righe modificate, fermati e spezza.
