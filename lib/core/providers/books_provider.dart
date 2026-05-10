import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/book.dart';
import '../models/highlight.dart';
import 'isar_provider.dart';
import 'auth_provider.dart';

// Live stream of all books for the current user, ordered by title
final booksProvider = StreamProvider.autoDispose<List<Book>>(
  (ref) {
    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return Stream.value([]);

    return isar.books
        .filter()
        .userIdEqualTo(userId)
        .sortByTitle()
        .watch(fireImmediately: true);
  },
);

// Single book by local Isar ID
final bookByIdProvider = FutureProvider.autoDispose.family<Book?, Id>(
  (ref, id) => ref.watch(isarProvider).books.get(id),
);

// Highlights for a given book ID, ordered by location
final highlightsByBookProvider = StreamProvider.autoDispose.family<List<Highlight>, Id>(
  (ref, bookId) {
    final isar = ref.watch(isarProvider);
    return isar.highlights
        .filter()
        .book((q) => q.idEqualTo(bookId))
        .sortByAddedAt()
        .watch(fireImmediately: true);
  },
);

// Favorite highlights for the current user
final favoriteHighlightsProvider = StreamProvider.autoDispose<List<Highlight>>(
  (ref) {
    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return Stream.value([]);

    return isar.highlights
        .filter()
        .userIdEqualTo(userId)
        .isFavoriteEqualTo(true)
        .sortByAddedAtDesc()
        .watch(fireImmediately: true);
  },
);

// Random highlight for the "daily" widget / home card
final randomHighlightProvider = FutureProvider.autoDispose<Highlight?>(
  (ref) async {
    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return null;

    final count = await isar.highlights.filter().userIdEqualTo(userId).count();
    if (count == 0) return null;

    final offset = DateTime.now().millisecondsSinceEpoch % count;
    return isar.highlights.filter().userIdEqualTo(userId).offset(offset).findFirst();
  },
);
