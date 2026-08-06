import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/features/library/bookshelf_view.dart';
import 'package:scripta/features/profile/profile_shared_widgets.dart';
import 'package:scripta/features/profile/shelf_arrange_sheet.dart';

// A reader arranges their shelf and other people see the result, so the order
// has to be reproducible on a device that never made the choice. That is the
// property under test here — not "does sorting sort", but "does the SAME input
// give the SAME shelf everywhere, and does nothing fall off the end".

ShelfEntry _b(String title, String author, [int marks = 0]) =>
    ShelfEntry(title: title, author: author, highlightCount: marks);

final _library = [
  _b('Sapiens', 'Harari', 30),
  _b('anna karenina', 'Tolstoj', 5),
  _b('Il Gattopardo', 'Lampedusa', 12),
  _b('Cosmos', 'Sagan', 40),
];

String _k(ShelfEntry e) => favCoverKey(e.title, e.author);

void main() {
  // A hand arrangement is only as good as the drag that builds it, and this is
  // where it was silently broken: `to` comes back measured against the list
  // BEFORE the item moves, so decrementing it AND inserting into the unshortened
  // list lands every DOWNWARD drag one slot early. Upward drags were correct,
  // which is why a quick check on a real phone said it worked.
  group('a drag lands where it was dropped', () {
    const start = ['A', 'B', 'C', 'D', 'E'];

    test('one slot down actually moves the item', () {
      // The headline bug: this used to return ABCDE — the drag did nothing.
      expect(applyReorder(start, 0, 2), ['B', 'A', 'C', 'D', 'E']);
      expect(applyReorder(start, 1, 3), ['A', 'C', 'B', 'D', 'E']);
      expect(applyReorder(start, 3, 5), ['A', 'B', 'C', 'E', 'D']);
    });

    test('the first book can be dragged all the way to the end', () {
      expect(applyReorder(start, 0, 5), ['B', 'C', 'D', 'E', 'A']);
    });

    test('the last book can be dragged all the way to the front', () {
      expect(applyReorder(start, 4, 0), ['E', 'A', 'B', 'C', 'D']);
    });

    test('upward drags keep working', () {
      expect(applyReorder(start, 2, 0), ['C', 'A', 'B', 'D', 'E']);
      expect(applyReorder(start, 4, 2), ['A', 'B', 'E', 'C', 'D']);
    });

    test('no drag ever loses or duplicates a book', () {
      for (var from = 0; from < start.length; from++) {
        for (var to = 0; to <= start.length; to++) {
          final out = applyReorder(start, from, to);
          expect(out.length, start.length, reason: '($from,$to) changed length');
          expect(out.toSet(), start.toSet(), reason: '($from,$to) lost a book');
        }
      }
    });
  });

  test('every mode keeps every book', () {
    for (final s in ShelfSort.values) {
      final out = applyShelfOrder(_library, s, const []);
      expect(out.length, _library.length, reason: '$s lost a book');
      expect(out.map(_k).toSet(), _library.map(_k).toSet(),
          reason: '$s changed which books are on the shelf');
    }
  });

  test('sorting never mutates the caller\'s list', () {
    // The list belongs to a provider's cache; sorting it in place would
    // reorder the shelf under everything else reading it.
    final original = [..._library.map(_k)];
    for (final s in ShelfSort.values) {
      applyShelfOrder(_library, s, const []);
    }
    expect(_library.map(_k).toList(), original);
  });

  test('by title is case-insensitive', () {
    final out = applyShelfOrder(_library, ShelfSort.title, const []);
    expect(out.map((e) => e.title).toList(),
        ['anna karenina', 'Cosmos', 'Il Gattopardo', 'Sapiens']);
  });

  test('most highlighted puts the best-read book first', () {
    final out = applyShelfOrder(_library, ShelfSort.mostHighlighted, const []);
    expect(out.first.title, 'Cosmos');
    expect(out.last.title, 'anna karenina');
  });

  test('by colour is stable across devices', () {
    // No colour is stored anywhere — a spine's hue is derived from its title and
    // author, so the owner's phone and a visitor's phone must agree. If this
    // ever depended on anything but the book, the arrangement would differ for
    // the person it was arranged FOR.
    final a = applyShelfOrder(_library, ShelfSort.color, const []);
    final b = applyShelfOrder([..._library.reversed], ShelfSort.color, const []);
    expect(a.map(_k).toList(), b.map(_k).toList());
  });

  test('a hand arrangement is followed exactly', () {
    final order = [_k(_library[2]), _k(_library[0]), _k(_library[3]), _k(_library[1])];
    final out = applyShelfOrder(_library, ShelfSort.manual, order);
    expect(out.map(_k).toList(), order);
  });

  test('a book imported after arranging appends, it does not vanish', () {
    // The failure this guards: arrange by hand, sync a new book from Kindle,
    // and the new book is in no arrangement. Dropping it would lose a book from
    // the shelf; inserting it at a random index would look like a glitch.
    final order = [_k(_library[0]), _k(_library[1])];
    final grown = [..._library, _b('Zorba il greco', 'Kazantzakis')];
    final out = applyShelfOrder(grown, ShelfSort.manual, order);

    expect(out.length, grown.length);
    expect(out.take(2).map(_k).toList(), order,
        reason: 'the hand-arranged books moved');
    // The newcomers follow, alphabetically, so the result is deterministic.
    expect(out.skip(2).map((e) => e.title).toList(),
        ['Cosmos', 'Il Gattopardo', 'Zorba il greco']);
  });

  test('a stale arrangement naming books that are gone still works', () {
    // Books get deleted; the saved order keeps their keys. A lookup that
    // assumed every key still exists would throw and take the profile with it.
    final out = applyShelfOrder(
      _library,
      ShelfSort.manual,
      ['un libro cancellato|nessuno', _k(_library[3])],
    );
    expect(out.length, _library.length);
    expect(out.first.title, 'Cosmos');
  });

  test('the persisted names match what the database will accept', () {
    // sort_mode has a CHECK constraint in migration 078; a name that drifts here
    // makes every save fail at the server with a constraint violation.
    const allowed = {
      'title', 'author', 'color', 'most_highlighted', 'recent', 'manual'
    };
    for (final s in ShelfSort.values) {
      expect(allowed, contains(shelfSortName(s)));
      expect(shelfSortFromName(shelfSortName(s)), s,
          reason: 'the name does not round-trip');
    }
  });

  test('an unknown stored mode falls back instead of throwing', () {
    // A shelf saved by a newer build must not crash an older one.
    expect(shelfSortFromName('by_smell'), ShelfSort.title);
    expect(shelfSortFromName(null), ShelfSort.title);
  });

  test('the count aggregate is read in every shape the server sends', () {
    // fetchMyBooks returns a PostgREST embedded aggregate; the RPC path returns
    // a flat int the service re-wraps. Both must land on the same number, or a
    // visitor's spines would all be equally thin.
    expect(shelfMarksOf({'highlights': [{'count': 7}]}), 7);
    expect(shelfMarksOf({'highlights': {'count': 7}}), 7);
    expect(shelfMarksOf({'highlights': []}), 0);
    expect(shelfMarksOf({}), 0);
  });
}
