import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/highlight_native.dart';
import 'isar_provider_native.dart';
import 'auth_provider.dart';

// Full-text search across highlight content
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async {
    final query = ref.watch(searchQueryProvider).trim();
    if (query.isEmpty) return [];

    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return [];

    // Isar doesn't support full-text search natively — load and filter in memory.
    // For 10K+ highlights this is still fast (<50ms) since content is short strings.
    final lowerQuery = query.toLowerCase();
    final all = await isar.highlights.filter().userIdEqualTo(userId).findAll();

    return all
        .where((h) =>
            h.content.toLowerCase().contains(lowerQuery) ||
            (h.note?.toLowerCase().contains(lowerQuery) ?? false))
        .toList()
      ..sort((a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
  },
);

// Single highlight by Isar ID
final highlightByIdProvider = FutureProvider.autoDispose.family<Highlight?, Id>(
  (ref, id) => ref.watch(isarProvider).highlights.get(id),
);

// Notifier for toggling favorite on a highlight
class HighlightFavoriteNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> toggleFavorite(Id highlightId) async {
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      final highlight = await isar.highlights.get(highlightId);
      if (highlight == null) return;
      highlight.isFavorite = !highlight.isFavorite;
      await isar.highlights.put(highlight);
    });
  }
}

final highlightFavoriteNotifierProvider =
    NotifierProvider<HighlightFavoriteNotifier, void>(HighlightFavoriteNotifier.new);

// All highlights for current user (used by Jam share picker)
final allHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async {
    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return [];
    final all = await isar.highlights.filter().userIdEqualTo(userId).findAll();
    all.sort((a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
    return all;
  },
);
