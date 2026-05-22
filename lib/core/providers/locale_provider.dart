import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── localeProvider ───────────────────────────────────────────────────────────
//
// Drives the `locale:` parameter of both MaterialApp instances in app.dart.
// Initialized at startup via ProviderScope.overrides in app_startup_native.dart.
// Updated at runtime when the user picks a language in the onboarding screen.

final localeProvider = StateProvider<Locale>((ref) => const Locale('it'));
