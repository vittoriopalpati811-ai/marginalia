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

    final results = all
        .where((h) =>
            h.content.toLowerCase().contains(lowerQuery) ||
            (h.note?.toLowerCase().contains(lowerQuery) ?? false))
        .toList()
      ..sort((a, b) => (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));

    // Load book links so bookTitle/bookAuthor are available in search cards
    await Future.wait(results.map((h) => h.book.load()));
    return results;
  },
);

// Single highlight by Isar ID — loads the book IsarLink so bookTitle/bookAuthor
// are available in HighlightDetailScreen and ShareCardService.
final highlightByIdProvider = FutureProvider.autoDispose.family<Highlight?, Id>(
  (ref, id) async {
    final h = await ref.watch(isarProvider).highlights.get(id);
    if (h != null) await h.book.load();
    return h;
  },
);

// Notifier for toggling favorite on a highlight
class HighlightFavoriteNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> toggleFavorite(Id highlightId) async {
    final isar = ref.read(isarProvider);
    // Guarded like grade(): a storage error must never crash the UI. The
    // favorites stream stays consistent with whatever actually persisted.
    String? supabaseId;
    bool? newValue;
    try {
      await isar.writeTxn(() async {
        final highlight = await isar.highlights.get(highlightId);
        if (highlight == null) return;
        highlight.isFavorite = !highlight.isFavorite;
        await isar.highlights.put(highlight);
        // Capture what to mirror remotely once the local write succeeds.
        supabaseId = highlight.supabaseId;
        newValue = highlight.isFavorite;
      });
    } catch (_) {
      // swallow — non-critical
    }
    // Best-effort remote sync so "save to favourites" actually persists for the
    // user (and survives a reinstall). Never crash the UI if it fails offline.
    final id = supabaseId;
    final value = newValue;
    if (id != null && id.isNotEmpty && value != null) {
      try {
        await ref.read(supabaseServiceProvider).updateHighlightFavorite(id, value);
      } catch (_) {
        // swallow — non-critical, the local Isar write is the source of truth
      }
    }
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
    // Load book links so bookTitle is available in library strip and share picker
    await Future.wait(all.map((h) => h.book.load()));
    return all;
  },
);
