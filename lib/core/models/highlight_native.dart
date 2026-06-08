import 'package:isar/isar.dart';
import 'book_native.dart';
import 'tag_native.dart';

part 'highlight_native.g.dart';

@collection
class Highlight {
  Id id = Isar.autoIncrement;

  String? supabaseId;

  late String content;
  String? note;
  String? location;
  DateTime? addedAt;

  // 'yellow' | 'blue' | 'pink' | 'orange' | null
  String? color;

  bool isFavorite = false;

  @Index()
  late String userId;

  // ── Spaced-repetition (SM-2) schedule — LOCAL, offline-first ───────────────
  //
  // These power the daily "Ripasso" recall ritual. All scheduling math lives in
  // lib/core/review/sm2.dart and is computed entirely on-device; nothing here is
  // synced to Supabase in v1. NULLABLE so existing records migrate for free:
  // a null [reviewDueAt] means "never scheduled" → eligible as a brand-new card
  // (treated as due now). See [scheduleSm2] for how these advance on each grade.
  double? reviewEase;        // SM-2 ease factor (default 2.5, floor 1.3)
  int? reviewIntervalDays;   // current interval in whole days
  int? reviewReps;           // consecutive successful (q>=3) recalls

  @Index()
  DateTime? reviewDueAt;     // null = never scheduled (eligible as "new")

  final book = IsarLink<Book>();
  final tags = IsarLinks<Tag>();

  // ── Compatibility getters (mirrors highlight_web.dart fields) ─────────────
  // book.value is null when the link isn't eagerly loaded — callers must
  // tolerate nulls.  These exist so shared UI code compiles on both platforms.
  String? get bookTitle => book.value?.title;
  String? get bookAuthor => book.value?.author;
  int get bookId => book.value?.id ?? 0;
}
