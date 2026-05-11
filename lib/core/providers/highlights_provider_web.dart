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

class HighlightFavoriteNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> toggleFavorite(int highlightId) async {}
}

final highlightFavoriteNotifierProvider =
    NotifierProvider<HighlightFavoriteNotifier, void>(HighlightFavoriteNotifier.new);

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

  return h;
}
