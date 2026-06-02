// ─── Recs Cache — platform barrel ─────────────────────────────────────────────
//
// Persistent DAILY cache for the AI book recommendations, so they are NOT
// regenerated (a slow, Groq-quota-burning call) on every cold start. Keyed by
// (today's date + a library signature): it rolls over at midnight and busts
// automatically when the library changes (an import shifts the counts).
//
// File-backed on iOS/Android/Windows; a no-op on web (the rollout target is
// iOS, and web has no app-documents dir). Works with raw JSON maps to stay
// decoupled from the BookRecommendation model.
//   • native → recs_cache_native.dart  (dart:io file in app docs dir)
//   • web    → recs_cache_web.dart      (always-miss stub)

export 'recs_cache_web.dart' if (dart.library.io) 'recs_cache_native.dart';
