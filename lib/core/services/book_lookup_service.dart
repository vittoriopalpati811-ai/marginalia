// ─── BookLookupService ──────────────────────────────────────────────────────
//
// Fetches book metadata from Open Library by ISBN (10 or 13 digits).
// No API key required, no rate limits beyond fair-use, works on every
// platform including Flutter web.
//
// We chose Open Library over Google Books because the latter now requires
// an API key with billing — even for ISBN lookups — and returns HTTP 429
// for anonymous requests.
//
// Usage:
//   final book = await BookLookupService.byIsbn('9780735211292');
//   if (book != null) print('${book.title} — ${book.author}');

import 'dart:convert';
import 'package:http/http.dart' as http;

class BookLookupResult {
  const BookLookupResult({
    required this.isbn,
    required this.title,
    this.author,
    this.coverUrl,
    this.publishDate,
    this.pageCount,
  });

  final String isbn;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? publishDate;
  final int?    pageCount;
}

class BookLookupService {
  static final _isbnDigitsOnly = RegExp(r'[^0-9X]');

  /// Strips any non-digit characters (spaces, hyphens) and validates the
  /// result is 10 or 13 digits. Returns null if invalid.
  static String? normalizeIsbn(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(_isbnDigitsOnly, '');
    if (cleaned.length == 10 || cleaned.length == 13) return cleaned;
    return null;
  }

  /// Looks up a book by ISBN. Returns null if not found, the API errors,
  /// or the ISBN is malformed.
  static Future<BookLookupResult?> byIsbn(String rawIsbn) async {
    final isbn = normalizeIsbn(rawIsbn);
    if (isbn == null) return null;

    try {
      final uri = Uri.parse(
        'https://openlibrary.org/api/books'
        '?bibkeys=ISBN:$isbn&format=json&jscmd=data',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      // UTF-8 explicit: Open Library may omit `charset=utf-8`, and Dart http
      // then falls back to latin1 → accented titles/authors become mojibake.
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final entry = body['ISBN:$isbn'] as Map<String, dynamic>?;
      if (entry == null) return null;

      final title  = (entry['title'] as String?)?.trim();
      if (title == null || title.isEmpty) return null;

      // Authors: list of {name, url}. Join multiple with comma.
      final authorList = (entry['authors'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map((a) => (a['name'] as String?)?.trim())
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toList() ?? const <String>[];
      final author = authorList.isEmpty ? null : authorList.join(', ');

      // Cover: prefer medium, fall back to large or small.
      final coverMap = entry['cover'] as Map<String, dynamic>?;
      final coverUrl = (coverMap?['medium'] ?? coverMap?['large'] ?? coverMap?['small']) as String?;

      final publishDate = (entry['publish_date'] as String?)?.trim();
      final pageCount   = (entry['number_of_pages'] as num?)?.toInt();

      return BookLookupResult(
        isbn: isbn,
        title: title,
        author: author,
        coverUrl: coverUrl,
        publishDate: publishDate,
        pageCount: pageCount,
      );
    } catch (_) {
      return null;
    }
  }
}
