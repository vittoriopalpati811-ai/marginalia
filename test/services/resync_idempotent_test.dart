import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scripta/core/parser/my_clippings_parser.dart';
import 'package:scripta/core/services/amazon_sync_service.dart';
import 'package:scripta/core/services/import_match.dart';

// The question the founder asked: "c'è il rischio di overlapping nella libreria
// e negli highlights quando si fa il sync di nuovo". There was, twice over — the
// two doors into the library disagree about how to write an author and how to
// write a location, so the same book arrived as a second book and the same
// quote as a second quote.
//
// This walks the importer's actual decision loop over the actual byte shapes
// both doors produce. It does not touch Isar; it asks the only question that
// matters — after the second import, how many books and how many highlights?

/// The importer's loop, in miniature: one shelf, matched the way the real one
/// matches, so the rules are exercised rather than described.
class _Shelf {
  final Map<String, List<ParsedClipping>> books = {};

  void import(String clippingsText) {
    for (final c in MyClippingsParser().parse(clippingsText)) {
      if (c.type == ClippingType.bookmark) continue;
      final marks =
          books.putIfAbsent(bookMatchKey(c.bookTitle, c.bookAuthor), () => <ParsedClipping>[]);
      final twin = marks.indexWhere((m) => isSameHighlight(
            locationA: m.location,
            contentA: m.content,
            locationB: c.location,
            contentB: c.content,
          ));
      if (twin >= 0) {
        if (c.content.length > marks[twin].content.length) marks[twin] = c;
        continue;
      }
      marks.add(c);
    }
  }

  int get bookCount => books.length;
  int get markCount => books.values.fold(0, (n, l) => n + l.length);
}

/// A page of the reader's real Kindle notebook, as the sync serialises it.
String _fromKindleSync() => amazonHighlightsToClippingsText(const [
      AmazonHighlight(
        bookTitle: 'Il nome della rosa',
        bookAuthor: 'Umberto Eco',
        content: 'Il libro parlava di cose ridicole.',
        location: '1234',
      ),
      AmazonHighlight(
        bookTitle: 'Il nome della rosa',
        bookAuthor: 'Umberto Eco',
        content: 'La biblioteca si difende da sola.',
        location: '2500',
      ),
      AmazonHighlight(
        bookTitle: 'Il nome della rosa',
        bookAuthor: 'Umberto Eco',
        content: 'Una frase che Amazon non sa dove sta.',
      ),
    ]);

/// The same three highlights as Kindle wrote them into My Clippings.txt:
/// surname-first author, location as a RANGE.
const _fromClippingsFile = '''
Il nome della rosa (Eco, Umberto)
- La tua evidenziazione alla posizione 1234-1236 | Aggiunto in data lunedì 3 marzo 2025 21:14:52

Il libro parlava di cose ridicole.
==========
Il nome della rosa (Eco, Umberto)
- La tua evidenziazione alla posizione 2500-2502 | Aggiunto in data lunedì 3 marzo 2025 21:20:11

La biblioteca si difende da sola.
==========
''';

void main() {
  setUpAll(() async => initializeDateFormatting('en_US'));

  test('syncing the same notebook twice changes nothing', () {
    // The automatic sync re-reads the WHOLE notebook every six hours. If this
    // were not exactly idempotent the library would grow without anyone doing
    // anything — which is the failure mode that made this worth checking.
    final shelf = _Shelf()..import(_fromKindleSync());
    final booksAfterFirst = shelf.bookCount;
    final marksAfterFirst = shelf.markCount;

    shelf.import(_fromKindleSync());
    shelf.import(_fromKindleSync());

    expect(shelf.bookCount, booksAfterFirst, reason: 'the book multiplied');
    expect(shelf.markCount, marksAfterFirst, reason: 'the highlights multiplied');
    expect(shelf.bookCount, 1);
    expect(shelf.markCount, 3);
  });

  test('a clippings file and the Kindle sync are one library, not two', () {
    // The real-world case: the reader imported My Clippings.txt once, then
    // connected Kindle. Author order and location shape both differ, and before
    // this the shelf ended up with the same book twice, each holding its own
    // copy of the same sentences.
    final shelf = _Shelf()
      ..import(_fromClippingsFile)
      ..import(_fromKindleSync());

    expect(shelf.bookCount, 1,
        reason: 'the same book landed on the shelf twice');
    // Two quotes are shared; the third exists only in the Kindle notebook.
    expect(shelf.markCount, 3,
        reason: 'a shared quote was stored under both spellings');
  });

  test('the order the two imports run in does not matter', () {
    final a = _Shelf()
      ..import(_fromClippingsFile)
      ..import(_fromKindleSync());
    final b = _Shelf()
      ..import(_fromKindleSync())
      ..import(_fromClippingsFile);

    expect(b.bookCount, a.bookCount);
    expect(b.markCount, a.markCount);
  });

  test('a highlight with no location survives a re-sync without duplicating', () {
    // Amazon reports some highlights with no location at all. These are keyed
    // by a digest of their text, so they must land once and stay once.
    final shelf = _Shelf()
      ..import(_fromKindleSync())
      ..import(_fromKindleSync());

    final marks = shelf.books.values.single;
    final orphan =
        marks.where((m) => m.content.contains('non sa dove sta')).toList();
    expect(orphan, hasLength(1));
  });

  test('a genuinely new highlight still arrives', () {
    // The other way to pass every test above is to import nothing at all.
    final shelf = _Shelf()..import(_fromKindleSync());
    shelf.import(amazonHighlightsToClippingsText(const [
      AmazonHighlight(
        bookTitle: 'Il nome della rosa',
        bookAuthor: 'Umberto Eco',
        content: 'Una frase nuova di zecca.',
        location: '9000',
      ),
    ]));
    expect(shelf.markCount, 4);
    expect(shelf.bookCount, 1);
  });
}
