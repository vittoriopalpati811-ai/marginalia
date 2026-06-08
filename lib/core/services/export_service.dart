import 'dart:ui' show Rect;

import 'package:intl/intl.dart';

import '../models/highlight.dart';
import 'export_file_writer.dart';

/// Generates and shares a Markdown export of the user's highlights.
///
/// Output format (per book):
///
/// ```markdown
/// # Marginalia Export — 16 maggio 2026
///
/// 42 highlight da 8 libri
///
/// ---
///
/// ## Titolo Libro
/// *Autore*
/// 3 highlight
///
/// > Testo dell'highlight sottolineato...
///
/// — Posizione 234 · 10 gen 2024
///
/// 💬 *La mia nota personale*
///
/// ---
/// ```
///
/// Uses string-based book info (from the cross-platform [bookTitle] /
/// [bookAuthor] getters on [Highlight]) so it works identically on native
/// (Isar) and web (Supabase) without touching platform-specific models.
///
/// File I/O is delegated to [writeAndShareMarkdown] which is a conditional
/// export: native uses [dart:io], web shares as plain text.
class ExportService {
  ExportService._();

  // ─── Markdown builders ──────────────────────────────────────────────────────

  /// Builds the Markdown section for a single book.
  static String buildBookSection({
    required String bookTitle,
    required String bookAuthor,
    required List<Highlight> highlights,
  }) {
    final buf = StringBuffer();
    final dateFormatter = DateFormat('d MMM yyyy', 'it');

    buf.writeln('## $bookTitle');
    if (bookAuthor.isNotEmpty) buf.writeln('*$bookAuthor*');
    buf.writeln('${highlights.length} highlight');
    buf.writeln();

    for (final h in highlights) {
      // Blockquote — each content line gets the > prefix.
      for (final line in h.content.trim().split('\n')) {
        buf.writeln('> ${line.trim()}');
      }

      // Metadata: position · date
      final meta = <String>[];
      if (h.location != null && h.location!.isNotEmpty) {
        meta.add('Posizione ${h.location}');
      }
      if (h.addedAt != null) {
        meta.add(dateFormatter.format(h.addedAt!));
      }
      if (meta.isNotEmpty) {
        buf.writeln();
        buf.writeln('— ${meta.join(' · ')}');
      }

      // Personal note
      if (h.note != null && h.note!.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('💬 *${h.note!.trim()}*');
      }

      buf.writeln();
    }

    return buf.toString();
  }

  /// Builds the full Markdown document from a flat list of highlights.
  ///
  /// Highlights are automatically grouped by [Highlight.bookTitle] and sorted
  /// chronologically within each group.
  static String buildFullMarkdown(List<Highlight> allHighlights) {
    final buf = StringBuffer();
    final now = DateFormat('d MMMM yyyy', 'en').format(DateTime.now());

    buf.writeln('# Marginalia Export — $now');
    buf.writeln();
    buf.writeln(
        '> Exported from [Marginalia](https://marginalia.app) — '
        'rediscover your Kindle highlights.');
    buf.writeln();

    // Group by (bookTitle, bookAuthor) in insertion order.
    final grouped = <String, List<Highlight>>{};
    for (final h in allHighlights) {
      final key = '${h.bookTitle ?? 'Untitled'}|||${h.bookAuthor ?? ''}';
      grouped.putIfAbsent(key, () => []).add(h);
    }

    // Sort each group chronologically (earliest highlight first = book order).
    for (final list in grouped.values) {
      list.sort((a, b) =>
          (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));
    }

    final totalBooks = grouped.length;
    final totalHighlights = allHighlights.length;
    buf.writeln('$totalHighlights highlight${totalHighlights == 1 ? '' : 's'} from $totalBooks '
        '${totalBooks == 1 ? 'book' : 'books'}');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final bookTitle = parts[0];
      final bookAuthor = parts.length > 1 ? parts[1] : '';
      buf.write(buildBookSection(
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        highlights: entry.value,
      ));
      buf.writeln('---');
      buf.writeln();
    }

