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

  // Populated from Supabase join so HighlightDetailScreen can display book
  // info without a secondary lookup.
  int bookId = 0;
  String? bookTitle;
  String? bookAuthor;
}
