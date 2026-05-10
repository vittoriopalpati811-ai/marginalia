# Setup Mac — Guida al primo accesso

> Da eseguire la PRIMA VOLTA che accedi a un Mac (cloud o fisico).
> Dopo questo setup, tutto il resto avviene automaticamente via GitHub Actions.
> Stima tempo: 2-3 ore la prima volta.

---

## Prerequisiti da completare prima sul PC Windows

- [ ] Account Apple Developer creato ($99/anno) → [developer.apple.com](https://developer.apple.com)
- [ ] App Store Connect: crea l'app "Marginalia" con Bundle ID `io.marginalia.app`
- [ ] Repo GitHub privato per certificati (es. `github.com/tuonome/marginalia-certs`)
- [ ] Chiave App Store Connect API creata (Users & Access → Integrations → App Store Connect API)
  - Salva: Key ID, Issuer ID, file .p8

---

## Passo 1 — Clona il repo e installa dipendenze

```bash
git clone https://github.com/tuonome/marginalia.git
cd marginalia/ios

# Installa Homebrew se non presente
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Ruby + Bundler
brew install rbenv ruby-build
rbenv install 3.2.0 && rbenv global 3.2.0
gem install bundler

# Fastlane via Bundler
bundle install
```

---

## Passo 2 — Crea il progetto Xcode

Il Package.swift contiene la business logic, ma serve un progetto Xcode per compilare l'app.

```
1. Apri Xcode → File → New → Project
2. Template: iOS App
3. Product Name: MarginaliaApp
4. Bundle Identifier: io.marginalia.app
5. Team: seleziona il tuo Apple Developer account
6. Interface: SwiftUI
7. Language: Swift
8. Salva in: marginalia/ios/
```

Dopo la creazione:
```
1. File → Add Package Dependencies
2. Aggiungi path locale: ./  (la cartella ios/ con Package.swift)
3. Aggiungi target Marginalia all'app target principale
```

Crea anche la Widget Extension:
```
File → New → Target → Widget Extension
Nome: MarginaliaWidgets
Include Configuration Intent: No
```

Committa il .xcodeproj:
```bash
git add MarginaliaApp.xcodeproj
git commit -m "[setup] aggiungi progetto Xcode creato su Mac"
```

---

## Passo 3 — Setup Fastlane Match (certificati)

Match gestisce i certificati in un repo Git privato e li condivide con GitHub Actions.

```bash
# Inizializza Match (solo la prima volta)
bundle exec fastlane match init
# → scegli "git" come storage
# → inserisci URL repo privato per certificati (es. https://github.com/tuonome/marginalia-certs)

# Crea/scarica certificati per App Store
bundle exec fastlane match appstore
# → ti chiede MATCH_PASSWORD: scegli una password forte e salvala (serve in GitHub Secrets)

# Crea/scarica certificati per development (simulatore)
bundle exec fastlane match development
```

---

## Passo 4 — Configura GitHub Secrets

Vai su GitHub → Settings → Secrets and variables → Actions.
Aggiungi questi secrets:

| Secret | Come ottenerlo |
|--------|----------------|
| `MATCH_PASSWORD` | La password scelta al passo 3 |
| `MATCH_GIT_URL` | URL repo certificati (es. `https://github.com/tuonome/marginalia-certs`) |
| `ASC_KEY_ID` | Dall'App Store Connect API key |
| `ASC_ISSUER_ID` | Dall'App Store Connect API key |
| `ASC_KEY_CONTENT` | Contenuto del file .p8, convertito in Base64: `base64 -i AuthKey_XXXX.p8` |
| `APPLE_TEAM_ID` | Il tuo Team ID (visibile su developer.apple.com) |
| `APPLE_ITC_TEAM_ID` | Team ID per App Store Connect (spesso uguale ad APPLE_TEAM_ID) |

---

## Passo 5 — Prima build e TestFlight

```bash
# Build locale (verifica che tutto compili)
bundle exec fastlane beta
```

Se va a buon fine, vedrai l'app su App Store Connect → TestFlight.

Da quel momento in poi: ogni push su `main` → GitHub Actions builda → TestFlight aggiornato automaticamente.

---

## Passo 6 — Installa sul tuo iPhone

1. Installa l'app TestFlight sul tuo iPhone
2. Vai su App Store Connect → TestFlight → seleziona il build → Aggiungi tester interno
3. Aggiungi la tua Apple ID come tester
4. Apri email di invito su iPhone → Accetta → Installa

Da questo momento, ogni build automatica compare in TestFlight entro ~15 minuti dal push.

---

## Errori di compilazione frequenti (blind compile)

Quando compili per la prima volta troverai probabilmente errori. Per ognuno:
1. Nota l'errore esatto
2. Fixalo in Xcode
3. Aggiungi voce in `LESSONS-LEARNED.md`
4. Committa il fix

Le zone più fragili (ordine di probabilità errori):
1. `Tag` — relazione M:M con `@Relationship` (verifica sintassi)
2. `BookDetailView` — predicate su relazione nested (`$0.book.id`)
3. `AmazonLoginView` — import WebKit + UIKit (assicurati siano nel target)
4. `MarginaliaApp.swift` — `@main` non può stare in un library target SwiftPM
   → Sposta `MarginaliaApp.swift` nel target Xcode (non nella libreria)

---

## Supabase setup (se non già fatto)

1. [supabase.com](https://supabase.com) → New project
2. SQL Editor → esegui `supabase/migrations/001_initial_schema.sql`
3. SQL Editor → esegui `supabase/migrations/002_rls_policies.sql`
4. Storage → New bucket → `clippings` (private) e `avatars` (public)
5. Edge Functions → Deploy `supabase/functions/parse-clippings/`
6. Copia URL e anon key → aggiungi all'app iOS come constants

---

## Checklist fine primo accesso Mac

- [ ] Progetto Xcode creato e committato
- [ ] App compila senza errori (warning ok)
- [ ] Match configurato, certificati in repo privato
- [ ] GitHub Secrets configurati
- [ ] Prima build su TestFlight completata
- [ ] App installata su iPhone personale
- [ ] Errori di compilazione annotati in LESSONS-LEARNED.md
- [ ] Supabase setup completato
