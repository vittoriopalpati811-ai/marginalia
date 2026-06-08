// ─── RecsCache — Web stub ─────────────────────────────────────────────────────
//
// No persistent recommendation cache on web: there is no app-documents
// directory, and the US rollout target is iOS. `read` always misses (so the
// provider falls through to the live AI call) and `write` is a no-op.

class RecsCache {
  static Future<List<Map<String, dynamic>>?> read(String signature) async =>
      null;

  static Future<void> write(
      String signature, List<Map<String, dynamic>> recs) async {}

  /// No-op on web (no persistent cache to clear).
  static Future<void> clear() async {}

  /// No-op on web (no persistent cache; the provider always fetches live).
  static Future<bool> isStaleForToday() async => false;
}
