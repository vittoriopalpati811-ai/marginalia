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
    final now = DateFormat('d MMMM yyyy', 'it').format(DateTime.now());

    buf.writeln('# Marginalia Export — $now');
    buf.writeln();
    buf.writeln(
        '> Esportato da [Marginalia](https://marginalia.app) — '
        'riscopri i tuoi highlight Kindle.');
    buf.writeln();

    // Group by (bookTitle, bookAuthor) in insertion order.
    final grouped = <String, List<Highlight>>{};
    for (final h in allHighlights) {
      final key = '${h.bookTitle ?? 'Senza titolo'}|||${h.bookAuthor ?? ''}';
      grouped.putIfAbsent(key, () => []).add(h);
    }

    // Sort each group chronologically (earliest highlight first = book order).
    for (final list in grouped.values) {
      list.sort((a, b) =>
          (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));
    }

    final totalBooks = grouped.length;
    final totalHighlights = allHighlights.length;
    buf.writeln('$totalHighlights highlight da $totalBooks '
        '${totalBooks == 1 ? 'libro' : 'libri'}');
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
    final now = DateFormat('d MMMM yyyy', 'it').format(DateTime.now());

    buf.writeln('# $bookTitle');
    if (bookAuthor.isNotEmpty) buf.writeln('## *$bookAuthor*');
    buf.writeln();
    buf.writeln('> Esportato da Marginalia il $now');
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

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Exports all highlights grouped by book, shared as a .md file.
  static Future<void> exportAll(List<Highlight> allHighlights) async {
    final markdown = buildFullMarkdown(allHighlights);
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    await writeAndShareMarkdown(
      markdown: markdown,
      filename: 'marginalia_export_$date.md',
      subject: 'Marginalia — Export completo',
    );
  }

  /// Exports highlights for a single book, shared as a .md file.
  static Future<void> exportBook({
    required String bookTitle,
    required String bookAuthor,
    required List<Highlight> highlights,
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
    );
  }
}
