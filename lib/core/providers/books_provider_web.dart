import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/book_web.dart';
import '../models/highlight_web.dart';

final booksProvider = StreamProvider.autoDispose<List<Book>>(
  (ref) => Stream.value([]),
);

final bookByIdProvider = FutureProvider.autoDispose.family<Book?, int>(
  (ref, id) async => null,
);

final highlightsByBookProvider = StreamProvider.autoDispose.family<List<Highlight>, int>(
  (ref, bookId) => Stream.value([]),
);

final favoriteHighlightsProvider = StreamProvider.autoDispose<List<Highlight>>(
  (ref) => Stream.value([]),
);

final randomHighlightProvider = FutureProvider.autoDispose<Highlight?>(
  (ref) async => null,
);
