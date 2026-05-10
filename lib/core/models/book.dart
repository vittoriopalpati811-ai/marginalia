import 'package:isar/isar.dart';
import 'highlight.dart';

part 'book.g.dart';

@collection
class Book {
  Id id = Isar.autoIncrement;

  @Index()
  late String supabaseId;

  @Index()
  late String userId;

  late String title;
  late String author;
  String? coverUrl;
  DateTime? lastSyncedAt;
  DateTime? createdAt;

  @Backlink(to: 'book')
  final highlights = IsarLinks<Highlight>();
}
