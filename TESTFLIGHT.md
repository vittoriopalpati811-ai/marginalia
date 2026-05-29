# Marginalia → TestFlight checklist

Single source-of-truth for shipping Marginalia to TestFlight. The
codebase is now set up so that the entire iOS build — including the
native Xcode project and the app icon — is generated automatically on
Codemagic's Mac runners. You don't need a Mac and you don't need Flutter
installed locally for any of this.

**Target audience for this doc:** the founder (Windows, no Mac).

What's left for you is purely the account/credentials plumbing that only
you can do (Apple + Codemagic web UIs). Everything mechanical is done.

---

## What's already done (committed + automated)

- ✅ **iOS native shell is generated in CI.** `codemagic.yaml` runs
  `flutter create --platforms=ios --org io.marginalia .` on the Mac
  runner before building. That produces `Runner.xcodeproj`,
  `Runner.xcworkspace`, `AppDelegate.swift`, `LaunchScreen.storyboard`,
  the asset catalog, and the `Podfile` — none of which need to live in
  git. `flutter create` never overwrites existing files, so the
  hand-written `ios/Runner/Info.plist` is preserved.
- ✅ **Bundle identifier normalized to `io.marginalia.app`.** `flutter
  create --org io.marginalia` would name it `io.marginalia.marginalia`;
  a one-line step in CI rewrites it to the canonical `io.marginalia.app`
  that matches the signing config and the App Store Connect record.
- ✅ **App icon committed + auto-resized.** A 1024×1024 source lives at
  `assets/icon/app-icon.png` (matcha-green "M" placeholder). CI runs
  `dart run flutter_launcher_icons` to expand it into every required iOS
  size. **You can replace it any time** — see "Replacing the app icon".
- ✅ **`ios/Runner/Info.plist`** — bundle metadata,
  `NSPhotoLibraryUsageDescription`, ProMotion (120 Hz) flag, indirect
  input events. (No stray `Main.storyboard` reference — Flutter uses
  only `LaunchScreen`.)
- ✅ **`codemagic.yaml`** — full pipeline: Flutter setup, l10n,
  build_runner (Isar), tests, `pod install`,
  `app-store-connect fetch-signing-files --create`, `xcode-project
  build-ipa`, and publish to the "Tester interni" beta group.
- ✅ **Backend hardening** — storage buckets have file-size limits +
  MIME whitelists.

---

## What you need to do (in order)

Three real steps. The first two are one-time setup; after that, releasing
is just `git push`.

### Step 1 — Create the App Store Connect record (10 min, browser)

The official "this app exists" registration with Apple. Needed before
the first TestFlight upload.

1. Sign in to https://appstoreconnect.apple.com with your Apple
   Developer account.
2. **My Apps** → **+** → **New App**.
3. Fill in:
   - Platform: **iOS**
   - Name: **Marginalia**
   - Primary language: **Italian (Italy)** (or English if you prefer)
   - Bundle ID: **io.marginalia.app** (must match exactly — this is what
     CI builds and signs)
   - SKU: any unique string, e.g. `marginalia-001`
   - User access: Full access
4. Save. On the reloaded page, under **App Information**, you'll see
   **Apple ID** — a numeric value like `6470012345`. Copy it.

Optional but tidy: open `codemagic.yaml`, replace the
`APP_STORE_APPLE_ID: "REPLACE_WITH_NUMERIC_APPLE_ID"` placeholder with
that number, and commit. (Codemagic matches the app by bundle ID when
publishing, so the build won't fail without it — but it's good to have
the real value recorded.)

> If you don't already have an Apple Developer membership, enroll first
> at https://developer.apple.com/programs ($99/yr). You need it to have
> an App Store Connect account at all.

---

### Step 2 — Connect Codemagic (15 min, browser)

This is the only step that absolutely requires the Codemagic web UI.

1. Sign in to https://codemagic.io with GitHub (the account that owns
   `vittoriopalpati811-ai/marginalia`).
2. **Apps** → find Marginalia → connect the repo.
3. **Teams** → **Personal Account** → **Integrations** → **App Store
   Connect**:
   - Issuer ID + Key ID: from https://appstoreconnect.apple.com/access/api
   - .p8 file: download once from that same page
   - Name the integration anything (e.g. `marginalia-asc`).
