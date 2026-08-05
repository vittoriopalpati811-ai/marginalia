import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scripta/core/parser/my_clippings_parser.dart';
import 'package:scripta/core/services/amazon_sync_service.dart';

// Kindle-synced highlights reach the library by being serialised into My
// Clippings text and fed through the ordinary importer. Two things in that
// serialisation were quietly destroying data, and both are locked down here.

AmazonHighlight _h(String content, {String? location}) => AmazonHighlight(
      bookTitle: 'Il deserto dei Tartari',
      bookAuthor: 'Dino Buzzati',
      content: content,
      location: location,
    );

void main() {
  setUpAll(() async {
    // The entry writes an English long-form date; the parser needs the locale
    // data to read it back.
    await initializeDateFormatting('en_US');
  });

  test('highlights with no location stay separate highlights', () {
    // Regression: the entry wrote `location 0` whenever Amazon gave none. The
    // importer dedups on (book, location), so an entire book collapsed to its
    // single longest highlight and the rest disappeared without any error.
    final text = amazonHighlightsToClippingsText([
      _h('Da quel giorno la vita della Fortezza parve fermarsi.'),
      _h('E intanto il tempo passava, sempre piu veloce.'),
      _h('La speranza lo teneva legato alla Fortezza.'),
    ]);

    final parsed = MyClippingsParser().parse(text);

    expect(parsed.length, 3, reason: 'highlights collapsed into one another');
    final locations = parsed.map((c) => c.location).toSet();
    expect(locations.length, 3, reason: 'locations were not distinct');
    expect(locations.contains('0'), isFalse);
  });

  test('a real Amazon location is used as-is', () {
    final parsed = MyClippingsParser()
        .parse(amazonHighlightsToClippingsText([_h('Una frase', location: '1234')]));
    expect(parsed.single.location, '1234');
  });

  test('re-syncing the same highlight keeps the same location', () {
    // What makes an unattended repeat sync safe: identical input must produce
    // an identical dedup key, or every background run would duplicate the
    // whole library.
    String locOf() => MyClippingsParser()
        .parse(amazonHighlightsToClippingsText([_h('Una frase stabile')]))
        .single
        .location!;
    expect(locOf(), locOf());
  });

  test('the date is written in a shape the parser can actually read', () {
    // Regression: a raw `DateTime.now()` ("2026-08-05 12:34:56.789012") matched
    // none of the parser's formats, so every Kindle highlight landed with a
    // null date — and the reading-session stats are derived from that date.
    final parsed = MyClippingsParser()
        .parse(amazonHighlightsToClippingsText([_h('Una frase', location: '7')]));

    expect(parsed.single.addedAt, isNotNull,
        reason: 'the Added on line did not parse');
    expect(
      parsed.single.addedAt!.difference(DateTime.now()).abs().inMinutes,
      lessThan(5),
      reason: 'the parsed date is not roughly now',
    );
  });

  test('a book with no author still survives the round trip', () {
    // MyClippingsParser drops any entry whose first line has no "(...)", so an
    // authorless book must fall back to a placeholder rather than vanish.
    final text = amazonHighlightsToClippingsText([
      const AmazonHighlight(
        bookTitle: 'Senza autore',
        bookAuthor: '',
        content: 'Una frase orfana',
        location: '12',
      ),
    ]);
    final parsed = MyClippingsParser().parse(text);
    expect(parsed.length, 1);
    expect(parsed.single.bookTitle, 'Senza autore');
  });
}
