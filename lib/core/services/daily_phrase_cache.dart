// ─── Daily Phrase Cache — platform barrel ─────────────────────────────────────
//
// Persistent cache for the "frase scelta per te" (daily highlight). The chosen
// phrase must stay STABLE for a 3-hour clock-aligned bucket (00/03/06/09/…),
// even across app restarts. Without disk persistence the pick lived only in a
// module-level variable, was lost on cold start, and the (non-deterministic)
// Groq picker ran again → a different phrase every launch.
//
// Stores a tiny JSON { "bucketKey": "...", "highlightId": 123 } so the SAME
// highlight is reused for the whole bucket. Reads hit only while the stored
// bucketKey matches the current one; once the bucket rolls over it's a miss and
// a fresh smart pick is computed (then persisted).
//
// File-backed on iOS/Android/Windows; a no-op on web (the rollout target is
// iOS, and web has no app-documents dir — the phrase simply recomputes there).
//   • native → daily_phrase_cache_native.dart  (dart:io file in app docs dir)
//   • web    → daily_phrase_cache_web.dart      (always-miss / no-op stub)

export 'daily_phrase_cache_web.dart'
    if (dart.library.io) 'daily_phrase_cache_native.dart';
