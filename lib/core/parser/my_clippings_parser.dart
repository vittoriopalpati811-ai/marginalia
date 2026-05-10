import 'package:intl/intl.dart';

class ParsedClipping {
  const ParsedClipping({
    required this.bookTitle,
    required this.bookAuthor,
    required this.content,
    required this.type,
    this.location,
    this.addedAt,
    this.color,
  });

  final String bookTitle;
  final String bookAuthor;
  final String content;
  final ClippingType type;
  final String? location;
  final DateTime? addedAt;
  final String? color;

  // Deduplication key: same book + location = same highlight
  String get dedupKey => '$bookTitle|$bookAuthor|${location ?? content.hashCode}';
}

enum ClippingType { highlight, note, bookmark }

class MyClippingsParser {
  // Entry separator used by Kindle firmware
  static const _separator = '==========';

  // Regex patterns
  static final _titleAuthorRegex = RegExp(r'^(.+?)\s*\(([^)]+)\)\s*$');
  static final _locationRegex = RegExp(
    r'(?:location|posizione|emplacement|Ort|ubicaci[oó]n)\s+([\d\-]+)',
    caseSensitive: false,
  );
  static final _pageRegex = RegExp(
    r'(?:page|pagina|página|Seite)\s+([\d\-]+)',
    caseSensitive: false,
  );

  // Date format patterns across Kindle firmware locales.
  // Kept as (pattern, locale) pairs so each DateFormat is constructed lazily
  // inside a try-catch — avoids static initializer errors when locale data
  // hasn't been loaded (common in unit tests without initializeDateFormatting).
  static const _dateFormatSpecs = [
    ('EEEE, MMMM d, yyyy h:mm:ss a', 'en_US'),
    ('EEEE d MMMM yyyy HH:mm:ss', 'it'),
    ("EEEE d MMMM yyyy HH'h'mm", 'fr'),
    ('dd MMMM yyyy HH:mm:ss', 'it'),
    ('MMMM d, yyyy h:mm:ss a', 'en_US'),
  ];

  List<ParsedClipping> parse(String rawText) {
    final entries = rawText
        .split(_separator)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final Map<String, ParsedClipping> seen = {};

    for (final entry in entries) {
      final clipping = _parseEntry(entry);
      if (clipping == null) continue;
      if (clipping.type == ClippingType.bookmark) continue;

      // Dedup: keep the longer content for same location
      final existing = seen[clipping.dedupKey];
      if (existing == null || clipping.content.length > existing.content.length) {
        seen[clipping.dedupKey] = clipping;
      }
    }

    return seen.values.toList()
      ..sort((a, b) => (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));
  }

  ParsedClipping? _parseEntry(String entry) {
    final lines = entry.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.length < 3) return null;

    // Line 0: "Book Title (Author Name)"
    final titleAuthorMatch = _titleAuthorRegex.firstMatch(lines[0]);
    if (titleAuthorMatch == null) return null;

    final bookTitle = titleAuthorMatch.group(1)!.trim();
    final bookAuthor = titleAuthorMatch.group(2)!.trim();

    // Line 1: metadata "- Your Highlight on location 123 | Added on ..."
    final metaLine = lines[1];
    final type = _detectType(metaLine);
    final location = _extractLocation(metaLine);
    final addedAt = _extractDate(metaLine);

    // Lines 2+: content
    final content = lines.sublist(2).join(' ').trim();
    if (content.isEmpty) return null;

    return ParsedClipping(
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      content: content,
      type: type,
      location: location,
      addedAt: addedAt,
    );
  }

  ClippingType _detectType(String metaLine) {
    final lower = metaLine.toLowerCase();
    if (lower.contains('highlight') ||
        lower.contains('evidenziazione') ||
        lower.contains('surlignement')) {
      return ClippingType.highlight;
    }
    if (lower.contains('note') || lower.contains('nota') || lower.contains('note')) {
      return ClippingType.note;
    }
    return ClippingType.bookmark;
  }

  String? _extractLocation(String metaLine) {
    final locMatch = _locationRegex.firstMatch(metaLine);
    if (locMatch != null) return locMatch.group(1);
    final pageMatch = _pageRegex.firstMatch(metaLine);
    return pageMatch?.group(1);
  }

  DateTime? _extractDate(String metaLine) {
    final addedOnRegex = RegExp(
      r'(?:Added on|Aggiunto il|Ajouté le|Hinzugef[üu]gt am|[Aa]gregado el)\s+(.+)',
      caseSensitive: false,
    );
    final match = addedOnRegex.firstMatch(metaLine);
    final dateStr = match?.group(1)?.trim() ?? metaLine;

    for (final (pattern, locale) in _dateFormatSpecs) {
      try {
        // DateFormat constructed inside try-catch: locale init errors are caught.
        return DateFormat(pattern, locale).parse(dateStr, true);
      } catch (_) {}
    }
    return null;
  }
}
