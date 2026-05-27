# Mobile viewport verification — 2026-05-27

Tested against the deployed build (commit `b0361e0`) via the embedded
iPhone mockup on the landing page (`https://vittoriopalpati811-ai.github.io/marginalia/`)
and the full app at `app.html` plus `#/stats`.

## Screens verified

### ✅ Library (home)
- Header `Marginalia` + greeting `Buon pomeriggio, vittorio` — IT locale picked up correctly.
- Section headers `SCELTO PER TE`, `RECENTI`, `LA TUA LIBRERIA` — IT.
- Filter chips `TUTTI` / `PREFERITI` — IT (new `libraryFilterAll/Favorites` keys).
- Daily card quote renders in italic EB Garamond; "Leggi >" CTA at the bottom in IT.
- Recent strip shows horizontally scrolling cards with book title in spaced caps + italic body — looks clean at narrow widths.
- Bottom nav: 5 tabs (Home / Library / Jam / Messages / Profile) labeled in EN (these are still hardcoded — see "Remaining tasks").

### ✅ Stats (`/stats`)
- Header `Le tue statistiche` ✓
- Section `OBIETTIVO 2026` with empty-goal CTA `Imposta obiettivo` ✓
- `PANORAMICA` row with 3 cards: `STREAK DI LETTURA`, `QUESTO MESE`, `QUEST'ANNO` ✓
- Big numeric `0`s render in matcha; subtitles in IT (`Nessuna streak`, `0 min letti`, `0 libri finiti`).
- 12-month bar chart axis labels — **previously mixed locale (G L A S O N D J F M A M)**, now locale-aware via `intl.DateFormat.MMM` → IT will read `Giu Lug Ago Set Ott Nov Dic Gen Feb Mar Apr Mag`.
- `SESSIONI RECENTI` with empty state: `Nessuna sessione ancora. Tocca il + per registrare la prima.` ✓
- FAB `+ Aggiungi sessione` ✓

## Bugs found and fixed

1. **Month chart labels mixed locales** (stats_screen.dart). My initial implementation hardcoded one-letter Italian-ish labels (`J F M A M G L A S O N D`) which is half English (`J` for January) and half Italian (`G` for Giugno, `L` for Luglio). Fixed by switching to `DateFormat.MMM(locale)` from `package:intl` so labels follow the user's locale (`Gen`/`Jan` etc.).

## Layout observations (pre-existing, not blockers)

These are characteristics of the current mobile-first design that show up when the app is opened on desktop / tablet — not breakage on mobile:

- **Library grid stays 2 columns at any width** (`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2)`). On a 1568px desktop screen the cards become ~780px wide — visually awkward but readable. Mobile is the primary target; consider adding a responsive `crossAxisCount` based on width as a future improvement.
- **Bottom nav stretches edge-to-edge** at desktop instead of rendering as the centred glass pill. Same root cause: no max-width constraint. Pill looks correct on mobile (verified via mockup) at 375 px.
- **Daily-card decorative quotation mark** uses `siennaFaint` which is intentionally low-contrast — on first read it can look like a rendering glitch. Consider bumping opacity slightly if we get user reports about it.

## Things deliberately not changed

- Italian locale shows `vittorio` in lowercase in the greeting because the underlying `display_name` was saved lowercase. This is data, not a UI bug — fix is to suggest title-casing on profile save (future task).
- Some error snackbars still read `Error: $e` in English — those are intentionally raw because they're dev-facing and rarely hit in normal use. If we want to ship to non-technical users in IT we should l10n them with `errorPrefix(message: $e)`.

## Tools used

- Chrome MCP via the user's local browser (window resize + screenshots + navigation).
- GitHub Actions API to confirm the deployed commit (`b0361e0`) succeeded before testing.
- Embedded iPhone mockup on the landing page for true 375 px visual check.
