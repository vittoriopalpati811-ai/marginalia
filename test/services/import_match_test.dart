import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/services/import_match.dart';

// Duplicates are not hypothetical here. Two production accounts hold the same
// book twice — "Il nome della rosa" (5 highlights) alongside "Il Nome della
// Rosa" (21), and "Il piccolo principe" alongside "Il Piccolo Principe" —
// because the importer compared titles with exact, case-sensitive equality.
// The sync now runs by itself every six hours, so a matching rule that is
// almost right would compound on a schedule.

void main() {
  group('the same book written two ways', () {
    test('capitalisation does not make a second book', () {
      // The exact pair sitting in production today.
      expect(bookMatchKey('Il nome della rosa', 'Umberto Eco'),
          bookMatchKey('Il Nome della Rosa', 'Umberto Eco'));
      expect(bookMatchKey('Il piccolo principe', 'Antoine de Saint-Exupéry'),
          bookMatchKey('Il Piccolo Principe', 'Antoine de Saint-Exupéry'));
    });

    test('surname-first and natural order are the same author', () {
      // My Clippings.txt writes "Eco, Umberto"; the web notebook writes
      // "Umberto Eco". Without this, every Kindle sync duplicates the entire
      // library of anyone who ever imported a clippings file.
      expect(bookMatchKey('Il nome della rosa', 'Eco, Umberto'),
          bookMatchKey('Il nome della rosa', 'Umberto Eco'));
      expect(
        bookMatchKey('Il piccolo principe', 'de Saint-Exupéry, Antoine'),
        bookMatchKey('Il piccolo principe', 'Antoine de Saint-Exupéry'),
      );
    });

    test('padding and double spaces do not make a second book', () {
      expect(bookMatchKey('  Il nome  della rosa ', 'Umberto Eco'),
          bookMatchKey('Il nome della rosa', 'Umberto Eco'));
    });

    test('genuinely different books stay different', () {
      expect(bookMatchKey('Il nome della rosa', 'Umberto Eco'),
          isNot(bookMatchKey('Il pendolo di Foucault', 'Umberto Eco')));
      // Same title, different author — an anthology, or a retelling.
      expect(bookMatchKey('Il processo', 'Franz Kafka'),
          isNot(bookMatchKey('Il processo', 'Rudolf Brazda')));
    });
  });

  group('the same highlight written two ways', () {
    test('identical text is one highlight even when the locations disagree', () {
      // The clippings file gives a RANGE, the sync gives a single number.
      expect(
        isSameHighlight(
          locationA: '1234-1236',
          contentA: 'Il libro parlava di cose ridicole.',
          locationB: '1234',
          contentB: 'Il libro parlava di cose ridicole.',
        ),
        isTrue,
      );
    });

    test('a highlight Kindle re-issued with more text around it', () {
      // Same starting point, one text contains the other: the same passage,
      // extended. This is the case the "keep the longer one" rule is for.
      expect(
        isSameHighlight(
          locationA: '4792',
          contentA: 'Il sapere è come un\'arma',
          locationB: '4792-4795',
          contentB: 'Il sapere è come un\'arma: chi non la sa usare si fa male.',
        ),
        isTrue,
      );
    });

    test('two different quotes that happen to start together stay separate', () {
      // The rule that keeps this from eating people's sentences. Losing a
      // highlight is far worse than showing one twice.
      expect(
        isSameHighlight(
          locationA: '1234',
          contentA: 'Il tempo passava, sempre più veloce.',
          locationB: '1234',
          contentB: 'La speranza lo teneva legato alla Fortezza.',
        ),
        isFalse,
      );
    });

    test('different quotes in different places stay separate', () {
      expect(
        isSameHighlight(
          locationA: '10',
          contentA: 'Una frase.',
          locationB: '900',
          contentB: 'Un altra frase.',
        ),
        isFalse,
      );
    });

    test('curly and straight quotes are the same text', () {
      expect(
        isSameHighlight(
          locationA: null,
          contentA: '\u201cNon so\u201d, disse.',
          locationB: null,
          contentB: '"Non so", disse.',
        ),
        isTrue,
      );
    });
  });

  group('the fallback identity for a locationless highlight', () {
    test('is stable for the same text', () {
      expect(contentFingerprint('Una frase stabile'),
          contentFingerprint('Una frase stabile'));
    });

    test('does not depend on String.hashCode', () {
      // This value is PERSISTED and compared on every later sync. Dart does not
      // promise hashCode is stable across SDK releases, and a shift would
      // silently re-import a reader's whole locationless library.
      const text = 'Le pause sono parte della musica.';
      expect(contentFingerprint(text), isNot(text.hashCode.abs().toString()));
      expect(contentFingerprint(text), hasLength(16));
      expect(contentFingerprint(text), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('separates different texts', () {
      expect(contentFingerprint('Una frase'),
          isNot(contentFingerprint('Un altra frase')));
    });
  });

  group('locationStart', () {
    test('reads the beginning of a range', () {
      expect(locationStart('1234-1236'), '1234');
      expect(locationStart('1234'), '1234');
      expect(locationStart('pos. 4792-4795'), '4792');
    });

    test('tolerates nothing to read', () {
      expect(locationStart(null), isNull);
      expect(locationStart(''), isNull);
      expect(locationStart('sconosciuta'), isNull);
    });
  });
}
