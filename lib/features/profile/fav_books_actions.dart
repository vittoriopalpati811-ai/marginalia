// ─── Favourite books ("libri del cuore") actions ─────────────────────────────
//
// Lets any book be toggled into / out of the profile's favourite-books list
// (profiles.favorite_books jsonb, max 6 entries of {title, author}) from the
// library. The heart's state is exposed via [favoriteBooksListProvider] so the
// button fills/outlines reactively, and [toggleFavoriteBook] enforces the 6-book
// cap with a snackbar and persists via SupabaseService.updateFavoriteBooks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_provider.dart';

/// Normalised key for matching two book references regardless of case/spacing —
/// mirrors the per-user cover store key ('title|author', lowercased + trimmed).
String _favBookKey(String title, String author) =>
    '${title.toLowerCase().trim()}|${author.toLowerCase().trim()}';

/// The signed-in user's favourite books ({title, author}), read from the
/// profile. Used to drive the library heart's filled/outline state. Refresh by
/// invalidating after a write.
final favoriteBooksListProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return const [];
  final profile = await svc.fetchProfile();
  final raw = profile?['favorite_books'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => {
            'title': e['title']?.toString() ?? '',
            'author': e['author']?.toString() ?? '',
          })
      .where((m) => (m['title'] ?? '').isNotEmpty)
      .take(6)
      .toList();
});

/// Whether [title]/[author] is currently among the signed-in user's favourites.
/// Returns false while loading or on error so the heart defaults to outline.
final isFavoriteBookProvider = FutureProvider.autoDispose
    .family<bool, ({String title, String author})>((ref, book) async {
  final list = await ref.watch(favoriteBooksListProvider.future);
  final key = _favBookKey(book.title, book.author);
  return list.any((m) => _favBookKey(m['title'] ?? '', m['author'] ?? '') == key);
});

/// Toggles [title]/[author] in the profile's favourite books. Enforces the
/// 6-book cap (snackbar when full), persists the new list, then invalidates the
/// providers so every heart refreshes. Returns true when the book ends up
/// favourited, false when removed (or when the add was blocked by the cap).
Future<bool> toggleFavoriteBook(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String author,
}) async {
  final it = Localizations.localeOf(context).languageCode == 'it';
  final messenger = ScaffoldMessenger.maybeOf(context);
  final svc = ref.read(supabaseServiceProvider);

  // Start from the freshest list we have, falling back to a fetch.
  final current = await ref.read(favoriteBooksListProvider.future);
  final list = current
      .map((m) => {'title': m['title'] ?? '', 'author': m['author'] ?? ''})
      .toList();

  final key = _favBookKey(title, author);
  final existingIndex = list.indexWhere(
      (m) => _favBookKey(m['title'] ?? '', m['author'] ?? '') == key);
  final wasFavorite = existingIndex >= 0;

  if (wasFavorite) {
    list.removeAt(existingIndex);
  } else {
    if (list.length >= 6) {
      messenger?.showSnackBar(SnackBar(
        content: Text(it
            ? 'Puoi avere al massimo 6 libri del cuore'
            : 'You can have up to 6 favourite books'),
      ));
      return false;
    }
    list.add({'title': title.trim(), 'author': author.trim()});
  }

  try {
    await svc.updateFavoriteBooks(list);
  } catch (error) {
    messenger?.showSnackBar(SnackBar(
      content: Text(it
          ? 'Impossibile aggiornare i libri del cuore'
          : "Couldn't update your favourite books"),
    ));
    return wasFavorite; // state unchanged
  }

  ref.invalidate(favoriteBooksListProvider);

  messenger?.showSnackBar(SnackBar(
    content: Text(wasFavorite
        ? (it ? 'Rimosso dai libri del cuore' : 'Removed from favourites')
        : (it ? 'Aggiunto ai libri del cuore' : 'Added to favourites')),
  ));
  return !wasFavorite;
}
