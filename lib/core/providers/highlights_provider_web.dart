import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/highlight_web.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async => [],
);

final highlightByIdProvider = FutureProvider.autoDispose.family<Highlight?, int>(
  (ref, id) async => null,
);

class HighlightFavoriteNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> toggleFavorite(int highlightId) async {}
}

final highlightFavoriteNotifierProvider =
    NotifierProvider<HighlightFavoriteNotifier, void>(HighlightFavoriteNotifier.new);

final allHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async => [],
);
