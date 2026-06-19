import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ─── EventApproachService — Native (iOS / Android / Windows) ──────────────────
//
// Persists how the user tends to feel before a scheduled event to a tiny file in
// the app documents directory, mirroring GenderService. Read back at startup so
// the choice survives across launches.
//
// PRIVACY: stored ONLY on-device — never uploaded. Values are
// 'calm' | 'focused' | 'anxious'.

class EventApproachService {
  static const _file = '.marginalia_event_approach';

  static Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  /// Returns the stored value (trimmed), or null if none is stored.
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

  /// Persists the chosen value for future launches.
  static Future<void> write(String value) async {
    try {
      final f = await _path();
      await f.writeAsString(value);
    } catch (_) {}
  }
}
