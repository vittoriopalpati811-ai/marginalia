import 'dart:async';
import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:crypto/crypto.dart';

import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../parser/my_clippings_parser.dart';
import 'supabase_service.dart';

class ImportResult {
  const ImportResult({
    required this.booksAdded,
    required this.highlightsAdded,
    required this.highlightsDeduplicated,
    this.highlightsFailed = 0,
    this.booksFailed = 0,
    this.firstError,
  });

  final int booksAdded;
  final int highlightsAdded;
  final int highlightsDeduplicated;
  final int highlightsFailed;
  final int booksFailed;
  final String? firstError;
}

class ImportService {
  const ImportService(this._isar, this._userId,
      {SupabaseService? supabaseService})
      : _supabase = supabaseService;

  final Isar _isar;
  final String _userId;
  final SupabaseService? _supabase;

  Future<ImportResult> importClippingsText(String rawText) async {
    final parser = MyClippingsParser();
    final clippings = parser.parse(rawText);

    int booksAdded = 0;
    int highlightsAdded = 0;
    int highlightsDeduplicated = 0;

    await _isar.writeTxn(() async {
      for (final clipping in clippings) {
        if (clipping.type == ClippingType.bookmark) continue;

        // Find or create book
        Book? book = await _isar.books
            .filter()
            .userIdEqualTo(_userId)
            .titleEqualTo(clipping.bookTitle)
            .authorEqualTo(clipping.bookAuthor)
            .findFirst();

        if (book == null) {
          book = Book()
            ..supabaseId = _generateLocalId(clipping.bookTitle, clipping.bookAuthor)
            ..userId = _userId
            ..title = clipping.bookTitle
            ..author = clipping.bookAuthor
            ..createdAt = DateTime.now();
          await _isar.books.put(book);
          booksAdded++;
        }

        // Check if highlight already exists at this location
        final existingHighlight = await _isar.highlights
            .filter()
            .userIdEqualTo(_userId)
            .locationEqualTo(clipping.location)
            .book((q) => q.idEqualTo(book!.id))
            .findFirst();

        if (existingHighlight != null) {
          // Keep longer content on conflict
          if (clipping.content.length > existingHighlight.content.length) {
            existingHighlight.content = clipping.content;
            await _isar.highlights.put(existingHighlight);
          }
          highlightsDeduplicated++;
          continue;
        }

        final highlight = Highlight()
          ..content = clipping.content
          ..note = null
          ..location = clipping.location
          ..addedAt = clipping.addedAt
          ..color = clipping.color
          ..userId = _userId;

        await _isar.highlights.put(highlight);
        highlight.book.value = book;
        await highlight.book.save();

        highlightsAdded++;
      }
    });

    // Mirror the library to the cloud in the background so the highlights
    // survive a reinstall / a sign-in on a new device. Native imports used to
    // be LOCAL-ONLY (the founder lost highlights this way) — this is what makes
    // "Restore from cloud" possible. Fire-and-forget + best-effort so a slow or
    // offline cloud never blocks or fails the fast local import.
    unawaited(_backupToCloudSafe());

    return ImportResult(
      booksAdded: booksAdded,
      highlightsAdded: highlightsAdded,
      highlightsDeduplicated: highlightsDeduplicated,
    );
  }

  Future<void> _backupToCloudSafe() async {
    try {
      await backupToCloud();
    } catch (_) {
      // Best-effort: a cloud failure must never surface as an import failure.
    }
  }

  /// Pushes every local book + highlight to Supabase with stable UUIDs (the same
  /// scheme as the web import, so a later re-import stays idempotent) and writes
  /// the cloud id back into Isar. Idempotent (upsert by id). Returns the number
  /// of highlights synced. Safe to call repeatedly.
  Future<int> backupToCloud() async {
    final svc = _supabase;
    if (svc == null || !svc.isAuthenticated) return 0;

    final books =
        await _isar.books.filter().userIdEqualTo(_userId).findAll();
    final bookIdUpdates = <Book, String>{};
    final hlIdUpdates = <Highlight, String>{};
    int synced = 0;

    for (final book in books) {
      final bookCloudId = _stableUuid('$_userId|${book.title}', book.author);
      try {
        await svc.upsertRawBook(
          id: bookCloudId,
          userId: _userId,
          title: book.title,
          author: book.author,
        );
      } catch (_) {
        continue; // skip this book's highlights if the book upsert failed
      }
      if (book.supabaseId != bookCloudId) bookIdUpdates[book] = bookCloudId;

      final hls = await _isar.highlights
          .filter()
          .userIdEqualTo(_userId)
          .book((q) => q.idEqualTo(book.id))
          .findAll();
      for (final h in hls) {
        final loc = h.location ?? '';
        final hlId =
            _stableUuid(bookCloudId, loc.isNotEmpty ? loc : h.content);
        try {
          await svc.upsertRawHighlight(
            id: hlId,
            userId: _userId,
            bookId: bookCloudId,
            content: h.content,
            location: h.location,
            addedAt: h.addedAt,
            color: h.color,
          );
          if (h.supabaseId != hlId) hlIdUpdates[h] = hlId;
          synced++;
        } catch (_) {
          // Skip a single failed highlight; keep going.
        }
      }
    }

    // Persist all the freshly-assigned cloud ids in a single transaction.
    if (bookIdUpdates.isNotEmpty || hlIdUpdates.isNotEmpty) {
      await _isar.writeTxn(() async {
        for (final e in bookIdUpdates.entries) {
          e.key.supabaseId = e.value;
          e.key.lastSyncedAt = DateTime.now();
          await _isar.books.put(e.key);
        }
        for (final e in hlIdUpdates.entries) {
          e.key.supabaseId = e.value;
          await _isar.highlights.put(e.key);
        }
      });
    }
    return synced;
  }

