// ─── DailyPhraseCache — Web stub ──────────────────────────────────────────────
//
// No persistent daily-phrase cache on web: there is no app-documents directory,
// and the rollout target is iOS. `read` always misses (so the provider computes
// a fresh pick) and `write` is a no-op. The 3-hour in-memory cache still keeps
// the phrase stable within a single web session.

class DailyPhraseCache {
  static Future<int?> read(String bucketKey) async => null;

  static Future<void> write(String bucketKey, int highlightId) async {}
}
