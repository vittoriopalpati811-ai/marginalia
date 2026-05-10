import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/core/parser/my_clippings_parser.dart';

void main() {
  final parser = MyClippingsParser();

  group('MyClippingsParser', () {
    test('parses a single English highlight', () {
      const input = '''The Great Gatsby (F. Scott Fitzgerald)
- Your Highlight on location 342-344 | Added on Saturday, January 1, 2022 10:30:00 AM

So we beat on, boats against the current, borne back ceaselessly into the past.
==========''';

      final clippings = parser.parse(input);
      expect(clippings.length, 1);
      final c = clippings.first;
      expect(c.bookTitle, 'The Great Gatsby');
      expect(c.bookAuthor, 'F. Scott Fitzgerald');
      expect(c.content, 'So we beat on, boats against the current, borne back ceaselessly into the past.');
      expect(c.location, '342-344');
      expect(c.type, ClippingType.highlight);
    });

    test('parses an Italian highlight', () {
      const input = '''Il Nome della Rosa (Umberto Eco)
- La tua evidenziazione in posizione 1234-1236 | Aggiunto il domenica 2 gennaio 2022 14:22:30

Nel mezzo del cammin di nostra vita.
==========''';

      final clippings = parser.parse(input);
      expect(clippings.length, 1);
      expect(clippings.first.bookTitle, 'Il Nome della Rosa');
      expect(clippings.first.bookAuthor, 'Umberto Eco');
      expect(clippings.first.location, '1234-1236');
    });

    test('filters out bookmarks', () {
      const input = '''Atomic Habits (James Clear)
- Your Bookmark on location 100 | Added on Monday, February 7, 2022 8:00:00 AM


==========''';

      final clippings = parser.parse(input);
      expect(clippings, isEmpty);
    });

    test('deduplicates highlights at the same location keeping longest', () {
      const input = '''Thinking, Fast and Slow (Daniel Kahneman)
- Your Highlight on location 500 | Added on Tuesday, March 1, 2022 9:00:00 AM

Short version.
==========
Thinking, Fast and Slow (Daniel Kahneman)
- Your Highlight on location 500 | Added on Tuesday, March 1, 2022 9:05:00 AM

The longer and more complete version of the same highlight at the same location.
==========''';

      final clippings = parser.parse(input);
      expect(clippings.length, 1);
      expect(clippings.first.content,
          'The longer and more complete version of the same highlight at the same location.');
    });

    test('groups highlights from multiple books', () {
      const input = '''Book One (Author A)
- Your Highlight on location 10 | Added on Monday, January 3, 2022 10:00:00 AM

First highlight.
==========
Book Two (Author B)
- Your Highlight on location 20 | Added on Tuesday, January 4, 2022 11:00:00 AM

Second highlight.
==========''';

      final clippings = parser.parse(input);
      expect(clippings.length, 2);
      expect(clippings.map((c) => c.bookTitle).toSet(), {'Book One', 'Book Two'});
    });

    test('handles entries with no location', () {
      const input = '''Some Book (Some Author)
- Your Highlight | Added on Wednesday, May 1, 2022 8:00:00 AM

A highlight with no location info.
==========''';

      final clippings = parser.parse(input);
      expect(clippings.length, 1);
      expect(clippings.first.location, isNull);
    });

    test('returns empty list for empty input', () {
      expect(parser.parse(''), isEmpty);
    });

    test('returns empty list for only separators', () {
      expect(parser.parse('==========\n==========\n'), isEmpty);
    });
  });
}
