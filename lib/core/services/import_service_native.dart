import 'dart:async';
import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:crypto/crypto.dart';

import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../parser/my_clippings_parser.dart';
import 'import_match.dart';
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

  Future<ImportResult> importClippingsText(String rawText,
      {bool skipCloudBackup = false}) async {
    final parser = MyClippingsParser();
    final clippings = parser.parse(rawText);

    int booksAdded = 0;
    int highlightsAdded = 0;
    int highlightsDeduplicated = 0;

    await _isar.writeTxn(() async {
      // Load the library ONCE and match in memory.
      //
      // Two reasons. The small one: this used to run two Isar queries per
      // clipping, so a 2000-line clippings file meant 4000 queries. The load
      // -bearing one: matching now has to be NORMALISED (see import_match.dart),
      // and "find me the book whose normalised key is X" is not something the
      // exact-equality query could ever ask.
      final books =
          await _isar.books.filter().userIdEqualTo(_userId).findAll();

      // Books already in the library that are the same book written two ways
      // are merged as we go, rather than left as two spines forever.
      final byKey = <String, Book>{};
      for (final b in books) {
        final key = bookMatchKey(b.title, b.author);
        final kept = byKey[key];
        if (kept == null) {
          byKey[key] = b;
        } else {
          await _mergeBookInto(kept, b);
        }
      }

      // Highlights of each matched book, kept in memory for the same reason.
      final marksOf = <int, List<Highlight>>{};
      Future<List<Highlight>> marksFor(Book book) async =>
          marksOf[book.id] ??= await _isar.highlights
              .filter()
              .userIdEqualTo(_userId)
              .book((q) => q.idEqualTo(book.id))
              .findAll();

      for (final clipping in clippings) {
        if (clipping.type == ClippingType.bookmark) continue;

        final key = bookMatchKey(clipping.bookTitle, clipping.bookAuthor);
        var book = byKey[key];

        if (book == null) {
          book = Book()
            ..supabaseId = _generateLocalId(clipping.bookTitle, clipping.bookAuthor)
            ..userId = _userId
            ..title = clipping.bookTitle
            ..author = clipping.bookAuthor
            ..createdAt = DateTime.now();
          await _isar.books.put(book);
          byKey[key] = book;
          marksOf[book.id] = <Highlight>[];
          booksAdded++;
        }

        final existing = await marksFor(book);
        Highlight? twin;
        for (final h in existing) {
          if (isSameHighlight(
            locationA: h.location,
            contentA: h.content,
            locationB: clipping.location,
            contentB: clipping.content,
          )) {
            twin = h;
            break;
          }
        }

        if (twin != null) {
          // Kindle re-issues a highlight with more text around it; keep the
          // fuller version, and take the location that came with it.
          if (clipping.content.length > twin.content.length) {
            twin.content = clipping.content;
            twin.location = clipping.location ?? twin.location;
            await _isar.highlights.put(twin);
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
        existing.add(highlight);

        highlightsAdded++;
      }
    });

    // Mirror the library to the cloud in the background so the highlights
    // survive a reinstall / a sign-in on a new device. Native imports used to
    // be LOCAL-ONLY (the founder lost highlights this way) — this is what makes
    // "Restore from cloud" possible. Fire-and-forget + best-effort so a slow or
    // offline cloud never blocks or fails the fast local import. Skipped for
    // the DEMO import — sample data must never pollute the user's real cloud
    // library (and then come back via Restore from cloud).
    if (!skipCloudBackup) unawaited(_backupToCloudSafe());

    return ImportResult(
      booksAdded: booksAdded,
      highlightsAdded: highlightsAdded,
      highlightsDeduplicated: highlightsDeduplicated,
    );
  }

  /// Folds [loser] into [keeper]: every highlight moves across unless [keeper]
  /// already has it, then the empty book row goes.
  ///
  /// Called during an import, inside its transaction. Nothing is thrown away —
  /// a highlight is only dropped when the SAME highlight is already on the book
  /// it is moving to.
  Future<void> _mergeBookInto(Book keeper, Book loser) async {
    final kept = await _isar.highlights
        .filter()
        .userIdEqualTo(_userId)
        .book((q) => q.idEqualTo(keeper.id))
        .findAll();
    final moving = await _isar.highlights
        .filter()
        .userIdEqualTo(_userId)
        .book((q) => q.idEqualTo(loser.id))
        .findAll();

    for (final h in moving) {
      final duplicate = kept.any((k) => isSameHighlight(
            locationA: k.location,
            contentA: k.content,
            locationB: h.location,
            contentB: h.content,
          ));
      if (duplicate) {
        await _isar.highlights.delete(h.id);
        continue;
      }
      h.book.value = keeper;
      await h.book.save();
      kept.add(h);
    }
    await _isar.books.delete(loser.id);
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
    // Two highlights of the SAME quote in the same book would collide on the
    // 2nd upsert; skip the duplicate client-side so the upsert never throws
    // (the content is already covered). The server backs this up with a UNIQUE
    // index on (user_id, content_hash) — added in migration 080, because this
    // comment used to CLAIM the server enforced it and the constraint simply
    // was not there.
    final seenHashes = <String>{};
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
        final contentHash = sha256
            .convert(utf8.encode('$bookCloudId ${h.content}'))
            .toString();
        if (!seenHashes.add(contentHash)) {
          synced++; // same quote already covered by another highlight
          continue;
        }
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
      // The local library indexed the way books are actually identified.
      final localByKey = <String, Book>{
        for (final b
            in await _isar.books.filter().userIdEqualTo(_userId).findAll())
          bookMatchKey(b.title, b.author): b,
      };
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
        // Fall back to a NORMALISED match, not exact equality. The cloud can
        // legitimately hold the same book twice — that is precisely the mess
        // this restore has to land on top of without making it worse — and an
        // exact title match would faithfully recreate both spines locally.
        local ??= localByKey[bookMatchKey(title, author)];
        if (local == null) {
          local = Book()
            ..supabaseId = cloudId
            ..userId = _userId
            ..title = title
            ..author = author
            ..coverUrl = b['cover_url'] as String?
            ..createdAt = DateTime.now();
          await _isar.books.put(local);
          localByKey[bookMatchKey(title, author)] = local;
        } else if (local.supabaseId != cloudId) {
          // Matched by (title, author): adopt the cloud UUID — its supabaseId
          // was a local_ placeholder before its first cloud backup, so later
          // cover/cloud writes target the right row.
          local.supabaseId = cloudId;
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
        final content = h['content'] as String? ?? '';
        // Same highlight already here under another location shape? Adopt the
        // cloud id onto it rather than shelving the quote a second time. Exact
        // location equality used to be the only test, which missed the whole
        // clippings-vs-sync family of mismatches.
        final localMarks = await _isar.highlights
            .filter()
            .userIdEqualTo(_userId)
            .book((q) => q.idEqualTo(book.id))
            .findAll();
        Highlight? twin;
        for (final k in localMarks) {
          if (isSameHighlight(
            locationA: k.location,
            contentA: k.content,
            locationB: loc,
            contentB: content,
          )) {
            twin = k;
            break;
          }
        }
        if (twin != null) {
          if (twin.supabaseId == null) {
            twin.supabaseId = cloudId;
            await _isar.highlights.put(twin);
          }
          continue;
        }

        final hl = Highlight()
          ..supabaseId = cloudId
          ..content = content
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
