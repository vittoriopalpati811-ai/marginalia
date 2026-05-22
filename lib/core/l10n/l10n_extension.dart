import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// ─── BuildContext.l10n extension ─────────────────────────────────────────────
//
// Usage:
//   Text(context.l10n.libraryTitle)
//
// Requires:
//   1. flutter pub get          (adds flutter_localizations + generate: true)
//   2. flutter gen-l10n         (generates lib/generated/...)
//   3. Uncomment AppLocalizations.delegate in lib/app.dart
//
// Until step 2 is run, this file will fail to compile (AppLocalizations is
// a generated class). Run: flutter gen-l10n

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
