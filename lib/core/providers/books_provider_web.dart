import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/book_web.dart';
import '../models/highlight_web.dart';
import 'auth_provider.dart';
import 'highlights_provider_web.dart' show highlightsFromSupabase;

// In-memory registry: Supabase UUID ↔ int ID
final _bookUuidToInt = <String, int>{};
final _bookIntToUuid = <int, String>{};

String? bookUuidForIntId(int id) => _bookIntToUuid[id];

Book _bookFromMap(Map<String, dynamic> m, int intId) {
  final uuid = m['id'] as String? ?? '';
  _bookUuidToInt[uuid] = intId;
  _bookIntToUuid[intId] = uuid;
  return Book()
    ..id = intId
    ..supabaseId = uuid
    ..userId = m['user_id'] as String? ?? ''
    ..title = m['title'] as String? ?? ''
    ..author = m['author'] as String? ?? ''
    ..coverUrl = m['cover_url'] as String?;
}

final booksProvider = StreamProvider.autoDispose<List<Book>>((ref) async* {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isAuthenticated) {
    yield [];
    return;
  }
  try {
    final data = await service.fetchBooks();
    final books = <Book>[];
    for (var i = 0; i < data.length; i++) {
      books.add(_bookFromMap(data[i], i + 1));
    }
    yield books;
  } catch (_) {
    yield [];
  }
});

final bookByIdProvider =
    FutureProvider.autoDispose.family<Book?, int>((ref, id) async {
  final books = await ref.watch(booksProvider.future);
  try {
    return books.firstWhere((b) => b.id == id);
  } catch (_) {
    return null;
  }
});

final highlightsByBookProvider =
    StreamProvider.autoDispose.family<List<Highlight>, int>((ref, bookId) async* {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isAuthenticated) {
    yield [];
    return;
  }
  final bookUuid = bookUuidForIntId(bookId);
  if (bookUuid == null) {
    yield [];
    return;
  }
  try {
    final data = await service.fetchHighlights(bookId: bookUuid);
    yield highlightsFromSupabase(data);
  } catch (_) {
    yield [];
  }
});

final favoriteHighlightsProvider =
    StreamProvider.autoDispose<List<Highlight>>((ref) async* {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isAuthenticated) {
    yield [];
    return;
  }
  try {
    final data = await service.fetchHighlights();
    final favs =
        highlightsFromSupabase(data).where((h) => h.isFavorite).toList();
    yield favs;
  } catch (_) {
    yield [];
  }
});

final randomHighlightProvider =
    FutureProvider.autoDispose<Highlight?>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isAuthenticated) return null;
  try {
    final data = await service.fetchHighlights();
    if (data.isEmpty) return null;
    final highlights = highlightsFromSupabase(data);
    highlights.shuffle();
    return highlights.first;
  } catch (_) {
    return null;
  }
});
