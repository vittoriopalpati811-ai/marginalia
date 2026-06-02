import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// ─── RecsCache — Native (iOS / Android / Windows) ─────────────────────────────
//
// Stores the latest successful recommendation set as JSON in a tiny file in the
// app documents directory, stamped with the date and a library signature. Reads
// hit only when BOTH still match today's request, so the AI call is skipped on
// repeat cold starts but re-runs the next day or after an import.

class RecsCache {
  static const _file = '.marginalia_recs_cache';

  static Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// Today's cached recommendation maps for [signature], or null on any miss
  /// (different day, different library signature, missing/corrupt file).
  static Future<List<Map<String, dynamic>>?> read(String signature) async {
    try {
      final f = await _path();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (data['date'] != _today() || data['sig'] != signature) return null;
      final recs = (data['recs'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return recs.isEmpty ? null : recs;
    } catch (_) {
      return null;
    }
  }

  /// Persists [recs] (raw maps) for today under [signature].
  static Future<void> write(
      String signature, List<Map<String, dynamic>> recs) async {
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode({
        'date': _today(),
        'sig': signature,
        'recs': recs,
      }));
    } catch (_) {}
  }
}
