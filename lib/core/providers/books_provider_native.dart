import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/book_native.dart';
import '../models/highlight_native.dart';
import 'isar_provider_native.dart';
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

// ─── Book cover editing ──────────────────────────────────────────────────────
//
// Updates a book's coverUrl (a custom upload or a Kindle-scraped cover, or null
// to clear). Writes through Isar — so booksProvider (a watch stream) and the
// detail card update reactively — then best-effort mirrors cover_url to Supabase.
class BookCoverController {
  BookCoverController(this._ref);
  final Ref _ref;

  Future<void> setCover(Id bookId, String? coverUrl) async {
    final isar = _ref.read(isarProvider);
    Book? book;
    await isar.writeTxn(() async {
      final fresh = await isar.books.get(bookId);
      if (fresh == null) return;
      fresh.coverUrl = coverUrl;
      await isar.books.put(fresh);
      book = fresh;
    });
    _ref.invalidate(bookByIdProvider(bookId));
    final b = book;
    if (b != null) {
      try {
        await _ref
            .read(supabaseServiceProvider)
            .setBookCoverUrl(b.supabaseId, coverUrl);
      } catch (_) {
        // best-effort cloud sync; the local cover is already saved
      }
    }
  }
}

final bookCoverControllerProvider =
    Provider<BookCoverController>((ref) => BookCoverController(ref));

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
