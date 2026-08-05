import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/features/library/bookshelf_view.dart';

// The shelf packs spines of varying width into rows by hand, so the two ways
// that can go wrong are locked down here:
//
//   • a row overflowing its board (Flutter turns any RenderFlex overflow into a
//     test failure, so simply pumping a full library asserts it), and
//   • a "widow" — one lonely book left on the bottom board, which reads as a
//     bug rather than as a shelf.

List<ShelfEntry> _library(int count) => List.generate(
      count,
      (i) => ShelfEntry(
        title: 'Titolo numero ${i + 1}',
        author: 'Autore ${i + 1}',
        bookId: i + 1,
        // Spread across the thickness range: thin, average and very marked-up.
        highlightCount: (i * 7) % 45,
      ),
    );

Future<void> _pumpShelf(
  WidgetTester tester,
  List<ShelfEntry> entries, {
  double width = 320,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: BookshelfView(entries: entries, onTap: (_, __) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1)); // settle the entrance animation
}

void main() {
  testWidgets('a full library packs into shelves without overflowing a row',
      (tester) async {
    await _pumpShelf(tester, _library(41));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every book keeps its title on the shelf', (tester) async {
    await _pumpShelf(tester, _library(12));

    // Titles are rotated, not hidden: each one is still a Text in the tree.
    for (var i = 1; i <= 12; i++) {
      expect(find.text('Titolo numero $i'), findsOneWidget);
    }
  });

  testWidgets('no book is left alone on the bottom shelf', (tester) async {
    // Sweep library sizes so at least some of them would naturally leave one
    // or two books stranded on the last row.
    for (final count in [9, 10, 11, 13, 17, 22, 29, 34, 41]) {
      await _pumpShelf(tester, _library(count));
      expect(tester.takeException(), isNull, reason: '$count books overflowed');

      // Whatever the rebalancing did, no book may be dropped on the way.
      for (var i = 1; i <= count; i++) {
        expect(find.text('Titolo numero $i'), findsOneWidget,
            reason: 'book $i vanished from a $count-book shelf');
      }
    }
  });

  testWidgets('an empty library draws nothing at all', (tester) async {
    await _pumpShelf(tester, const []);
    // Not "paints nothing" — Material paints plenty on its own — but that the
    // shelf itself takes up no room.
    expect(tester.getSize(find.byType(BookshelfView)).height, 0);
  });

  testWidgets('a single book still stands on a shelf', (tester) async {
    await _pumpShelf(tester, _library(1));
    expect(tester.takeException(), isNull);
    expect(find.text('Titolo numero 1'), findsOneWidget);
  });
}
