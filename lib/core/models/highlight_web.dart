class Highlight {
  int id = 0;
  String? supabaseId;
  String content = '';
  String? note;
  String? location;
  DateTime? addedAt;
  String? color;
  bool isFavorite = false;
  String userId = '';

  // ── Spaced-repetition (SM-2) schedule — mirrors highlight_native.dart so
  // shared review UI compiles on web. The review loop itself is native-gated;
  // these fields exist purely for type compatibility on the Chrome dev target.
  double? reviewEase;
  int? reviewIntervalDays;
  int? reviewReps;
  DateTime? reviewDueAt;

  // Populated from Supabase join so HighlightDetailScreen can display book
  // info without a secondary lookup.
  int bookId = 0;
  String? bookTitle;
  String? bookAuthor;
}
