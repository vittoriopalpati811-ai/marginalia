import 'package:isar/isar.dart';

part 'review_state_native.g.dart';

/// Per-user streak + daily-progress state for the "Ripasso" recall ritual.
///
/// A tiny singleton (one row per [userId]) so the deck never has to scan every
/// highlight to know the streak. Stored LOCALLY in Isar (offline-first,
/// authoritative); after a finished session it is best-effort mirrored to
/// `profiles.review_streak` so the streak can become social later, but the
/// local copy is always the source of truth.
@collection
class ReviewState {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String userId;

  /// Consecutive days the user has completed at least one review.
  int currentStreak = 0;

  /// All-time longest [currentStreak].
  int bestStreak = 0;

  /// Local date (midnight) of the last completed review session. Used to decide
  /// whether the streak continues, resets, or is already counted for today.
  DateTime? lastReviewedOn;

  /// Cards graded today — resets across the day boundary via [reviewedTodayDate].
  int reviewedTodayCount = 0;

  /// Local date the [reviewedTodayCount] belongs to, so it auto-resets at
  /// midnight without a background task.
  DateTime? reviewedTodayDate;
}
