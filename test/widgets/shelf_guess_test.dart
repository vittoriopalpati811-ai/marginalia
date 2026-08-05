import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/features/library/shelf_guess_card.dart';

// The playable shelf reads its books straight out of a post row that came from
// the network, so the parser has to survive whatever is in that column — and
// the answer must be derived from the very counts the spines are drawn from,
// never stored separately where the two could disagree.

Map<String, dynamic> _post(Object? payload) => {'payload': payload};

Map<String, dynamic> _shelf({
  String question = 'guess',
  List<Map<String, dynamic>>? books,
  int? total,
}) =>
    {
      'type': 'shelf_guess',
      'question': question,
      if (total != null) 'total': total,
      'books': books ??
          [
            {'t': 'Il barone rampante', 'a': 'Italo Calvino', 'm': 4},
            {'t': 'Cent\'anni di solitudine', 'a': 'Gabriel Garcia Marquez', 'm': 30},
            {'t': 'Stoner', 'a': 'John Williams', 'm': 11},
          ],
    };

void main() {
  group('payload parsing', () {
    test('reads a well-formed shelf post', () {
      final data = shelfGuessFromPost(_post(_shelf(total: 43)));
      expect(data, isNotNull);
      expect(data!.entries.length, 3);
      expect(data.playable, isTrue);
      expect(data.totalBooks, 43);
    });

    test('ignores posts that are not shelves', () {
      expect(shelfGuessFromPost(_post(null)), isNull);
      expect(shelfGuessFromPost(const {}), isNull);
      expect(shelfGuessFromPost(_post({'type': 'something_else'})), isNull);
      expect(shelfGuessFromPost(_post('not a map')), isNull);
    });

    test('survives a malformed or empty book list', () {
      expect(shelfGuessFromPost(_post(_shelf(books: []))), isNull);
      // Entries without a title are dropped, not rendered blank.
      final data = shelfGuessFromPost(_post(_shelf(books: [
        {'t': '', 'a': 'Nessuno', 'm': 3},
        {'t': 'Vero', 'a': 'Autore', 'm': 5},
      ])));
      expect(data!.entries.length, 1);
      expect(data.entries.single.title, 'Vero');
    });

    test('a missing highlight count is zero, not a crash', () {
      final data = shelfGuessFromPost(_post(_shelf(books: [
        {'t': 'Senza conteggio', 'a': 'A'},
        {'t': 'Con conteggio', 'a': 'B', 'm': 7},
      ])));
      expect(data!.entries.first.highlightCount, 0);
      expect(data.answerIndex, 1);
    });

    test('only the guess prompt is playable', () {
      expect(shelfGuessFromPost(_post(_shelf()))!.playable, isTrue);
      expect(shelfGuessFromPost(_post(_shelf(question: 'next')))!.playable,
          isFalse);
      expect(shelfGuessFromPost(_post(_shelf(question: 'none')))!.playable,
          isFalse);
    });
  });

  group('the answer', () {
    test('is the most-highlighted book, wherever it sits', () {
      final data = shelfGuessFromPost(_post(_shelf()))!;
      expect(data.answerIndex, 1);
      expect(data.entries[data.answerIndex].title, 'Cent\'anni di solitudine');
    });

    test('is derived from the same counts the spines are drawn from', () {
      // Reordering the books moves the answer with them — nothing is pinned to
      // a stored index that could drift out of step with the shelf.
      final data = shelfGuessFromPost(_post(_shelf(books: [
        {'t': 'Il piu segnato', 'a': 'A', 'm': 99},
        {'t': 'Poco segnato', 'a': 'B', 'm': 1},
      ])))!;
      expect(data.answerIndex, 0);
    });

    test('a tie resolves to the first, never to a crash', () {
      final data = shelfGuessFromPost(_post(_shelf(books: [
        {'t': 'Primo', 'a': 'A', 'm': 8},
        {'t': 'Secondo', 'a': 'B', 'm': 8},
      ])))!;
      expect(data.answerIndex, 0);
    });

    test('a single-book shelf still has an answer', () {
      final data = shelfGuessFromPost(_post(_shelf(books: [
        {'t': 'Unico', 'a': 'A', 'm': 2},
      ])))!;
      expect(data.answerIndex, 0);
    });
  });
}
