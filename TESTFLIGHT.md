# Marginalia → TestFlight checklist

Single source-of-truth for shipping Marginalia to TestFlight. Run through
this from top to bottom the first time; once you've shipped one build,
subsequent releases skip most of this and just `git push`.

**Target audience for this doc:** the founder (Windows, no Mac).

---

## What's already done (committed to the repo)

- ✅ Backend: storage buckets have file-size limits + MIME whitelists.
- ✅ `ios/Runner/Info.plist` — bundle metadata + `NSPhotoLibraryUsageDescription`.
- ✅ `codemagic.yaml` — uses Codemagic CLI's `xcode-project build-ipa`
  (no hand-written `export_options.plist`), runs `pod install`,
  `app-store-connect fetch-signing-files`, and publishes to the
  "Tester interni" beta group.
- ✅ `pubspec.yaml` — `flutter_launcher_icons: ^0.13.1` added.
- ✅ `flutter_launcher_icons.yaml` — config for icon generation.

---

## What you need to do (in order)

### Step 1 — Generate the iOS native shell (5 min, Windows)

From the Marginalia repo root:

```bash
flutter create --platforms=ios --org io.marginalia .
```

This creates:
- `ios/Runner.xcodeproj/`
- `ios/Runner.xcworkspace/`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Assets.xcassets/` (with placeholder icons)
- `ios/Runner/Base.lproj/LaunchScreen.storyboard`
- `ios/Podfile`
- A few xcconfig files in `ios/Flutter/`

**Important:** `flutter create` does NOT overwrite files that already
exist, so the `Info.plist` I committed will be preserved.

Commit everything that was created:
```bash
git add ios/
git commit -m "ios: scaffold via flutter create --platforms=ios"
```

---

### Step 2 — Provide an app icon (5 min, Windows)

Drop a single 1024×1024 PNG at `assets/icon/app-icon.png`. Constraints:
- Exactly 1024×1024 pixels
- **No transparency** (Apple rejects transparent App Store icons)
- **No rounded corners** (iOS applies its own mask)

Then generate every size:
```bash
flutter pub get
dart run flutter_launcher_icons
```

This populates `ios/Runner/Assets.xcassets/AppIcon.appiconset/` with
the full set of sizes (20pt × 2/3, 29pt × 2/3, 40pt × 2/3, 60pt × 2/3,
plus the 1024×1024 App Store icon).

Commit the generated icons:
```bash
git add ios/Runner/Assets.xcassets/ assets/icon/
git commit -m "ios: app icon set generated from app-icon.png"
```

---

### Step 3 — Create the App Store Connect record (10 min, browser)

This is the official "app exists" registration with Apple. You need it
before the first TestFlight upload.

1. Sign in to https://appstoreconnect.apple.com with your Apple
   Developer account.
2. **My Apps** → **+** → **New App**.
3. Fill in:
   - Platform: **iOS**
   - Name: **Marginalia**
   - Primary language: **Italian (Italy)** (or English if you prefer)
   - Bundle ID: **io.marginalia.app** (must match `codemagic.yaml`
     `bundle_identifier`)
   - SKU: any unique string, e.g. `marginalia-001`
   - User access: Full access
4. Save. The page reloads and at **App Information** at the top of the
   left sidebar, you'll see **Apple ID** — a numeric value like
   `6470012345`. Copy it.

Open `codemagic.yaml`, find this line:
```yaml
APP_STORE_APPLE_ID: "REPLACE_WITH_NUMERIC_APPLE_ID"
```
Replace the placeholder with the number, commit:
```bash
git add codemagic.yaml
git commit -m "ci: real APP_STORE_APPLE_ID for App Store Connect record"
```

---

### Step 4 — Apple Developer team setup (5 min, browser)

If you haven't already in Xcode-land, register your Team ID:

1. https://developer.apple.com/account → membership → copy your **Team ID**
   (10-character alphanumeric like `7XYZ123ABC`).
2. From Xcode you'd configure this per-project; we'll let Codemagic
   handle signing automatically (see Step 5).

---

### Step 5 — Codemagic integration (15 min, browser)

This is the only step that absolutely requires the Codemagic web UI.

1. Sign in to https://codemagic.io with GitHub (same account that owns
   `vittoriopalpati811-ai/marginalia`).
2. **Apps** → find Marginalia → connect.
3. **Teams** → **Personal Account** → **Integrations** → **App Store
   Connect**:
   - Issuer ID: from https://appstoreconnect.apple.com/access/api
   - Key ID: from the same page
   - .p8 file: download once from there
   - Name the integration anything (e.g. `marginalia-asc`).
4. **Code signing identities**:
   - Apple Developer Portal integration: same flow with the .p8 key
   - On first build, Codemagic auto-creates a distribution
     certificate + provisioning profile for `io.marginalia.app`.
5. **App settings** → **Workflow settings** → make sure
   `codemagic.yaml` is selected as the build config.

---

### Step 6 — First build (Codemagic) (~25 min, automatic)

```bash
git push origin master
```

Codemagic detects the push, runs `codemagic.yaml`. Watch in the web UI:
- `Set up Flutter` → `pub get` → `gen-l10n` → `build_runner` → `test`
  should all pass (CI has been green on master for the web build).
- `Install CocoaPods` runs `pod install` in `ios/`.
- `Fetch signing files` auto-creates the cert+profile.
- `Build IPA` produces `build/ios/ipa/Runner.ipa`.
- `publishing` uploads to App Store Connect → TestFlight.

When the build succeeds, App Store Connect emails you saying the build
is processing. **Processing takes 10-30 min on Apple's side** — you'll
get a second email when it's ready to install on devices.

---

### Step 7 — Install on your iPhone (5 min, phone)

1. Install **TestFlight** from the App Store (free Apple app).
2. Open TestFlight → **Redeem** or follow the email link Apple sent.
3. Marginalia appears in TestFlight as a beta app — **Install**.
4. Open and use. Bugs you find go straight back to the founder's email.

---

## Subsequent releases (after the first one ships)

Once the above is all set up, the daily release loop is:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.0+2`).
2. `git push origin master`.
3. ~25 min later, the new build is in TestFlight.

That's it.

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
  signed URLs + migrating existing `image_url` values in the
  `messages` table. Not blocking for TestFlight internal because the
  beta tester (you) is the only person using it.
- **App Store metadata** (screenshots, description, keywords, support
  URL, marketing URL, privacy policy URL, age rating). Required for
  App Store submission, NOT for TestFlight internal.

---

## Troubleshooting

- **`flutter create` complains about an existing project**: that's
  fine, it's idempotent — it adds iOS without touching the Dart code.
- **Codemagic build fails at `pod install`**: usually means a Flutter
  plugin has a misconfigured iOS subspec. Read the error, the fix is
  almost always either bumping the plugin version or running
  `pod repo update` (Codemagic does this automatically on retry).
- **Codemagic build fails at signing**: probably the
  `app-store-connect fetch-signing-files` step needs the bundle ID
  registered in Apple Developer Portal first. Codemagic does this
  automatically with `--create`, but if it fails, register the bundle
  ID manually at https://developer.apple.com/account → Certificates,
  Identifiers & Profiles → Identifiers → +.
- **TestFlight build "Missing Compliance"**: this is Apple's export
  compliance question. Answer "no" to all cryptography questions
  (Marginalia uses only Apple's stock TLS for HTTPS, which is exempt).
