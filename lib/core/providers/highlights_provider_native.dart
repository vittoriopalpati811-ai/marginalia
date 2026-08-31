import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../models/highlight_native.dart';
import '../models/book_native.dart';
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

  /// Flips the saved/bookmarked flag and returns the value that is ACTUALLY on
  /// disk afterwards — or null if nothing could be written.
  ///
  /// It returns the persisted value rather than the intended one because this
  /// button spent a release doing nothing: the write was wrapped in a bare
  /// `catch (_) {}`, so whatever went wrong was thrown away and the icon simply
  /// never changed. A storage error still must not crash the app, but it must
  /// not be invisible either — the caller surfaces it, and the value handed
  /// back is re-read from Isar so the UI can never claim a save that did not
  /// happen.
  Future<bool?> toggleFavorite(Id highlightId) async {
    final isar = ref.read(isarProvider);
    String? supabaseId;
    bool? persisted;
    try {
      // SYNC api inside the transaction, and saveLinks:FALSE — this is the
      // whole bug. The async `put()` has no saveLinks flag, so it ALWAYS writes
      // the object's links back, and saving a link opens its own transaction:
      // "IsarError: Cannot perform this operation from within an active
      // transaction. Isar does not support nesting transactions." The highlight
      // detail screen loads `book` before showing the row, so by the time the
      // reader tapped the bookmark the link was attached and every single
      // toggle threw — silently, because the old code swallowed it. Nothing
      // here touches links, so there is nothing to save.
      isar.writeTxnSync(() {
        final highlight = isar.highlights.getSync(highlightId);
        if (highlight == null) {
          debugPrint('[favorite] highlight $highlightId non trovato in Isar');
          return;
        }
        highlight.isFavorite = !highlight.isFavorite;
        isar.highlights.putSync(highlight, saveLinks: false);
        supabaseId = highlight.supabaseId;
      });
      // Read back OUTSIDE the transaction: this is the value the rest of the
      // app will see, so it is the only one worth reporting.
      persisted = (await isar.highlights.get(highlightId))?.isFavorite;
      debugPrint('[favorite] $highlightId -> $persisted');
    } catch (e, st) {
      debugPrint('[favorite] scrittura fallita per $highlightId: $e\n$st');
      return null;
    }
    // Refresh the providers the UI watches so the bookmark/saved state flips
    // immediately (the web variant does the same).
    ref.invalidate(highlightByIdProvider(highlightId));
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(favoriteHighlightsProvider);
    // Best-effort remote mirror so "saved" survives a reinstall. Never crash
    // the UI if it fails offline — the local row is the source of truth.
    final id = supabaseId;
    final value = persisted;
    if (id != null && id.isNotEmpty && value != null) {
      try {
        await ref.read(supabaseServiceProvider).updateHighlightFavorite(id, value);
      } catch (e) {
        debugPrint('[favorite] mirror remoto non riuscito: $e');
      }
    }
    return persisted;
  }
}

/// The reader's saved highlights, newest first — the backing list of the
/// private "Saved" screen. Scoped to [currentUserProvider] like every other
/// library query, so one account never sees another's saves.
final favoriteHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async {
    final isar = ref.watch(isarProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    if (userId == null) return [];
    final saved = await isar.highlights
        .filter()
        .userIdEqualTo(userId)
        .isFavoriteEqualTo(true)
        .findAll();
    saved.sort((a, b) =>
        (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
    await Future.wait(saved.map((h) => h.book.load()));
    return saved;
  },
);

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

// ─── Jam-share sync (native) ──────────────────────────────────────────────────
//
// Native highlights live only in local Isar and are never uploaded to Supabase,
// so [Highlight.supabaseId] is null on device. Sharing a highlight into a Jam
// inserts its id into jam_highlights.highlight_id, which is a uuid FK to
// highlights(id) — so we must first push the BOOK and the HIGHLIGHT to Supabase
// with STABLE UUIDs (mirroring import_service_web's `_stableUuid`), persist
// those uuids back into Isar, and return the highlight uuid for the FK.
//
// Returns the highlight's real Supabase uuid, or null if it can't be resolved
// (not authenticated, missing book/highlight, or the upsert failed).
Future<String?> ensureHighlightSynced(WidgetRef ref, int highlightId) async {
  final service = ref.read(supabaseServiceProvider);
  final userId = service.userId;
  if (!service.isAuthenticated || userId == null) return null;

  final isar = ref.read(isarProvider);
  final highlight = await isar.highlights.get(highlightId);
  if (highlight == null) return null;

  // Already synced (real uuid, not a `local_` placeholder) → return immediately.
  final existing = highlight.supabaseId;
  if (existing != null &&
      existing.isNotEmpty &&
      !existing.startsWith('local_')) {
    return existing;
  }

  await highlight.book.load();
  final book = highlight.book.value;
  if (book == null) return null;

  // Stable UUIDs keyed exactly like import_service_web so they are
  // deterministic/idempotent and match any rows a web import already created.
  final bookUuid = _stableUuid('$userId|${book.title}', book.author);
  final location = highlight.location;
  final hlUuid = _stableUuid(
    bookUuid,
    (location != null && location.isNotEmpty) ? location : highlight.content,
  );

  try {
    await service.upsertRawBook(
      id: bookUuid,
      userId: userId,
      title: book.title,
      author: book.author,
    );
    await service.upsertRawHighlight(
      id: hlUuid,
      userId: userId,
      bookId: bookUuid,
      content: highlight.content,
      location: highlight.location,
      addedAt: highlight.addedAt,
      color: highlight.color,
    );
  } catch (_) {
    return null;
  }

  // Persist the uuids back into Isar so a re-share short-circuits above.
  try {
    await isar.writeTxn(() async {
      final fresh = await isar.highlights.get(highlightId);
      if (fresh != null) {
        fresh.supabaseId = hlUuid;
        await isar.highlights.put(fresh);
      }
      // Promote the book's local placeholder id to the real uuid so future
      // syncs of its other highlights reuse the same remote book row.
      if (book.supabaseId.isEmpty || book.supabaseId.startsWith('local_')) {
        book.supabaseId = bookUuid;
        await isar.books.put(book);
      }
    });
  } catch (_) {
    // Non-critical: the remote rows exist; the local mirror is best-effort.
  }

  return hlUuid;
}

// Stable UUID from two strings — idempotent, formatted as UUID v4 shape for
// Supabase. MIRRORS import_service_web.dart's `_stableUuid` exactly.
String _stableUuid(String a, String b) {
  final bytes = utf8.encode('$a||$b');
  final hash = sha256.convert(bytes).toString();
  return '${hash.substring(0, 8)}-${hash.substring(8, 12)}'
      '-4${hash.substring(13, 16)}-${hash.substring(16, 20)}'
      '-${hash.substring(20, 32)}';
}
