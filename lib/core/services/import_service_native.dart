import 'package:isar/isar.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../parser/my_clippings_parser.dart';

class ImportResult {
  const ImportResult({
    required this.booksAdded,
    required this.highlightsAdded,
    required this.highlightsDeduplicated,
  });

  final int booksAdded;
  final int highlightsAdded;
  final int highlightsDeduplicated;
}

class ImportService {
  const ImportService(this._isar, this._userId, {dynamic supabaseService});

  final Isar _isar;
  final String _userId;

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

    return ImportResult(
      booksAdded: booksAdded,
      highlightsAdded: highlightsAdded,
      highlightsDeduplicated: highlightsDeduplicated,
    );
  }

  // Generate a stable local ID (not a Supabase UUID — used before first sync)
  String _generateLocalId(String title, String author) {
    final bytes = utf8.encode('$title|$author');
    return 'local_${sha256.convert(bytes).toString().substring(0, 16)}';
  }
}
