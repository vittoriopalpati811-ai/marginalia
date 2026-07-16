import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/generated/app_localizations_en.dart';
import 'package:scripta/generated/app_localizations_it.dart';

// gen-l10n generates positional params in ALPHABETICAL placeholder order,
// so the signature is importSuccess(books, highlights) even though the
// message reads "{highlights} highlight da {books} libri". This locks the
// order so a regen or a "natural-looking" call-site swap fails loudly.
void main() {
  test('importSuccess fills (books, highlights) into the right slots', () {
    expect(
      AppLocalizationsIt().importSuccess(1, 2),
      'Importati 2 highlight da 1 libri',
    );
    expect(
      AppLocalizationsEn().importSuccess(1, 2),
      'Imported 2 highlights from 1 books',
    );
  });
}
