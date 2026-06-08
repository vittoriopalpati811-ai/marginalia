/// Plain web stub mirroring [DailyActivity] in daily_activity_native.dart so the
/// shared review/profile UI compiles on the Chrome dev target. The activity log
/// is native-gated (Isar); on web it is simply never persisted.
class DailyActivity {
  int id = 0;
  DateTime day = DateTime.now();
  int reviewedCount = 0;
  bool reviewedComplete = false;
  String userId = '';
}
