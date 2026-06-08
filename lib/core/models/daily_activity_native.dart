import 'package:isar/isar.dart';

part 'daily_activity_native.g.dart';

/// One row per local day the user did anything trackable in the recall ritual.
///
/// This is the durable log behind the upcoming profile heatmaps: instead of
/// re-deriving "which days did I review?" from the streak singleton (which only
/// knows the *last* reviewed day), we keep an explicit, queryable history. A row
/// is upserted when a review session completes (see [ReviewSessionController]),
/// incrementing [reviewedCount] and flipping [reviewedComplete]. Stored LOCALLY
/// in Isar (offline-first); nothing here is synced to Supabase in v1.
@collection
class DailyActivity {
  Id id = Isar.autoIncrement;

  /// Local midnight of the day this row covers (date-only). Indexed so the
  /// heatmap can range-scan days and the upsert can find today's row in O(log n).
  @Index()
  late DateTime day;

  /// How many cards were graded on [day]. Accumulates across multiple sessions
  /// in the same day.
  int reviewedCount = 0;

  /// True once at least one full review session was completed on [day] — lets a
  /// heatmap distinguish "opened the deck" from "finished the deck".
  bool reviewedComplete = false;

  @Index()
  late String userId;
}
