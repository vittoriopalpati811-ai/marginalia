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
//   1. Kindle "My Clippings.txt" already — recognised by parsing it and seeing
//      that it actually yields clippings (not merely by containing "==========",
//      which can appear as a divider in free-form notes).
//
//   2. Apple Books copy: each highlight is a quote FOLLOWED by an attribution
//        Excerpt From
//        <Title>
//        <Author>
//        This material may be protected by copyright.
//      (or the inline "Excerpt From: <Title> by <Author>"). Parsed line-by-line
//      so it works whether or not the (localised) copyright line is present.
//
//   3. Free-form: one highlight per blank-line-separated block (or the whole
//      text as a single highlight), filed under the title/author the user typed.
//
// Every synthesised entry gets a STABLE numeric "location" derived from the
// content, so the downstream importer (which dedups on book+location) treats a
// re-paste of the same text as a duplicate instead of collapsing distinct
// highlights together.

import 'my_clippings_parser.dart';

const _clippingsSeparator = '==========';

/// All straight + smart quotation marks we strip from the edges of a quote.
final _edgeQuotes = RegExp(r'^["«“”‘’‹]+|["»“”‘’›]+$');

final _excerptMarker = RegExp(r'excerpt from', caseSensitive: false);
final _excerptInline =
    RegExp(r'^[:\s]*(.+?)\s+by\s+(.+)$', caseSensitive: false, dotAll: true);
// Loose copyright-notice matcher — English ("…protected by copyright."),
// Italian ("…protetto da copyright."), and the © glyph.
final _copyrightLine =
    RegExp(r'copyright|©|protett|protected', caseSensitive: false);

bool _isCopyright(String line) => _copyrightLine.hasMatch(line);

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
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) return '';

  // (1) Already Kindle format → pass through, but ONLY if it really parses as
  // clippings. A bare "==========" divider in free-form notes must NOT short-
  // circuit here (it would be split into sub-3-line fragments and dropped).
  if (text.contains(_clippingsSeparator) &&
      MyClippingsParser().parse(text).isNotEmpty) {
    return text;
  }

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
    // Defuse any run of '=' that could look like the Kindle entry separator and
    // split this content into broken fragments on re-parse.
    final safeContent = h.content.trim().replaceAll(RegExp(r'={5,}'), '=');
    // Sanitise the author's parentheses: the synthesised header is
    // "Title (Author)" and MyClippingsParser's title/author regex needs the
    // LAST '(...)' to be the author — a ')' inside the author breaks it and the
    // whole entry is silently dropped on re-parse.
    final rawAuthor = h.author.trim();
    final author = rawAuthor.isEmpty
        ? ' '
        : rawAuthor.replaceAll('(', '[').replaceAll(')', ']');
    buffer.writeln('${h.title.trim()} ($author)');
    buffer.writeln('- Your Highlight | location $location');
    buffer.writeln();
    buffer.writeln(safeContent);
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

  // ── (2) Apple Books (quote FOLLOWED by "Excerpt From …") ────────────────────
  if (_excerptMarker.hasMatch(text)) {
    final out = <PastedHighlight>[];
    final lines = text.split('\n');
    final quoteBuf = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();

      if (_excerptMarker.hasMatch(trimmed)) {
        final quote = _stripQuotes(quoteBuf.join('\n'));
        quoteBuf.clear();

        var title = fbTitle;
        var author = fbAuthor;

        // inline form: "Excerpt From: <Title> by <Author>"
        final afterMarker = trimmed.replaceFirst(_excerptMarker, '').trim();
        final inline = afterMarker.isEmpty ? null : _excerptInline.firstMatch(afterMarker);
        if (inline != null) {
          title = inline.group(1)!.trim();
          author = inline.group(2)!.trim();
        } else {
          // multi-line: the next up-to-two non-empty, non-copyright lines are
          // the title then the author.
          final attr = <String>[];
          var j = i + 1;
          while (j < lines.length && attr.length < 2) {
            final t = lines[j].trim();
            j++;
            if (t.isEmpty) {
              if (attr.isEmpty) continue; // skip blanks before the title
              break; // a blank after the title ends the attribution
            }
            if (_isCopyright(t)) break;
            attr.add(t);
          }
          if (attr.isNotEmpty) title = attr[0];
          if (attr.length > 1) author = attr[1];
          i = j - 1; // resume after the consumed attribution lines
        }

        if (quote.isNotEmpty) {
          out.add(PastedHighlight(
            quote,
            title.trim().isEmpty ? genericTitle : title.trim(),
            author.trim(),
          ));
        }
      } else if (_isCopyright(trimmed)) {
        // drop stray copyright lines so they never leak into a quote
        continue;
      } else {
        quoteBuf.add(lines[i]);
      }
    }
    if (out.isNotEmpty) return out;
  }

  // ── (3) Free-form ──────────────────────────────────────────────────────────
  // Split on a blank line OR a divider line of 3+ '=' (people paste lists
  // separated either way), so each becomes its own highlight.
  final blocks = text
      .split(RegExp(r'\n\s*\n|\n\s*={3,}\s*\n'))
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
