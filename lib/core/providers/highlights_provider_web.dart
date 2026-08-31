import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/highlight_web.dart';
import 'auth_provider.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<Highlight>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return [];
  final all = await ref.watch(allHighlightsProvider.future);
  final lower = query.toLowerCase();
  return all
      .where((h) =>
          h.content.toLowerCase().contains(lower) ||
          (h.note?.toLowerCase().contains(lower) ?? false))
      .toList();
});

final highlightByIdProvider =
    FutureProvider.autoDispose.family<Highlight?, int>((ref, id) async {
  final all = await ref.watch(allHighlightsProvider.future);
  try {
    return all.firstWhere((h) => h.id == id);
  } catch (_) {
    return null;
  }
});

final allHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>((ref) async {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isAuthenticated) return [];
  try {
    final data = await service.fetchHighlights();
    return highlightsFromSupabase(data);
  } catch (_) {
    return [];
  }
});

// ─── Jam-share sync (web) ─────────────────────────────────────────────────────
//
// On web, highlights are loaded straight from Supabase and already carry a real
// uuid in [Highlight.supabaseId] — there is nothing to upload. This stub exists
// so the conditional export compiles with the same signature the caller uses;
// it just returns the highlight's existing supabaseId.
Future<String?> ensureHighlightSynced(WidgetRef ref, int highlightId) async {
  final all = await ref.read(allHighlightsProvider.future);
  final highlight = all.where((h) => h.id == highlightId).firstOrNull;
  final id = highlight?.supabaseId;
  return (id != null && id.isNotEmpty) ? id : null;
}

class HighlightFavoriteNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Mirrors the native signature: returns the value that was actually stored,
  /// or null when nothing could be written, so the caller can tell the reader
  /// the truth instead of leaving a dead button.
  Future<bool?> toggleFavorite(int highlightId) async {
    final service = ref.read(supabaseServiceProvider);
    final all = await ref.read(allHighlightsProvider.future);
    final highlight = all.where((h) => h.id == highlightId).firstOrNull;
    if (highlight == null || highlight.supabaseId == null) return null;
    final next = !highlight.isFavorite;
    try {
      await service.updateHighlightFavorite(highlight.supabaseId!, next);
      ref.invalidate(allHighlightsProvider);
      ref.invalidate(favoriteHighlightsProvider);
      return next;
    } catch (_) {
      return null;
    }
  }
}

final highlightFavoriteNotifierProvider =
    NotifierProvider<HighlightFavoriteNotifier, void>(HighlightFavoriteNotifier.new);

/// Web twin of the native provider — the reader's saved highlights, newest
/// first. Keeps the conditional export surface identical (see CLAUDE.md §2).
final favoriteHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async {
    final all = await ref.watch(allHighlightsProvider.future);
    final saved = all.where((h) => h.isFavorite).toList()
      ..sort((a, b) =>
          (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
    return saved;
  },
);

// ─── Shared conversion helpers (used by books_provider_web too) ──────────────

final hlUuidToInt = <String, int>{};
final hlIntToUuid = <int, String>{};

List<Highlight> highlightsFromSupabase(List<Map<String, dynamic>> data) {
  final results = <Highlight>[];
  for (var i = 0; i < data.length; i++) {
    results.add(_highlightFromMap(data[i], i + 1));
  }
  return results;
}

Highlight _highlightFromMap(Map<String, dynamic> m, int intId) {
  final uuid = m['id'] as String? ?? '';
  hlUuidToInt[uuid] = intId;
  hlIntToUuid[intId] = uuid;

  final h = Highlight()
    ..id = intId
    ..supabaseId = uuid
    ..userId = m['user_id'] as String? ?? ''
    ..content = m['content'] as String? ?? ''
    ..note = m['note'] as String?
    ..location = m['location'] as String?
    ..color = m['color'] as String?
    ..isFavorite = m['is_favorite'] as bool? ?? false;

  final addedAtStr = m['added_at'] as String?;
  if (addedAtStr != null) h.addedAt = DateTime.tryParse(addedAtStr);

  // Book info from Supabase join: select('*, books(title, author)')
  final bookMap = m['books'] as Map<String, dynamic>?;
  if (bookMap != null) {
    h.bookTitle = bookMap['title'] as String?;
    h.bookAuthor = bookMap['author'] as String?;
  }

  return h;
}