    return buf.toString();
  }

  /// Builds the Markdown document for a single book (with its own header).
  static String buildSingleBookMarkdown({
    required String bookTitle,
    required String bookAuthor,
    required List<Highlight> highlights,
  }) {
    final buf = StringBuffer();
    final now = DateFormat('d MMMM yyyy', 'en').format(DateTime.now());

    buf.writeln('# $bookTitle');
    if (bookAuthor.isNotEmpty) buf.writeln('## *$bookAuthor*');
    buf.writeln();
    buf.writeln('> Exported from Marginalia on $now');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    final sorted = [...highlights]
      ..sort((a, b) =>
          (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));

    buf.write(buildBookSection(
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      highlights: sorted,
    ));

    return buf.toString();
  }

  // ─── CSV (Notion Reading Tracker) ───────────────────────────────────────────

  /// Builds a CSV with one row per highlight, columns:
  /// `Book, Author, Highlight, Note, Location, Date`.
  ///
  /// Notion imports a CSV as a database, so this doubles as an instant "Reading
  /// Tracker" template: import the file and Notion creates a table with those
  /// columns, one row per highlight, grouped/filtered however the user likes.
  /// Also opens cleanly in Sheets / Excel / Numbers.
  static String buildHighlightsCsv(List<Highlight> allHighlights) {
    final dateFormatter = DateFormat('yyyy-MM-dd');

    // RFC 4180 escaping: collapse newlines to spaces (single-line cells), wrap
    // in quotes when the value contains a comma/quote, and double inner quotes.
    String esc(String? value) {
      var s = (value ?? '')
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ')
          .trim();
      // Neutralise spreadsheet formula injection (CWE-1236) AND the very common
      // case of a Kindle highlight that legitimately starts with "- " (which
      // Excel/Sheets would otherwise parse as a formula → #NAME? error).
      if (s.isNotEmpty && '=+-@'.contains(s[0])) {
        s = "'$s";
      }
      if (s.contains(',') || s.contains('"')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final sorted = [...allHighlights]..sort((a, b) {
        final byBook = (a.bookTitle ?? '').compareTo(b.bookTitle ?? '');
        if (byBook != 0) return byBook;
        return (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0));
      });

    final buf = StringBuffer();
    buf.writeln('Book,Author,Highlight,Note,Location,Date');
    for (final h in sorted) {
      buf.writeln([
        esc(h.bookTitle),
        esc(h.bookAuthor),
        esc(h.content),
        esc(h.note),
        esc(h.location),
        esc(h.addedAt != null ? dateFormatter.format(h.addedAt!) : ''),
      ].join(','));
    }
    return buf.toString();
  }

  /// Exports all highlights as a Notion-importable CSV, shared as a .csv file.
  static Future<void> exportAllCsv(
    List<Highlight> allHighlights, {
    Rect? sharePositionOrigin,
  }) async {
    final csv = buildHighlightsCsv(allHighlights);
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    await writeAndShareCsv(
      csv: csv,
      filename: 'marginalia_reading_tracker_$date.csv',
      subject: 'Marginalia — Reading Tracker (CSV)',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Exports all highlights grouped by book, shared as a .md file.
  static Future<void> exportAll(
    List<Highlight> allHighlights, {
    Rect? sharePositionOrigin,
  }) async {
    final markdown = buildFullMarkdown(allHighlights);
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    await writeAndShareMarkdown(
      markdown: markdown,
      filename: 'marginalia_export_$date.md',
      subject: 'Marginalia — Export completo',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Exports highlights for a single book, shared as a .md file.
  static Future<void> exportBook({
    required String bookTitle,
    required String bookAuthor,
    required List<Highlight> highlights,
    Rect? sharePositionOrigin,
  }) async {
    final markdown = buildSingleBookMarkdown(
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      highlights: highlights,
    );
    // Build a safe filename slug from the book title.
    final slug = bookTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    await writeAndShareMarkdown(
      markdown: markdown,
      filename: 'marginalia_${slug.isEmpty ? 'libro' : slug}.md',
      subject: 'Highlight: $bookTitle',
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
