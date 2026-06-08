import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── localeProvider ───────────────────────────────────────────────────────────
//
// Drives the `locale:` parameter of both MaterialApp instances in app.dart.
// Initialized at startup via ProviderScope.overrides in app_startup_native.dart.
// Updated at runtime when the user picks a language in the onboarding screen.
//
// The default is English-predominant: on any non-overridden path (e.g. web) it
// resolves to English unless the device's primary language is Italian. On
// native, the startup override replaces this with the persisted/device choice.
// NOTE: the helper is inlined (dart:ui only, web-safe) rather than calling
// LocaleService, which imports dart:io and would break the web compile graph.

Locale _deviceDefaultLocale() {
  try {
    if (PlatformDispatcher.instance.locale.languageCode == 'it') {
      return const Locale('it');
    }
  } catch (_) {}
  return const Locale('en');
}

final localeProvider =
    StateProvider<Locale>((ref) => _deviceDefaultLocale());
