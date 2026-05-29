import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/bootstrap_error_app.dart';
import 'core/services/widget_service.dart';
import 'core/services/subscription_service.dart';
import 'core/storage/app_startup.dart';

const _supabaseUrl = 'https://ibucvloawkfwobaelwbr.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc';

void main() {
  // Run the WHOLE bootstrap inside a guarded zone.
  //
  // A black screen on launch means runApp() never ran — i.e. an initializer
  // threw before any UI was built. The previous main() awaited Supabase, Isar
  // (via launchApp) and the home-widget bridge with NO error handling, so a
  // single failure on a real device (most likely Isar.open failing to load its
  // native library on iOS) aborted startup and left the user staring at black,
  // with zero diagnostics because release builds have no console.
  //
  // Now any fatal error renders a visible, screenshot-able error screen
  // instead, and the optional subsystems below are individually guarded so
  // they can never take the whole app down.
  runZonedGuarded(_bootstrap, (error, stack) {
    debugPrint('[bootstrap] FATAL: $error\n$stack');
    runApp(BootstrapErrorApp(
      error: error,
      stackTrace: stack,
      onRetry: _bootstrap,
    ));
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface framework errors (and keep the default red-box behavior) so any
  // error during the first frames is logged rather than swallowed.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // Always show the status bar; never let individual routes hide it.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Default status-bar style: dark icons on cream bg (light theme).
  // Screens with dark headers override this via AppBar.systemOverlayStyle.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light, // iOS
    statusBarIconBrightness: Brightness.dark, // Android
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // ── Optional subsystems — never fatal ───────────────────────────────────────
  // The app is offline-first (see CLAUDE.md): the backend, the home-screen
  // widget bridge and the (stubbed) subscription layer are all optional. A
  // failure in any of them must NOT prevent the UI from launching, so each runs
  // in isolation and only logs on failure.
  await _tryInit('Supabase', () async {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  });
  await _tryInit('Subscriptions', SubscriptionService.configure);
  await _tryInit('HomeWidget', WidgetService.init);

  // ── Required: open the local DB and start the app ───────────────────────────
  // launchApp() opens Isar (native) / reads persisted state (web) and calls
  // runApp(). If it throws, the zone guard above shows the error screen with
  // the real exception text.
  await launchApp();
}

/// Runs an optional initializer, swallowing (but logging) any failure so it can
/// never prevent the UI from launching.
Future<void> _tryInit(String label, Future<void> Function() init) async {
  try {
    await init();
  } catch (error, stack) {
    debugPrint('[bootstrap] $label init failed (non-fatal): $error\n$stack');
  }
}