4. **Code signing identities** → Apple Developer Portal integration:
   on the first build, Codemagic auto-creates a distribution certificate
   + provisioning profile for `io.marginalia.app` (the
   `fetch-signing-files --create` step handles this).
5. **App settings** → **Workflow settings** → confirm `codemagic.yaml`
   is selected as the build configuration.

---

### Step 3 — Build + install (~25 min build, automatic)

```bash
git push origin master
```

Codemagic detects the push and runs `codemagic.yaml`. Watch in the web UI:

- `Generate iOS native shell` → `flutter create` + bundle-ID rewrite.
- `Set up Flutter` → `pub get`.
- `Generate app icons` → expands `app-icon.png` into the AppIcon set.
- `Generate localizations` → `build_runner` → `Run tests` (all green on
  master for the web build already).
- `Install CocoaPods` → `pod install` in `ios/`.
- `Fetch signing files` → auto-creates cert + profile.
- `Build IPA` → `build/ios/ipa/Runner.ipa`.
- `publishing` → uploads to App Store Connect → TestFlight.

When the build succeeds, App Store Connect emails you that the build is
processing. **Processing takes 10–30 min on Apple's side** — you'll get
a second email when it's installable.

Then, on your iPhone:

1. Install **TestFlight** from the App Store (free Apple app).
2. Open TestFlight → follow the email link / **Redeem**.
3. Marginalia appears as a beta app — **Install**.
4. Open and use. Report bugs back to yourself by email.

---

## Subsequent releases (after the first one ships)

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.0+2`).
2. `git push origin master`.
3. ~25 min later, the new build is in TestFlight.

That's it.

---

## Replacing the app icon

The committed icon is an on-brand placeholder (matcha "M"). To use a
real one:

1. Export a **1024×1024 PNG**: no transparency (Apple rejects
   transparent icons), no rounded corners (iOS applies its own mask).
2. Overwrite `assets/icon/app-icon.png` with it.
3. Commit + push. CI regenerates every size automatically.

No need to run anything locally.

---

## What's NOT yet wired up

These don't block a TestFlight INTERNAL beta but DO block public App
Store review:

- **Sign in with Apple** (Apple Guideline 4.8 requires it on iOS when
  other social logins are offered). Currently disabled on Supabase.
- **Google OAuth callback URL scheme** in `CFBundleURLTypes`. Currently
  Google OAuth is also disabled on Supabase.
- **Storage `message-images` bucket is PUBLIC.** DM photos are
  world-readable by URL. Privatising requires switching upload code to
  signed URLs + migrating existing `image_url` values in the `messages`
  table. Not blocking for TestFlight internal because the beta tester
  (you) is the only person using it.
- **App Store metadata** (screenshots, description, keywords, support
  URL, marketing URL, privacy policy URL, age rating). Required for App
  Store submission, NOT for TestFlight internal.

---

## Troubleshooting

- **Build fails at `Generate iOS native shell`**: `flutter create` is
  idempotent and safe to re-run; a failure here usually means a transient
  network/SDK issue on the runner — just retry the build.
- **Codemagic build fails at `pod install`**: usually a Flutter plugin
  with a misconfigured iOS subspec. Read the error; the fix is almost
  always bumping the plugin version or `pod repo update` (Codemagic does
  this automatically on retry).
- **Codemagic build fails at signing**: the `fetch-signing-files` step
  needs the bundle ID registered in the Apple Developer Portal. It does
  this automatically with `--create`, but if it fails, register
  `io.marginalia.app` manually at https://developer.apple.com/account →
  Certificates, Identifiers & Profiles → Identifiers → +.
- **Wrong bundle ID in the build**: the `Generate iOS native shell` step
  logs the bundle identifiers after rewriting — they should all read
  `io.marginalia.app`. If not, check the `perl` rewrite line in
  `codemagic.yaml`.
- **TestFlight build "Missing Compliance"**: Apple's export-compliance
  question. Answer "no" to the cryptography questions (Marginalia uses
  only Apple's stock TLS for HTTPS, which is exempt).
