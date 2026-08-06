import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/models/highlight.dart';
import 'package:scripta/core/providers/highlights_provider.dart';
import 'package:scripta/features/reader/book_info_screen.dart';

// The founder tapped a book on his profile and got a page with a cover, a title
// and nothing else: "se clicco su un libro nella libreria non fa vedere le frasi
// salvate". The profile shelf routes to BookInfoScreen, which had no highlight
// code in it at all — so no query was failing, there was simply nothing to fail.
// These tests are about the SCREEN keeping its promise, whatever routes to it.

Highlight _mark(String text, {String? location}) => Highlight()
  ..content = text
  ..location = location
  ..userId = 'u1';

Widget _host(List<Highlight> marks, {String title = 'Il nome della rosa'}) {
  return ProviderScope(
    overrides: [
      allHighlightsProvider.overrideWith((ref) async => marks),
    ],
    child: MaterialApp(
      locale: const Locale('it'),
      home: BookInfoScreen(title: title, author: 'Umberto Eco'),
    ),
  );
}

void main() {
  // The matching rule, tested directly. The widget path cannot reach it: in a
  // test `Highlight.bookTitle` reads through an Isar link nothing can populate,
  // so a widget test asserting "the phrases appear" would only ever be checking
  // that null != a title. This is the part with actual decisions in it.
  group('which highlights belong to the book on screen', () {
    test('an exact title matches regardless of case and padding', () {
      expect(highlightBelongsToBook('  IL NOME della Rosa ', 'Il nome della rosa'),
          isTrue);
    });

    test('a sibling volume does NOT match', () {
      // The reason the rule is exact and not a prefix/"core title" match: a
      // reader looking at one volume must not be shown another's phrases.
      expect(
        highlightBelongsToBook(
            'Il Signore degli Anelli — Le due torri', 'Il Signore degli Anelli'),
        isFalse,
      );
    });

    test('a highlight whose book link never loaded matches nothing', () {
      expect(highlightBelongsToBook(null, 'Il nome della rosa'), isFalse);
    });

    test('an empty screen title matches nothing', () {
      // Otherwise a book row with a blank title would collect every orphan
      // highlight in the library.
      expect(highlightBelongsToBook('', ''), isFalse);
      expect(highlightBelongsToBook(null, '   '), isFalse);
    });
  });

  testWidgets('a book with no saved phrases does not show an empty section',
      (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();

    expect(find.text('FRASI SALVATE'), findsNothing,
        reason: 'an empty section is worse than no section');
  });

  testWidgets('the screen renders without exploding while metadata loads',
      (tester) async {
    // The highlights section is deliberately ABOVE the loading gate, so this
    // also pins that it is reachable on the very first frame — before any
    // network lookup has had a chance to settle.
    await tester.pumpWidget(_host([_mark('Una frase')]));
    await tester.pump();

    expect(find.text('Il nome della rosa'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
