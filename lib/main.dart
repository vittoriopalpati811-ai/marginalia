import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// DIAGNOSTIC BUILD — TEMPORARY. This is NOT the real app.
//
// Why this exists: render-first bootstrap (dfd8244) AND Impeller-disabled /
// Skia (1d359b3) both shipped and the TestFlight launch is STILL black. And
// the real app has never been confirmed to paint a single frame on iOS — only
// the web/CanvasKit build is known-good. So stop guessing and bisect.
//
// This strips EVERYTHING to the minimum needed to answer one binary question:
// can the Codemagic-built IPA paint ANY Flutter frame on the device?
//
//   • Vivid magenta screen shows  → engine + build pipeline + native shell all
//     work; the bug is 100% in the Dart app/init code (or the tester was still
//     on an older build). Re-introduce the real app from git next.
//   • Still black                 → native / engine / build-level, independent
//     of all Dart app code (or the new build was never installed).
//
// No runZonedGuarded, no ensureInitialized, no plugins, no Isar, no Supabase,
// no google_fonts — nothing that can hang, throw, or be tree-shaken. The real
// main.dart is recoverable: `git checkout 1d359b3 -- lib/main.dart`.
// ─────────────────────────────────────────────────────────────────────────
void main() {
  runApp(const _DiagApp());
}

class _DiagApp extends StatelessWidget {
  const _DiagApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFD81B60), // vivid magenta — never black/cream
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'MARGINALIA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'DIAGNOSTICA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                  SizedBox(height: 30),
                  Text(
                    'Se vedi questo schermo rosa,\nlo schermo e il motore grafico\nfunzionano.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
