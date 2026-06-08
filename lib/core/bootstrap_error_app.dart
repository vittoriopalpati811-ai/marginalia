import 'package:flutter/material.dart';

/// A self-contained screen shown when app bootstrap fails.
///
/// CRITICAL: this widget must NOT depend on Isar, Supabase, the app theme,
/// google_fonts, or any subsystem that could itself be the thing that failed.
/// It uses only hard-coded brand colors and system fonts so it can ALWAYS
/// render — turning a silent black screen (which means `runApp` never ran)
/// into a visible, screenshot-able error the user can report.
class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    super.key,
    required this.error,
    this.stackTrace,
    this.onRetry,
  });

  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;

  // Brand colors, hard-coded (never reach for the theme here).
  static const _cream = Color(0xFFFAFAF8);
  static const _ink = Color(0xFF2B2B2B);
  static const _inkMuted = Color(0xFF6B6B6B);
  static const _panel = Color(0xFFF0EEE8);
  static const _accent = Color(0xFF4A7A35); // matcha green

  String get _detail {
    final buffer = StringBuffer(error.toString());
    final trace = stackTrace?.toString().trim();
    if (trace != null && trace.isNotEmpty) {
      final head = trace.split('\n').take(6).join('\n');
      buffer
        ..write('\n\n')
        ..write(head);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scripta',
      home: Scaffold(
        backgroundColor: _cream,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SCRIPTA',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 13,
                        letterSpacing: 3,
                        color: _accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      "Non siamo riusciti\nad aprire l'app",
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 28,
                        height: 1.2,
                        color: _ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "C'è stato un problema durante l'avvio. Tocca "
                      '"Riprova". Se succede di nuovo, fai uno screenshot di '
                      'questa schermata e invialo allo sviluppatore: contiene '
                      "il dettaglio dell'errore.",
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.5,
                        color: _inkMuted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DETTAGLIO TECNICO',
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: _inkMuted,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            _detail,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              height: 1.45,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onRetry,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Riprova',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
