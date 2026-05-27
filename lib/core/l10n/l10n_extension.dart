import 'package:flutter/widgets.dart';
import 'package:marginalia/generated/app_localizations.dart';

// ─── BuildContext.l10n extension ─────────────────────────────────────────────
//
// Usage:  Text(context.l10n.libraryTitle)
//
// If the build fails with "Target of URI doesn't exist":
//   flutter pub get && flutter gen-l10n

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
