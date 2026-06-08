/// Plain web stub mirroring [ReviewState] in review_state_native.dart so shared
/// review UI compiles on the Chrome dev target. The review loop is native-gated;
/// on web the streak is simply never persisted (no Isar).
class ReviewState {
  int id = 0;
  String userId = '';
  int currentStreak = 0;
  int bestStreak = 0;
  DateTime? lastReviewedOn;
  int reviewedTodayCount = 0;
  DateTime? reviewedTodayDate;
}
