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
  ///
  /// Caller contract: ONLY a successful, non-empty recommendation list is ever
  /// passed here. Transient failures (rate_limit / ai_error / network / …) must
  /// never be written, so a one-off failure can never get stuck on disk and
  /// keep being served on the next cold start.
  static Future<void> write(
      String signature, List<Map<String, dynamic>> recs) async {
    // Defensive: never persist an empty set even if a caller slips up — an
    // empty file would read back as a miss anyway, but this keeps the on-disk
    // invariant ("the file, if present, holds a usable list") explicit.
    if (recs.isEmpty) return;
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode({
        'date': _today(),
        'sig': signature,
        'recs': recs,
      }));
    } catch (_) {}
  }

  /// Deletes the cache file outright. Used by the explicit "Riprova" retry so a
  /// forced re-fetch can never just re-read a previously cached (even good) set
  /// — the user asked for a fresh AI pick. The file only ever holds a single
  /// day/signature, so removing it is sufficient to bust the whole cache.
  static Future<void> clear() async {
    try {
      final f = await _path();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
