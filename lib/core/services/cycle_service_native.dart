import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ─── CycleService — Native (iOS / Android / Windows) ──────────────────────────
//
// The cycle used to be read from HealthKit. Apple removed that option for us
// (Guideline 2.5.1, 2026-09-02: no HealthKit without a primary health feature),
// so the reader now TELLS Scripta instead of the phone reading it behind their
// back — which is the better version of the promise anyway: nothing is
// inferred, and the setting is visible and clearable in Settings.
//
// Stored as one line, `yyyy-MM-dd|length`, in a tiny file in the app documents
// directory — exactly like GenderService.
//
// PRIVACY: on-device ONLY. Never uploaded to Supabase or anywhere else. This is
// special-category data; keep it that way.

class CycleService {
  static const _file = '.marginalia_cycle';

  static Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  /// The raw `yyyy-MM-dd|length` line, or null when the reader never set one.
  static Future<String?> read() async {
    try {
      final f = await _path();
      if (await f.exists()) {
        final value = (await f.readAsString()).trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> write(String value) async {
    try {
      await (await _path()).writeAsString(value);
    } catch (_) {}
  }

  /// Forgets the cycle entirely. Used by the "remove" action in Settings.
  static Future<void> clear() async {
    try {
      final f = await _path();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
