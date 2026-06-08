// ─── Activity providers — platform facade ────────────────────────────────────
//
// Exposes per-day activity maps for the profile "Activity" heatmaps:
//   • readingDaysProvider  — Map<date-only, highlightsAddedThatDay>
//   • reviewActivityProvider — Map<date-only, cardsReviewedThatDay>
//
// Native (Isar) and web (Supabase / stub) implementations live in the two files
// below and share this surface, exactly like the highlights/review providers.
export 'activity_provider_web.dart'
    if (dart.library.io) 'activity_provider_native.dart';
