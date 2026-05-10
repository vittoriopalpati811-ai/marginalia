import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../models/tag_native.dart';
import '../models/jam_native.dart';

// Overridden in main.dart with the initialized Isar instance before runApp.
final isarProvider = Provider<Isar>(
  (ref) => throw UnimplementedError('isarProvider must be overridden in ProviderScope'),
);

// Collections — convenience providers
final booksCollectionProvider = Provider<IsarCollection<Book>>(
  (ref) => ref.watch(isarProvider).books,
);

final highlightsCollectionProvider = Provider<IsarCollection<Highlight>>(
  (ref) => ref.watch(isarProvider).highlights,
);

final tagsCollectionProvider = Provider<IsarCollection<Tag>>(
  (ref) => ref.watch(isarProvider).tags,
);

final jamsCollectionProvider = Provider<IsarCollection<Jam>>(
  (ref) => ref.watch(isarProvider).jams,
);
