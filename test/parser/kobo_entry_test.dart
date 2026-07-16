import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/parser/my_clippings_parser.dart';
import 'package:scripta/core/services/clippings_importer.dart';

// Regression for the Kobo import collapsing same-book highlights: entries
// used to carry NO location, and the importer dedups on book+location, so
// every highlight after the first matched the null-location row and was
// dropped. buildKoboEntry must give each entry a stable content-hash location.
void main() {
  test('two same-book Kobo highlights keep distinct non-null locations', () {
    final e1 = buildKoboEntry(
      title: 'Il deserto dei Tartari',
      author: 'Dino Buzzati',
      text: 'Da quel giorno misterioso la vita della Fortezza parve fermarsi.',
      date: '2026-07-10T21:00:00',
    );
    final e2 = buildKoboEntry(
      title: 'Il deserto dei Tartari',
      author: 'Dino Buzzati',
      text: 'E intanto il tempo passava, sempre piu veloce.',
      date: '2026-07-11T09:30:00',
    );

    final parsed = MyClippingsParser().parse('$e1\n==========\n$e2\n==========\n');

    expect(parsed.length, 2);
    expect(parsed[0].bookTitle, 'Il deserto dei Tartari');
    expect(parsed[0].bookTitle, parsed[1].bookTitle);
    expect(parsed[0].location, isNotNull);
    expect(parsed[1].location, isNotNull);
    expect(parsed[0].location, isNot(parsed[1].location));
  });

  test('re-importing the same Kobo highlight yields the same location', () {
    String entry() => buildKoboEntry(
          title: 'Meditations',
          author: 'Marcus Aurelius',
          text: 'You have power over your mind.',
        );
    final a = MyClippingsParser().parse('${entry()}\n==========\n').single;
    final b = MyClippingsParser().parse('${entry()}\n==========\n').single;
    expect(a.location, b.location);
  });

  test('author parentheses are sanitised so the entry still parses', () {
    final e = buildKoboEntry(
      title: 'Norwegian Wood',
      author: 'Haruki Murakami (trad. Giorgio Amitrano)',
      text: 'Nessuna verita puo lenire il dolore di perdere chi amiamo.',
    );
    final parsed = MyClippingsParser().parse('$e\n==========\n');
    expect(parsed.length, 1);
    expect(parsed.single.bookTitle, 'Norwegian Wood');
    expect(parsed.single.bookAuthor, contains('Murakami'));
  });
}
