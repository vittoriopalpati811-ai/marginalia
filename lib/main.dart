import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry/sentry.dart';

import 'core/bootstrap_error_app.dart';
import 'core/services/widget_service.dart';
import 'core/storage/app_startup.dart';

const _supabaseUrl = 'https://ibucvloawkfwobaelwbr.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc';

// Sentry crash/error reporting DSN. Injected at BUILD time via
// --dart-define=SENTRY_DSN=... and NEVER committed to this (public) repo. The
// empty default means Sentry is simply disabled for any build that doesn't pass
// the define (e.g. local dev). CI reads it from the SENTRY_DSN GitHub secret.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

Future<void> main() async {
  // FIRST Dart statement to execute — a CI smoke-test probe (see codemagic.yaml).
  // Uses raw print (NOT debugPrint) so the line is never throttled or buffered
  // away before the simulator boot test can grep the console for it. If this
  // exact marker appears, Dart main() ran, which PROVES the Flutter engine
  // started — the very thing the missing UIMainStoryboardFile key used to prevent
  // (no main interface → no FlutterViewController → engine never started → black
  // screen, no crash, no Dart). Harmless in production: one log line at launch.
  // ignore: avoid_print
  print('### SCRIPTA-BOOT-OK ###');

  // Sentry owns the error-capturing zone when a DSN is configured; otherwise we
  // skip it entirely — zero overhead, behaviour identical to before.
  if (_sentryDsn.isEmpty) {
    _bootstrap();
    return;
  }
  await Sentry.init(
    (options) {
      options.dsn = _sentryDsn;
      options.tracesSampleRate = 0.2;
      options.environment = kReleaseMode ? 'production' : 'debug';
    },
    appRunner: _bootstrap,
  );
}

// Guard the WHOLE bootstrap. A black screen on launch means runApp() never ran —
// an initializer threw OR HUNG before any UI was built. runApp() is the FIRST
// thing that happens: a visible cream splash paints immediately, then every
// fallible/slow initializer runs INSIDE that widget, after the first frame, each
// bounded by a timeout. If the Flutter engine can draw at all, the user sees
// cream — never black. Fatal errors are also forwarded to Sentry when enabled.
void _bootstrap() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework errors (keep the default red-box) so anything during the
    // first frames is logged rather than swallowed — and report it to Sentry.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
      if (_sentryDsn.isNotEmpty) {
        Sentry.captureException(details.exception, stackTrace: details.stack);
      }
    };

    _applySystemChrome();

    runApp(const _StartupGate());
  }, (error, stack) {
    debugPrint('[bootstrap] FATAL (zone): $error\n$stack');
    if (_sentryDsn.isNotEmpty) {
      Sentry.captureException(error, stackTrace: stack);
    }
    runApp(BootstrapErrorApp(
      error: error,
      stackTrace: stack,
      onRetry: () => runApp(const _StartupGate()),
    ));
  });
}

/// Status-bar / nav-bar styling. Fire-and-forget on purpose: these return
/// Futures, but the first frame must never block on a platform channel.
void _applySystemChrome() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light, // iOS
    statusBarIconBrightness: Brightness.dark, // Android
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
}

/// Paints a visible splash IMMEDIATELY, then performs startup off the first
/// frame. Optional subsystems are each bounded by a timeout and are never
/// fatal; the required step (open Isar + read persisted state) hands off to the
/// real app via launchApp(). On a fatal error it shows the readable
/// BootstrapErrorApp instead of a black screen.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  String _status = 'Avvio…';
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      // ── Optional subsystems — offline-first, bounded, never fatal ──────────
      // A hang in any of these used to freeze startup forever; each is now
      // capped so we always fall through to opening the app.
      await _optional(
        'Supabase',
        'Connessione al server…',
        const Duration(seconds: 8),
        () async {
          await Supabase.initialize(
            url: _supabaseUrl,
            anonKey: _supabaseAnonKey,
          );
        },
      );
      await _optional(
        'HomeWidget',
        'Preparazione…',
        const Duration(seconds: 5),
        WidgetService.init,
      );

      // ── Required: open the local DB, read persisted state, runApp(real) ────
      if (mounted) setState(() => _status = 'Apertura libreria…');
      await launchApp(); // replaces this gate with the real app on success
    } catch (error, stack) {
      debugPrint('[bootstrap] FATAL (gate): $error\n$stack');
      if (mounted) {
        setState(() {
          _error = error;
          _stack = stack;
        });
      }
    }
  }

  /// Runs an optional initializer bounded by [limit]; logs and swallows any
  /// failure (including a timeout) so it can never block the UI from launching.
  Future<void> _optional(
    String label,
    String status,
    Duration limit,
    Future<void> Function() init,
  ) async {
    if (mounted) setState(() => _status = status);
    try {
      await init().timeout(limit);
    } catch (error) {
      debugPrint('[bootstrap] $label init skipped (non-fatal): $error');
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _stack = null;
      _status = 'Avvio…';
    });
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return BootstrapErrorApp(
        error: _error!,
        stackTrace: _stack,
        onRetry: _retry,
      );
    }
    return _SplashScreen(status: _status);
  }
}

/// Dependency-light splash (Material + system fonts only) so it can ALWAYS
/// paint, even if a higher-level subsystem — the app theme, google_fonts, Isar
/// — is the very thing that failed.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.status});

  final String status;

  static const _cream = Color(0xFFFAFAF8);
  static const _inkMuted = Color(0xFF6B6B6B);
  static const _accent = Color(0xFF4A7A35); // matcha green

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scripta',
      home: Scaffold(
        backgroundColor: _cream,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'SCRIPTA',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 15,
                    letterSpacing: 4,
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 30),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_accent),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  status,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 13.5,
                    color: _inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
