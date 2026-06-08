import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/core/parser/paste_parser.dart';
import 'package:marginalia/core/parser/my_clippings_parser.dart';

void main() {
  group('parsePastedHighlights', () {
    test('Apple Books multi-line attribution', () {
      const text = '''
“The unexamined life is not worth living.”

Excerpt From
Apology
Plato
This material may be protected by copyright.''';
      final hs = parsePastedHighlights(text);
      expect(hs, hasLength(1));
      expect(hs.first.content, 'The unexamined life is not worth living.');
      expect(hs.first.title, 'Apology');
      expect(hs.first.author, 'Plato');
    });

    test('Apple Books inline "Title by Author"', () {
      const text = '''
"Quote one."

Excerpt From: Meditations by Marcus Aurelius
This material may be protected by copyright.''';
      final hs = parsePastedHighlights(text);
      expect(hs, hasLength(1));
      expect(hs.first.content, 'Quote one.');
      expect(hs.first.title, 'Meditations');
      expect(hs.first.author, 'Marcus Aurelius');
    });

    test('Apple Books multiple highlights', () {
      const text = '''
“First.”

Excerpt From
Book A
Author A
This material may be protected by copyright.
“Second.”

Excerpt From
Book A
Author A
This material may be protected by copyright.''';
      final hs = parsePastedHighlights(text);
      expect(hs, hasLength(2));
      expect(hs[0].content, 'First.');
      expect(hs[1].content, 'Second.');
    });

    test('free-form blocks under fallback book', () {
      const text = '''
A first thought worth keeping.

A second, unrelated thought.''';
      final hs = parsePastedHighlights(text,
          fallbackTitle: 'My Notes', fallbackAuthor: 'Me');
      expect(hs, hasLength(2));
      expect(hs[0].title, 'My Notes');
      expect(hs[0].author, 'Me');
      expect(hs[1].content, 'A second, unrelated thought.');
    });

    test('single free-form line is one highlight', () {
      final hs = parsePastedHighlights('Just one line.',
          fallbackTitle: 'X');
      expect(hs, hasLength(1));
      expect(hs.first.content, 'Just one line.');
      expect(hs.first.title, 'X');
    });
  });

  group('synthesizeClippingsFromPaste', () {
    test('Kindle format passes through unchanged', () {
      const kindle =
          'Title (Author)\n- Your Highlight | location 100\n\nHi\n==========';
      expect(synthesizeClippingsFromPaste(kindle), kindle);
    });

    test('synthesised output round-trips through MyClippingsParser', () {
      const text = '''
“Alpha quote.”

Excerpt From
Greek Book
Some Author
This material may be protected by copyright.''';
      final synthesized = synthesizeClippingsFromPaste(text);
      final parsed = MyClippingsParser().parse(synthesized);
      expect(parsed, hasLength(1));
      expect(parsed.first.type, ClippingType.highlight);
      expect(parsed.first.bookTitle, 'Greek Book');
      expect(parsed.first.bookAuthor, 'Some Author');
      expect(parsed.first.content, 'Alpha quote.');
      expect(parsed.first.location, isNotNull);
    });

    test('two distinct free-form highlights survive the importer dedup key', () {
      final synthesized = synthesizeClippingsFromPaste(
        'First distinct quote.\n\nSecond distinct quote.',
        fallbackTitle: 'Book',
        fallbackAuthor: 'Auth',
      );
      final parsed = MyClippingsParser().parse(synthesized);
      // Distinct content ⇒ distinct stable locations ⇒ both kept.
      expect(parsed, hasLength(2));
      expect(parsed.map((p) => p.location).toSet(), hasLength(2));
    });

    test('empty input yields empty output', () {
      expect(synthesizeClippingsFromPaste('   '), '');
    });
  });
}
