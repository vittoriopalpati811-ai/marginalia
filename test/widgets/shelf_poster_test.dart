import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/features/library/bookshelf_view.dart';
import 'package:scripta/features/library/shelf_poster.dart';

// The poster used to show the 14 most-marked books. Founder: "nell'immagine fa
// vedere i primi libri, invece si devono vedere tutti in maniera leggibile."
// Both halves of that sentence are load-bearing, and they pull against each
// other — more books on a fixed card means smaller type. These tests pin the
// trade so a later tweak cannot quietly give one of them up.

const _titles = [
  'Il nome della rosa', "Cent'anni di solitudine", 'Anna Karenina',
  'Delitto e castigo', 'Il Gattopardo', 'La coscienza di Zeno',
  'Sapiens', 'Homo Deus', 'Atomic Habits', 'Antifragile',
  'Il cigno nero', 'Educata', 'Cosmos', 'Meditations',
  'La tregua', 'Il sistema periodico', 'Lessico famigliare',
  "L'amica geniale", 'Il vecchio e il mare', 'Il giovane Holden',
  'Il maestro e Margherita', 'Il grande Gatsby', 'Mrs Dalloway',
];

List<ShelfEntry> _library(int n) => [
      for (var i = 0; i < n; i++)
        ShelfEntry(
          title: '${_titles[i % _titles.length]} ${i ~/ _titles.length}',
          author: 'Autore $i',
          highlightCount: (i * 7) % 45,
        ),
    ];

/// The room the cabinet gets inside a 4:5 card on a 390pt phone, after the
/// header, the count headline and the signature have taken theirs.
const _room = Size(272.4, 262.0);

/// The factor the poster's FittedBox will apply — it multiplies the title's
/// point size directly, so it IS the legibility number.
double _fit(List<ShelfEntry> entries) {
  final design = posterDesignWidth(entries, _room);
  final size =
      BookshelfView.measureAt(entries, design, metrics: ShelfMetrics.poster);
  return math.min(_room.width / size.width, _room.height / size.height);
}

void main() {
  test('every book is on the poster, none dropped', () {
    for (final n in [1, 8, 14, 25, 43, 60]) {
      expect(posterSelection(_library(n)).length, n,
          reason: '$n books went in and something was left behind');
    }
  });

  test('past the safety ceiling the best-read books are the ones kept', () {
    // A 400-book account cannot be drawn legibly at any size, so there is a cap
    // — but it must drop the books barely read, never the ones lived in.
    final huge = _library(kPosterBooks + 40);
    final picked = posterSelection(huge);
    expect(picked.length, kPosterBooks);

    final keptTitles = picked.map((e) => e.title).toSet();
    final dropped = huge.where((e) => !keptTitles.contains(e.title));
    final keptMin = picked.map((e) => e.highlightCount).reduce(math.min);
    for (final d in dropped) {
      expect(d.highlightCount, lessThanOrEqualTo(keptMin),
          reason: 'dropped a book more marked than one that stayed');
    }
  });

  test('the poster is sorted alphabetically, not by highlights', () {
    // Otherwise the fattest spine is always first and the shelf gives away at a
    // glance which book was read hardest.
    final picked = posterSelection(_library(20));
    final titles = picked.map((e) => e.title.toLowerCase()).toList();
    final sorted = [...titles]..sort();
    expect(titles, sorted);
  });

  test('a whole 43-book library stays readable', () {
    // Measured floor. Before this change 43 books rendered at ~2.7pt — a smudge.
    // The adaptive design width plus the poster spine metrics roughly double it.
    // If a future tweak drops below 4.5pt, the poster has stopped being legible
    // and this is the alarm.
    final pt = 11.5 * _fit(_library(43));
    expect(pt, greaterThan(4.5), reason: 'titles shrank back to a smudge');
  });

  test('a small library is not blown up into absurdity', () {
    // scaleDown never upscales past 1.0, so eight books must not end up as
    // eight enormous spines filling the whole card.
    expect(_fit(_library(8)), lessThanOrEqualTo(1.0));
  });

  test('more books never makes the poster larger', () {
    // Monotonicity: the search picks a design width per library, and a bug in
    // it could make 43 books render bigger than 14 — which would mean the
    // smaller library was being drawn badly.
    var previous = double.infinity;
    for (final n in [8, 14, 25, 43, 60]) {
      final fit = _fit(_library(n));
      expect(fit, lessThanOrEqualTo(previous + 1e-9),
          reason: 'the poster grew when books were added ($n)');
      previous = fit;
    }
  });

  test('the chosen design width really is the best available', () {
    // The whole point of searching. If some other width fits better, the search
    // is broken and every poster is smaller than it needed to be.
    final entries = _library(43);
    final chosen = _fit(entries);
    for (var w = 240.0; w <= 1400.0; w += 20) {
      final size =
          BookshelfView.measureAt(entries, w, metrics: ShelfMetrics.poster);
      final fit =
          math.min(_room.width / size.width, _room.height / size.height);
      expect(fit, lessThanOrEqualTo(chosen + 1e-9),
          reason: 'width $w fits better than the one chosen');
    }
  });

  test('poster spines hold as long a title as the reading shelf', () {
    // Title capacity along a rotated spine is about (height - 22) / 5.29
    // characters. The poster may draw SMALLER, but it must not ellipsise a
    // title the library would have shown in full — that reads as broken.
    expect(ShelfMetrics.poster.minHeight,
        greaterThanOrEqualTo(ShelfMetrics.reading.minHeight));
  });

  test('a poster spine is never narrower than its own text line', () {
    // Below ~21.5 the rotated title overflows its spine, and in an exported PNG
    // an overflow is yellow-and-black stripes posted to Instagram.
    expect(ShelfMetrics.poster.minWidth, greaterThanOrEqualTo(24));
  });
}
