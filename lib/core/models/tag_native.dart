import 'package:isar/isar.dart';

part 'tag_native.g.dart';

@collection
class Tag {
  Id id = Isar.autoIncrement;

  @Index(unique: true, composite: [CompositeIndex('userId')])
  late String name;

  @Index()
  late String userId;
}