  /// Pulls the user's books + highlights from Supabase into Isar. Deduplicates
  /// by supabaseId AND by (book, location), so it NEVER creates duplicates even
  /// if some highlights already exist locally (e.g. a partial native import).
  /// Returns the number of highlights added. Safe to run repeatedly.
  Future<int> restoreFromCloud() async {
    final svc = _supabase;
    if (svc == null || !svc.isAuthenticated) return 0;

    final cloudBooks = await svc.fetchBooks();
    final cloudHls = await svc.fetchHighlights();
    int restored = 0;

    await _isar.writeTxn(() async {
      final bookByCloudId = <String, Book>{};
      for (final b in cloudBooks) {
        final cloudId = b['id'] as String?;
        if (cloudId == null) continue;
        final title = b['title'] as String? ?? '';
        final author = b['author'] as String? ?? '';

        Book? local = await _isar.books
            .filter()
            .userIdEqualTo(_userId)
            .supabaseIdEqualTo(cloudId)
            .findFirst();
        local ??= await _isar.books
            .filter()
            .userIdEqualTo(_userId)
            .titleEqualTo(title)
            .authorEqualTo(author)
            .findFirst();
        if (local == null) {
          local = Book()
            ..supabaseId = cloudId
            ..userId = _userId
            ..title = title
            ..author = author
            ..coverUrl = b['cover_url'] as String?
            ..createdAt = DateTime.now();
          await _isar.books.put(local);
        }
        bookByCloudId[cloudId] = local;
      }

      for (final h in cloudHls) {
        final cloudId = h['id'] as String?;
        final bookCloudId = h['book_id'] as String?;
        if (cloudId == null || bookCloudId == null) continue;
        final book = bookByCloudId[bookCloudId];
        if (book == null) continue;

        // Already restored (by cloud id)? skip.
        final bySupaId = await _isar.highlights
            .filter()
            .userIdEqualTo(_userId)
            .supabaseIdEqualTo(cloudId)
            .findFirst();
        if (bySupaId != null) continue;

        // Same (book, location) already local (e.g. a prior native import)?
        // Adopt the cloud id onto it instead of duplicating.
        final loc = h['location'] as String?;
        if (loc != null && loc.isNotEmpty) {
          final byLoc = await _isar.highlights
              .filter()
              .userIdEqualTo(_userId)
              .locationEqualTo(loc)
              .book((q) => q.idEqualTo(book.id))
              .findFirst();
          if (byLoc != null) {
            if (byLoc.supabaseId == null) {
              byLoc.supabaseId = cloudId;
              await _isar.highlights.put(byLoc);
            }
            continue;
          }
        }

        final hl = Highlight()
          ..supabaseId = cloudId
          ..content = h['content'] as String? ?? ''
          ..location = loc
          ..addedAt = DateTime.tryParse(h['added_at'] as String? ?? '')
          ..color = h['color'] as String?
          ..userId = _userId;
        await _isar.highlights.put(hl);
        hl.book.value = book;
        await hl.book.save();
        restored++;
      }
    });
    return restored;
  }

  // Generate a stable local ID (not a Supabase UUID — used before first sync)
  String _generateLocalId(String title, String author) {
    final bytes = utf8.encode('$title|$author');
    return 'local_${sha256.convert(bytes).toString().substring(0, 16)}';
  }

  // Stable UUID from two strings — idempotent across re-imports. Formatted as a
  // UUID v4 shape for Supabase. Mirrors import_service_web._stableUuid.
  String _stableUuid(String a, String b) {
    final bytes = utf8.encode('$a||$b');
    final hash = sha256.convert(bytes).toString();
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}'
        '-4${hash.substring(13, 16)}-${hash.substring(16, 20)}'
        '-${hash.substring(20, 32)}';
  }
}
