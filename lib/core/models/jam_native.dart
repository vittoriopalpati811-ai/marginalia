import 'package:isar/isar.dart';

part 'jam_native.g.dart';

// Local cache of a Supabase Jam record. Full social data (members, shared
// highlights) is always fetched from Supabase realtime — this is just a
// fast-access cache for the navigation / list view.
@collection
class Jam {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String supabaseId;

  late String name;

  @Index(unique: true)
  late String inviteCode;

  late String ownerId;
  DateTime? createdAt;

  // UUIDs of current members (from Supabase, kept in sync)
  List<String> memberIds = [];
}

// Value object used in the social UI (not persisted in Isar — comes from Supabase)
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
