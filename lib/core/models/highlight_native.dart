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

  final book = IsarLink<Book>();
  final tags = IsarLinks<Tag>();

  // ── Compatibility getters (mirrors highlight_web.dart fields) ─────────────
  // book.value is null when the link isn't eagerly loaded — callers must
  // tolerate nulls.  These exist so shared UI code compiles on both platforms.
  String? get bookTitle => book.value?.title;
  String? get bookAuthor => book.value?.author;
  int get bookId => book.value?.id ?? 0;
}
