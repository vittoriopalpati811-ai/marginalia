class Jam {
  int id = 0;
  String supabaseId = '';
  String name = '';
  String inviteCode = '';
  String ownerId = '';
  DateTime? createdAt;
  List<String> memberIds = [];
}

class JamHighlight {
  const JamHighlight({
    required this.jamId,
    required this.highlightSupabaseId,
    required this.content,
    required this.bookTitle,
    required this.bookAuthor,
    required this.sharedByUserId,
    required this.sharedAt,
  });

  final String jamId;
  final String highlightSupabaseId;
  final String content;
  final String bookTitle;
  final String bookAuthor;
  final String sharedByUserId;
  final DateTime sharedAt;
}
