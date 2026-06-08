// ─── Pasted-highlights parser ────────────────────────────────────────────────
//
// Converts text the user PASTES (rather than imports as a file) into canonical
// Kindle "My Clippings.txt" so it can be fed, unchanged, to the existing
// ImportService.importClippingsText pipeline (native + web). Supporting paste —
// not just a file picker — is what lets people import highlights from sources
// that don't hand you a tidy file: Apple Books (copy a highlight), a notes app,
// an email to oneself, etc.
//
// Three input shapes are recognised, in priority order:
//
//   1. Kindle "My Clippings.txt" already (contains the "==========" separator):
//      passed through verbatim — the existing parser handles every locale.
//
//   2. Apple Books copy: each highlight ends with the attribution block
//        Excerpt From
//        <Title>
//        <Author>
//        This material may be protected by copyright.
//      (or the inline "Excerpt From: <Title> by <Author>"). Title/author are
//      extracted per highlight; the surrounding smart-quotes are stripped.
//
//   3. Free-form: one highlight per blank-line-separated block (or the whole
//      text as a single highlight), filed under the title/author the user typed
//      in the paste screen.
//
// Every synthesised entry gets a STABLE numeric "location" derived from the
// content, so the downstream importer (which dedups on book+location) treats a
// re-paste of the same text as a duplicate instead of collapsing distinct
// highlights together (null locations all collide on one row).

const _clippingsSeparator = '==========';

/// All straight + smart quotation marks we strip from the edges of a quote.
final _edgeQuotes = RegExp(
  r'^["«“”‘’‹]+|["»“”‘’›]+$',
);

final _excerptMarker = RegExp(r'excerpt from', caseSensitive: false);
final _copyrightSentinel =
    RegExp(r'This material may be protected by copyright\.?', caseSensitive: false);
final _excerptInline =
    RegExp(r'^[:\s]*(.+?)\s+by\s+(.+)$', caseSensitive: false, dotAll: true);

class PastedHighlight {
  const PastedHighlight(this.content, this.title, this.author);
  final String content;
  final String title;
  final String author;
}

/// Converts pasted text to "My Clippings.txt" form. Returns an empty string when
/// nothing usable was found (the caller should treat that as "no highlights").
String synthesizeClippingsFromPaste(
  String raw, {
  String? fallbackTitle,
  String? fallbackAuthor,
}) {
  final text =
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) return '';

  // (1) Already Kindle format → pass through; the existing parser is better at
  // it (handles locations, dates, every firmware locale) than we could be.
  if (text.contains(_clippingsSeparator)) return text;

  final highlights = parsePastedHighlights(
    text,
    fallbackTitle: fallbackTitle,
    fallbackAuthor: fallbackAuthor,
  );
  if (highlights.isEmpty) return '';

  final buffer = StringBuffer();
  for (final h in highlights) {
    // Stable, deterministic numeric location keyed on the content so re-pasting
    // dedups instead of duplicating. abs() keeps the location-regex ([\d\-]+)
    // happy (no leading minus).
    final location = h.content.hashCode.abs();
    final author = h.author.trim().isEmpty ? ' ' : h.author.trim();
    buffer.writeln('${h.title.trim()} ($author)');
    buffer.writeln('- Your Highlight | location $location');
    buffer.writeln();
    buffer.writeln(h.content.trim());
    buffer.writeln(_clippingsSeparator);
  }
  return buffer.toString();
}

/// Parses pasted (non-Kindle) text into individual highlights. Exposed for unit
/// testing; [synthesizeClippingsFromPaste] is the production entry point.
List<PastedHighlight> parsePastedHighlights(
  String text, {
  String? fallbackTitle,
  String? fallbackAuthor,
}) {
  final fbTitle = (fallbackTitle ?? '').trim();
  final fbAuthor = (fallbackAuthor ?? '').trim();
  final genericTitle = fbTitle.isEmpty ? 'Pasted highlights' : fbTitle;

  // ── (2) Apple Books ────────────────────────────────────────────────────────
  if (_excerptMarker.hasMatch(text)) {
    final out = <PastedHighlight>[];
    // Each highlight ends with the copyright sentinel when present; otherwise
    // split just before each "Excerpt From" so multiple highlights separate.
    final records = _copyrightSentinel.hasMatch(text)
        ? text.split(_copyrightSentinel)
        : text.split(RegExp(r'(?=excerpt from)', caseSensitive: false));

    for (final record in records) {
      final rec = record.trim();
      if (rec.isEmpty) continue;

      final markerMatch = _excerptMarker.firstMatch(rec);
      if (markerMatch == null) {
        // A trailing quote with no attribution → file under the fallback book.
        final quote = _stripQuotes(rec);
        if (quote.isNotEmpty) {
          out.add(PastedHighlight(quote, genericTitle, fbAuthor));
        }
        continue;
      }

      final quote = _stripQuotes(rec.substring(0, markerMatch.start));
      final attribution = rec.substring(markerMatch.end).trim();
      var title = fbTitle;
      var author = fbAuthor;

      final inline = _excerptInline.firstMatch(attribution);
      if (inline != null && !attribution.contains('\n')) {
        title = inline.group(1)!.trim();
        author = inline.group(2)!.trim();
      } else {
        final lines = attribution
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) title = lines[0];
        if (lines.length > 1) author = lines[1];
      }

      if (quote.isNotEmpty) {
        out.add(PastedHighlight(
          quote,
          title.trim().isEmpty ? genericTitle : title.trim(),
          author.trim(),
        ));
      }
    }
    if (out.isNotEmpty) return out;
  }

  // ── (3) Free-form ──────────────────────────────────────────────────────────
  final blocks = text
      .split(RegExp(r'\n\s*\n'))
      .map((b) => _stripQuotes(b))
      .where((b) => b.isNotEmpty)
      .toList();

  final items = blocks.isEmpty ? [_stripQuotes(text)] : blocks;
  return [
    for (final item in items)
      if (item.trim().isNotEmpty) PastedHighlight(item, genericTitle, fbAuthor),
  ];
}

/// Trims and strips a single layer of surrounding quotation marks (straight or
/// smart), leaving inner punctuation intact.
String _stripQuotes(String s) => s.trim().replaceAll(_edgeQuotes, '').trim();
