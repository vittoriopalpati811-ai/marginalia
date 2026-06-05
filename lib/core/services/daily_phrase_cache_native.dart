import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// ─── DailyPhraseCache — Native (iOS / Android / Windows) ──────────────────────
//
// Persists the daily-highlight pick for the current 3-hour bucket as JSON in a
// tiny file in the app documents directory:
//   { "bucketKey": "2026-6-5-1", "highlightId": 123 }
//
// `read` returns the stored highlightId ONLY while the saved bucketKey still
// matches the requested (current) one — so the phrase stays identical across
// cold starts within the bucket, and naturally becomes a miss when the bucket
// rolls over. All I/O is guarded so a read/write failure can never break the
// phrase (the provider falls back to recomputing).

class DailyPhraseCache {
  static const _file = '.marginalia_daily_phrase_cache';

  static Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  /// The persisted highlightId for [bucketKey], or null on any miss (different
  /// bucket, missing/corrupt file, I/O error).
  static Future<int?> read(String bucketKey) async {
    try {
      final f = await _path();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (data['bucketKey'] != bucketKey) return null;
      final id = data['highlightId'];
      return id is int ? id : int.tryParse(id?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Persists the pick {[bucketKey], [highlightId]} for the current bucket so
  /// subsequent cold starts within the bucket reuse the exact same highlight.
  static Future<void> write(String bucketKey, int highlightId) async {
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode({
        'bucketKey': bucketKey,
        'highlightId': highlightId,
      }));
    } catch (_) {}
  }
}
