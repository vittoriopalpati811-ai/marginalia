import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../parser/my_clippings_parser.dart';
import 'supabase_service.dart';

class ImportResult {
  const ImportResult({
    required this.booksAdded,
    required this.highlightsAdded,
    required this.highlightsDeduplicated,
    this.firstError,
    this.highlightsFailed = 0,
    this.booksFailed = 0,
  });

  final int booksAdded;
  final int highlightsAdded;
  final int highlightsDeduplicated;
  final int highlightsFailed;
  final int booksFailed;
  final String? firstError;
}

class ImportService {
  const ImportService(dynamic isar, this._userId,
      {SupabaseService? supabaseService})
      : _supabase = supabaseService;

  final String _userId;
  final SupabaseService? _supabase;

  Future<ImportResult> importClippingsText(String rawText) async {
    final svc = _supabase;
    if (svc == null || !svc.isAuthenticated) {
      return const ImportResult(
        booksAdded: 0,
        highlightsAdded: 0,
        highlightsDeduplicated: 0,
      );
    }

    final clippings = MyClippingsParser().parse(rawText);

    // Fetch existing books once to detect new vs existing.
    final existingBooks = await svc.fetchBooks();
    final bookTitleAuthorToId = <String, String>{};
    for (final b in existingBooks) {
      final key = '${b['title']}|${b['author']}';
      bookTitleAuthorToId[key] = b['id'] as String;
    }

    // Fetch existing highlights once to track deduplication.
    // Key: bookId|location — SAME key used to generate stable UUIDs.
    final existingHighlights = await svc.fetchHighlights();
    final existingHlKeys = <String>{};
    for (final h in existingHighlights) {
      final loc = h['location'] as String?;
      final bookId = h['book_id'] as String?;
      if (loc != null && bookId != null) existingHlKeys.add('$bookId|$loc');
    }

    int booksAdded = 0;
    int booksFailed = 0;
    int highlightsAdded = 0;
    int highlightsFailed = 0;
    int highlightsDeduplicated = 0;
    String? firstError;

    for (final clipping in clippings) {
      if (clipping.type == ClippingType.bookmark) continue;

      // ── Find or create book ──────────────────────────────────────────────
      final bookKey = '${clipping.bookTitle}|${clipping.bookAuthor}';
      String? bookId = bookTitleAuthorToId[bookKey];

      if (bookId == null) {
        // Include userId in the UUID seed so each user gets a unique row
        // per book — prevents RLS conflicts when multiple users share titles.
        bookId = _stableUuid('$_userId|${clipping.bookTitle}', clipping.bookAuthor);
        try {
          await svc.upsertRawBook(
            id: bookId,
            userId: _userId,
            title: clipping.bookTitle,
            author: clipping.bookAuthor,
          );
          bookTitleAuthorToId[bookKey] = bookId;
          booksAdded++;
        } catch (e) {
          booksFailed++;
          firstError ??= 'BOOK "${clipping.bookTitle}": $e';
          continue;
        }
      }

      // ── Upsert highlight ─────────────────────────────────────────────────
      //
      // UUID is keyed on (bookId, location) — NOT on content.
      // This means the UUID is stable across re-imports even if the content
      // encoding was previously corrupted (Ã¨ vs è).  Re-importing always
      // updates the content column via upsert, automatically fixing any
      // data that was stored with broken encoding in a prior import.
      final locationKey = clipping.location ?? '';
      final hlKey = '$bookId|$locationKey';
      final isDuplicate = locationKey.isNotEmpty && existingHlKeys.contains(hlKey);

      // Use location as stable UUID seed; fall back to content only when
      // location is absent (e.g. notes without position metadata).
      final hlId = _stableUuid(
        bookId,
        locationKey.isNotEmpty ? locationKey : clipping.content,
      );

      try {
        await svc.upsertRawHighlight(
          id: hlId,
          userId: _userId,
          bookId: bookId,
          content: clipping.content,
          location: clipping.location,
          addedAt: clipping.addedAt,
          color: clipping.color,
        );
        existingHlKeys.add(hlKey);

        if (isDuplicate) {
          highlightsDeduplicated++;
        } else {
          highlightsAdded++;
        }
      } catch (e) {
        highlightsFailed++;
        firstError ??= 'HIGHLIGHT: $e';
      }
    }

    return ImportResult(
      booksAdded: booksAdded,
      booksFailed: booksFailed,
      highlightsAdded: highlightsAdded,
      highlightsFailed: highlightsFailed,
      highlightsDeduplicated: highlightsDeduplicated,
      firstError: firstError,
    );
  }

  // Stable UUID from two strings — idempotent across re-imports.
  // Formatted as UUID v4 shape for Supabase compatibility.
  String _stableUuid(String a, String b) {
    final bytes = utf8.encode('$a||$b');
    final hash = sha256.convert(bytes).toString();
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}'
        '-4${hash.substring(13, 16)}-${hash.substring(16, 20)}'
        '-${hash.substring(20, 32)}';
  }
}
