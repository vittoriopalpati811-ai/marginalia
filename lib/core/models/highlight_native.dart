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
}
