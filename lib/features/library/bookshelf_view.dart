// ─── Bookshelf — the library seen edge-on, as spines on a shelf ─────────────
//
// A second way to look at the same books the grid shows. The grid answers
// "which book is this?" (cover art, big and flat); the shelf answers "what have
// I read?" — the whole library in one glance, the way it would look on a wall.
//
// Design rules, so this reads as a designed object and not as clip-art:
//
//   1. NOTHING IS UNIFORM. Real shelves are ragged: every spine gets its own
//      height and thickness, derived deterministically from the book so it
//      never reshuffles between rebuilds. A row of identical rounded
//      rectangles is the giveaway of a generated bookshelf — this has none.
//   2. THE COLOURS ARE THE BOOK'S OWN. A spine is dressed in the exact palette
//      its generated cover paints with (`bookColorsFor`), so a book is the same
//      colour in the grid and on the shelf. No second, competing identity.
//   3. THICKNESS MEANS SOMETHING. A book you highlighted forty times stands
//      visibly fatter than one you barely marked. The shelf becomes a picture
//      of how you read, not merely of what you own.
//   4. VOLUME, NOT DECORATION. Each spine carries one horizontal shading pass
//      (a spine is a curved surface, darker where it turns away from the light)
//      and two hinge creases. That is what makes a rectangle read as an object.
//      No bevels, no glows, no drop-shadow stacks.
//   5. ONE DELIBERATE IMPERFECTION. When the last shelf has room left over, the
//      final book leans into its neighbours — exactly what a real book does
//      when nothing holds it up. It is the detail that stops the row from
//      looking machine-set.
//
// Tapping a spine opens the same book detail the grid opens.
//
// One deliberate asymmetry with the grid: a book carrying a REAL cover image
// (a Kindle scrape or a user upload) still gets its generated palette here,
// not a colour sampled from that image. Sampling means decoding every cover
// off the network before the shelf can lay out — a flicker, then a repaint, on
// every scroll. And it is not even more truthful: a printed spine is rarely the
// same colour as the front board. The mood palette is stable, instant, and
// already the book's colour everywhere else it appears without art.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/book.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/theme.dart';
import 'book_cover.dart';

// ─── Tunables ────────────────────────────────────────────────────────────────

/// Books touch on a real shelf; a hairline keeps their edges legible.
const double _kGap = 2.0;

/// Spine height range. Tight enough to look tidy, loose enough to look real.
/// Also the title's canvas: a real hardback is roughly four to five times
/// taller than it is thick, and at that proportion most titles fit along the
/// spine without being cut — a shelf of "Il Pendol…" reads as broken, not busy.
const double _kMinHeight = 146;
const double _kMaxHeight = 192;

/// Spine thickness range: a barely-marked book vs. one you lived inside.
const double _kMinWidth = 30;
const double _kMaxWidth = 52;

/// How big a spine is, so one shelf can be built to different ends.
///
/// The reading shelf wants generous spines. The shareable poster has to fit an
/// ENTIRE library — forty-odd books — into one card and keep the titles
/// readable, which is a different trade: slimmer, slightly shorter spines, more
/// per row, fewer rows. These were constants shared by both, so tuning the
/// poster silently shrank the library; they are a value object now.
///
/// Two floors are structural, not taste:
///   • [minWidth] must stay ≥ 24. Inside a spine the title is rotated, so the
///     spine's WIDTH becomes the text line's tight cross-axis: font 11.5 plus
///     2×5 padding needs 21.5, and below that the row overflows — which in an
///     exported PNG shows up as yellow-and-black stripes posted to Instagram,
///     not as a console warning.
///   • [minHeight] must stay ≥ ~130. Title capacity is about
///     `(height − 22) / 5.29` characters; below 130 real titles start
///     ellipsising, which is exactly what the height range exists to prevent.
class ShelfMetrics {
  const ShelfMetrics({
    this.minHeight = _kMinHeight,
    this.maxHeight = _kMaxHeight,
    this.minWidth  = _kMinWidth,
    this.maxWidth  = _kMaxWidth,
  });

  /// The reading shelf: library and profile.
  static const ShelfMetrics reading = ShelfMetrics();

  /// The poster, which has to hold a WHOLE library on one card.
  ///
  /// Slimmer spines, which is where the room comes from: more books per row
  /// means fewer rows and less shrinking. Height is deliberately NOT cut as far
  /// — measured, dropping the floor to 138 buys only 5% more rendered size and
  /// costs 1.5 characters of title, so [minHeight] is held at the reading value
  /// and no title ellipsises on a poster that would have fitted in the library.
  /// Still 1.36× thick-to-thin, so a heavily marked book still reads as fatter.
  static const ShelfMetrics poster = ShelfMetrics(
    minHeight: 146,
    maxHeight: 172,
    minWidth:  25,
    maxWidth:  34,
  );

  final double minHeight;
  final double maxHeight;
  final double minWidth;
  final double maxWidth;
}

/// Highlights at which a spine reaches full thickness.
const int _kThickAt = 40;

/// How far the last book tips when nothing holds it up, in radians.
const double _kLeanAngle = 0.085;

/// Horizontal distance a leaning spine's head travels left of where it would
/// stand upright. `Transform.rotate` does not take part in layout, so this is
/// also exactly the room that must be RESERVED beside it — otherwise the head
/// sweeps straight through its neighbour instead of coming to rest on it.
double _leanSweep(double height, double width) =>
    height * math.sin(_kLeanAngle) - width * (1 - math.cos(_kLeanAngle));

/// Breathing room between the title and the author along a spine.
const double _kTitleAuthorGap = 7;

// ─── The cabinet ─────────────────────────────────────────────────────────────
//
// The books do not float on loose planks any more: they stand inside a piece of
// furniture. Dark walnut, because pastel spines need something to sit against —
// on cream they drifted; against wood they read as objects on a shelf.
//
// Realistic, but built the way the rest of the app is built: flat planes, one
// light direction, grain suggested with a few low-alpha strokes rather than a
// photographic texture. No gloss, no bevel stacks, no drop-shadow pile.

/// Board the books stand on, and the front edge of it you see from below.
const double _kBoardTop = 7;
const double _kBoardLip = 4;

/// The carcass: uprights either side, a rail on top, a deeper plinth beneath.
const double _kStile   = 11;
const double _kTopRail = 10;
const double _kPlinth  = 14;

/// Breathing room between the uprights and the first/last book.
const double _kInnerPad = 5;

// Walnut, warm and reddish, lit from above-left.
const Color _kWalnutFace   = Color(0xFF4A3327); // stiles and rails
const Color _kWalnutLit    = Color(0xFF5E4433); // the edge catching light
const Color _kWalnutDeep   = Color(0xFF33231A); // where wood turns away
const Color _kCabinetBack  = Color(0xFF2A1E18); // the interior, in shade
const Color _kBoardFace    = Color(0xFF57402E); // top of a shelf board
const Color _kBoardEdge    = Color(0xFF3C2B20); // its front edge

// ─── Data ────────────────────────────────────────────────────────────────────

/// One book plus the only extra fact the shelf needs: how heavily it is marked.
///
/// Deliberately NOT an Isar `Book`. The same shelf is drawn from the local
/// library and from a post's payload in someone else's feed, and the second
/// case has no database rows to hand — only a title, an author and a count.
class ShelfEntry {
  const ShelfEntry({
    required this.title,
    required this.author,
    required this.highlightCount,
    this.bookId,
  });

  /// Builds an entry from a local library book.
  ShelfEntry.fromBook(Book book, this.highlightCount)
      : title  = book.title,
        author = book.author,
        bookId = book.id;

  final String title;
  final String author;
  final int    highlightCount;

  /// Local Isar id, when this shelf was built from the user's own library.
  /// Null for a shelf reconstructed from a post.
  final int? bookId;
}

// ─── Public widget ───────────────────────────────────────────────────────────

class BookshelfView extends StatelessWidget {
  const BookshelfView({
    super.key,
    required this.entries,
    required this.onTap,
    this.scale = 1.0,
    this.metrics = ShelfMetrics.reading,
  });

  final List<ShelfEntry> entries;

  /// Called with the position of the spine that was touched. Position, not the
  /// book, because a playable shelf cares about WHICH one you picked.
  final void Function(int index, ShelfEntry entry) onTap;

  /// Shrinks the whole shelf proportionally. 1.0 is the reading size used in
  /// the library; the shareable poster packs more books into less room.
  final double scale;

  /// How big the spines are. Defaults to the reading size; the poster passes
  /// [ShelfMetrics.poster] so a whole library fits without shrinking the
  /// library's own shelf.
  final ShelfMetrics metrics;


  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Books are packed against the INSIDE of the carcass, not the widget's
        // full width — the uprights own the rest.
        final interior = constraints.maxWidth -
            2 * _kStile * scale -
            2 * _kInnerPad * scale;

        final specs = entries
            .map((e) => _SpineSpec.from(e, scale: scale, metrics: metrics))
            .toList();
        final shelves = _packIntoShelves(specs, interior);

        // Free space left on the bottom shelf — the room a leaning book needs.
        // It also needs neighbours to fall against: a single book tipping over
        // on an otherwise empty shelf reads as a bug, not as a flourish.
        final last = shelves.last;
        final lastWidth = last.fold<double>(0, (sum, s) => sum + s.width) +
            _kGap * (last.length - 1);
        // It may only tip if the board can actually give it the room the tilt
        // needs; otherwise it would lean through the book beside it.
        final leanRoom = _leanSweep(last.last.height, last.last.width) + 6;
        final leanLast =
            last.length >= 3 && (interior - lastWidth) >= leanRoom;

        var seen = 0;
        final rows = <Widget>[];
        for (var i = 0; i < shelves.length; i++) {
          rows.add(_Shelf(
            specs:       shelves[i],
            indexOffset: seen,
            leanLast:    leanLast && i == shelves.length - 1,
            onTap:       onTap,
            scale:       scale,
            isLast:      i == shelves.length - 1,
          ));
          seen += shelves[i].length;
        }

        return _Cabinet(scale: scale, rows: rows);
      },
    );
  }

  /// What this shelf would MEASURE at [designWidth], without building it.
  ///
  /// The poster needs this to answer a question it cannot answer by trying: at
  /// which design width does a whole library end up largest on a fixed card?
  /// Wider means more books per row and fewer rows — a squat cabinet that runs
  /// out of horizontal room — while narrower means a tall thin one that runs out
  /// of vertical room. The best width is where the cabinet's proportions match
  /// the space it has to fit into, and finding it means measuring several.
  ///
  /// Always in design units at scale 1.0; the caller scales the result.
  static Size measureAt(
    List<ShelfEntry> entries,
    double designWidth, {
    ShelfMetrics metrics = ShelfMetrics.reading,
  }) {
    if (entries.isEmpty) return Size.zero;

    final interior = designWidth - 2 * _kStile - 2 * _kInnerPad;
    final specs = entries
        .map((e) => _SpineSpec.from(e, metrics: metrics))
        .toList();
    final shelves = _packIntoShelves(specs, interior);

    // Mirrors _Cabinet + _Shelf exactly: a rail on top, a plinth beneath, and
    // per row the tallest spine, its board, and a gap under all but the last.
    var height = _kTopRail + _kPlinth;
    for (var i = 0; i < shelves.length; i++) {
      final tallest = shelves[i].fold<double>(0, (m, s) => math.max(m, s.height));
      height += tallest + _kBoardTop + _kBoardLip;
      if (i != shelves.length - 1) height += 16;
    }
    return Size(designWidth, height);
  }

  /// Greedy left-to-right packing. Leftover space stays on the RIGHT of each
  /// shelf — books lean left against each other, they do not justify edge to
  /// edge like text.
  static List<List<_SpineSpec>> _packIntoShelves(
    List<_SpineSpec> specs,
    double maxWidth,
  ) {
    final shelves = <List<_SpineSpec>>[];
    var current   = <_SpineSpec>[];
    var used      = 0.0;

    for (final spec in specs) {
      final needed = current.isEmpty ? spec.width : spec.width + _kGap;
      if (current.isNotEmpty && used + needed > maxWidth) {
        shelves.add(current);
        current = [spec];
        used    = spec.width;
      } else {
        current.add(spec);
        used += needed;
      }
    }
    if (current.isNotEmpty) shelves.add(current);

    // Widow control. One book alone on the bottom board reads as a mistake
    // rather than as a shelf, so books are pulled down from the row above until
    // it has company — the same instinct that stops a typographer leaving a
    // single word on the last line. Never at the cost of overflowing the row,
    // and never by gutting the row above.
    if (shelves.length >= 2) {
      final last = shelves.last;
      final prev = shelves[shelves.length - 2];
      while (last.length < 3 && prev.length > 3) {
        final candidate = prev.last;
        final widthWithCandidate =
            last.fold<double>(0, (sum, s) => sum + s.width) +
                candidate.width +
                _kGap * last.length;
        if (widthWithCandidate > maxWidth) break;
        prev.removeLast();
        last.insert(0, candidate);
      }
    }
    return shelves;
  }
}

// ─── Spine metrics ───────────────────────────────────────────────────────────

class _SpineSpec {
  const _SpineSpec({
    required this.entry,
    required this.width,
    required this.height,
    required this.colors,
    required this.seed,
  });

  final ShelfEntry entry;
  final double     width;
  final double     height;
  final BookColors colors;
  final int        seed;

  /// Every dimension is a pure function of the book, so a shelf looks the same
  /// on every rebuild, every launch and every device.
  factory _SpineSpec.from(
    ShelfEntry entry, {
    double scale = 1.0,
    ShelfMetrics metrics = ShelfMetrics.reading,
  }) {
    final seed = bookArtSeed(entry.title, entry.author);

    // Two independent pseudo-random draws from the one seed.
    double draw(int salt) => ((seed ~/ (3 + salt * 7)) % 997) / 997.0;

    final marked = math.min(entry.highlightCount, _kThickAt) / _kThickAt;

    // The natural-variation slice of the width, kept proportional to the range
    // so a slim poster spine doesn't spend most of its thickness on noise and
    // lose the "thickness means highlights" signal entirely.
    final range = metrics.maxWidth - metrics.minWidth;
    final jitter = range * 0.36;

    return _SpineSpec(
      entry: entry,
      // Ragged tops — the single strongest cue that these are objects.
      height:
          (metrics.minHeight + draw(1) * (metrics.maxHeight - metrics.minHeight)) *
              scale,
      // Mostly "how much did I mark this", plus a little natural variation.
      width: (metrics.minWidth + draw(2) * jitter + marked * (range - jitter)) *
          scale,
      colors: bookColorsFor(entry.title, entry.author),
      seed:   seed,
    );
  }
}

// ─── One shelf: the books, then the board they stand on ──────────────────────

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.specs,
    required this.indexOffset,
    required this.leanLast,
    required this.onTap,
    required this.scale,
    required this.isLast,
  });

  final List<_SpineSpec> specs;
  final int              indexOffset;
  final bool             leanLast;
  final void Function(int index, ShelfEntry entry) onTap;
  final double           scale;

  /// The bottom row sits straight on the plinth, so it needs no gap under it.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tallest = specs.fold<double>(0, (m, s) => math.max(m, s.height));

    final books = <Widget>[];
    for (var i = 0; i < specs.length; i++) {
      final isLeaner = leanLast && i == specs.length - 1;

      if (i > 0) {
        // A leaning book's foot slides away from the stack while its head comes
        // to REST against the neighbour. Reserving the sweep is what turns an
        // overlap — a book slicing through the one beside it — into contact.
        books.add(SizedBox(
          width: isLeaner
              ? math.max(_kGap, _leanSweep(specs[i].height, specs[i].width))
              : _kGap,
        ));
      }

      final globalIndex = indexOffset + i;
      Widget spine = _Spine(
        spec:  specs[i],
        index: globalIndex,
        scale: scale,
        onTap: () => onTap(globalIndex, specs[i].entry),
      );

      if (isLeaner) {
        // Nothing to its right holds it up, so it tips LEFT onto its
        // neighbours, pivoting on the bottom corner that stays planted.
        spine = Transform.rotate(
          angle: -_kLeanAngle,
          alignment: Alignment.bottomRight,
          child: spine,
        );
      }
      books.add(spine);
    }

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: tallest,
            // Every book stands ON the board, whatever its height.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: books,
            ),
          ),
          _ShelfBoard(scale: scale),
          if (!isLast) SizedBox(height: 16 * scale),
        ],
      ),
    );
  }
}

// ─── The carcass ─────────────────────────────────────────────────────────────

class _Cabinet extends StatelessWidget {
  const _Cabinet({required this.scale, required this.rows});

  final double       scale;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7 * scale),
        // One soft shadow, the same language as every card in the app — a piece
        // of furniture standing on the page, not a sticker on it.
        boxShadow: [
          BoxShadow(
            color: ScriptaColors.ink.withAlpha(38),
            blurRadius: 18 * scale,
            offset: Offset(0, 6 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7 * scale),
        child: CustomPaint(
          painter: _CarcassPainter(scale: scale),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              (_kStile + _kInnerPad) * scale,
              _kTopRail * scale,
              (_kStile + _kInnerPad) * scale,
              _kPlinth * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the walnut box the books live in: the interior in shade, the uprights
/// and rails around it, and just enough grain to read as sawn wood.
class _CarcassPainter extends CustomPainter {
  _CarcassPainter({required this.scale});

  final double scale;

  /// Deterministic wobble so the grain is the same every frame — a shelf that
  /// reshuffles its wood grain on scroll is worse than no grain at all.
  double _n(int i) => ((i * 2654435761) % 1000) / 1000.0;

  @override
  void paint(Canvas canvas, Size size) {
    final stile   = _kStile * scale;
    final topRail = _kTopRail * scale;
    final plinth  = _kPlinth * scale;

    // 1 — the carcass, solid walnut.
    canvas.drawRect(Offset.zero & size, Paint()..color = _kWalnutFace);

    // 2 — grain. Long strokes with the run of the wood: vertical down the
    //     uprights, horizontal along the rails. Low alpha, never a pattern.
    final grain = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 7; i++) {
      final x = stile * (0.18 + 0.62 * _n(i * 3 + 1));
      grain
        ..color = (i.isEven ? _kWalnutDeep : _kWalnutLit).withAlpha(46)
        ..strokeWidth = (0.7 + _n(i) * 0.9) * scale;
      canvas.drawLine(Offset(x, topRail * 0.4),
          Offset(x + (_n(i + 9) - 0.5) * 3, size.height - plinth * 0.3), grain);
      canvas.drawLine(Offset(size.width - x, topRail * 0.5),
          Offset(size.width - x + (_n(i + 4) - 0.5) * 3,
              size.height - plinth * 0.4), grain);
    }
    for (var i = 0; i < 3; i++) {
      final y = topRail * (0.25 + 0.5 * _n(i + 21));
      grain
        ..color = _kWalnutDeep.withAlpha(40)
        ..strokeWidth = 0.8 * scale;
      canvas.drawLine(Offset(size.width * 0.1 * _n(i + 5), y),
          Offset(size.width * (0.55 + 0.4 * _n(i + 7)), y), grain);
    }

    // 3 — the interior, in shade: the inside of a cabinet never catches the
    //     light its front does.
    final inside = Rect.fromLTRB(
      stile,
      topRail,
      size.width - stile,
      size.height - plinth,
    );
    canvas.drawRect(inside, Paint()..color = _kCabinetBack);

    // 4 — the reveal where the carcass turns into the opening: a lit edge on
    //     the top and left, a dark one opposite. This single pair of lines is
    //     what makes the box read as having depth.
    final lit = Paint()
      ..color = _kWalnutLit.withAlpha(190)
      ..strokeWidth = 1.2 * scale;
    canvas.drawLine(inside.topLeft, inside.topRight, lit);
    canvas.drawLine(inside.topLeft, inside.bottomLeft, lit);

    final dark = Paint()
      ..color = _kWalnutDeep
      ..strokeWidth = 1.2 * scale;
    canvas.drawLine(inside.topRight, inside.bottomRight, dark);

    // 5 — the plinth catches light along its top edge.
    canvas.drawLine(
      Offset(0, size.height - plinth),
      Offset(size.width, size.height - plinth),
      Paint()
        ..color = _kWalnutLit.withAlpha(150)
        ..strokeWidth = 1 * scale,
    );

    // 6 — the interior darkens into its corners, the way an unlit box does.
    canvas.drawRect(
      inside,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [
            const Color(0x00000000),
            const Color(0x59000000),
          ],
        ).createShader(inside),
    );
  }

  @override
  bool shouldRepaint(covariant _CarcassPainter old) => old.scale != scale;
}

// ─── A shelf board inside the carcass ────────────────────────────────────────

class _ShelfBoard extends StatelessWidget {
  const _ShelfBoard({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (_kBoardTop + _kBoardLip) * scale,
      child: CustomPaint(
        painter: _BoardPainter(scale: scale),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.scale});

  final double scale;

  /// The shadow the books cast where they meet the board.
  static const _contact = LinearGradient(
    begin: Alignment.topCenter,
    end:   Alignment.bottomCenter,
    colors: [Color(0x4A000000), Color(0x00000000)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final top = _kBoardTop * scale;

    // The board runs wall to wall — it is jointed into the uprights, not a
    // plank resting in mid-air, so it has no rounded ends.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, top),
      Paint()..color = _kBoardFace,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, size.height - top),
      Paint()..color = _kBoardEdge,
    );

    // Where the books stand.
    final shade = Rect.fromLTWH(0, 0, size.width, top * 0.6);
    canvas.drawRect(shade, Paint()..shader = _contact.createShader(shade));

    // The front edge catches the light.
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()
        ..color = _kWalnutLit.withAlpha(120)
        ..strokeWidth = 0.9 * scale,
    );

    // Two strokes of grain along the run of the board.
    final grain = Paint()
      ..color = _kWalnutDeep.withAlpha(60)
      ..strokeWidth = 0.7 * scale;
    canvas.drawLine(Offset(size.width * 0.06, top * 0.68),
        Offset(size.width * 0.58, top * 0.68), grain);
    canvas.drawLine(Offset(size.width * 0.52, top * 0.34),
        Offset(size.width * 0.95, top * 0.34), grain);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => old.scale != scale;
}

// ─── One spine ───────────────────────────────────────────────────────────────

class _Spine extends StatelessWidget {
  const _Spine({
    required this.spec,
    required this.index,
    required this.scale,
    required this.onTap,
  });

  final _SpineSpec  spec;
  final int         index;
  final double      scale;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final book = spec.entry;
    final ink  = _readableInk(spec.colors.base);

    final title   = book.title.trim();
    final surname = _surname(book.author);

    final titleStyle = GoogleFonts.ebGaramond(
      fontSize: 11.5 * scale,
      height: 1.0,
      fontWeight: FontWeight.w600,
      color: ink,
      letterSpacing: 0.1,
    );
    final authorStyle = GoogleFonts.manrope(
      fontSize: 7.5 * scale,
      height: 1.0,
      fontWeight: FontWeight.w600,
      color: ink.withAlpha(150),
      letterSpacing: 0.4,
    );

    final spine = SizedBox(
      width:  spec.width,
      height: spec.height,
      child: CustomPaint(
        painter: _SpinePainter(
          base:   _deepenIfPale(spec.colors.base),
          accent: spec.colors.accent,
          seed:   spec.seed,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: 11 * scale, horizontal: 5 * scale),
          // Bottom-to-top, the way spines are set on Italian shelves.
          child: RotatedBox(
            quarterTurns: 3,
            // Inside the rotation the constraints are swapped, so maxWidth here
            // is the usable LENGTH of the spine.
            child: LayoutBuilder(
              builder: (context, box) {
                // The title always wins the spine. The author is printed only
                // when both still fit whole — measured, not guessed, because a
                // clipped "Anna Kareni…" trades away the one thing the shelf
                // exists to show. Two text layouts per spine; nothing compared
                // to what a scroll frame does anyway.
                // The 3px margin keeps a name off the very edge: measuring to
                // the exact pixel let a final letter clip when the laid-out
                // width landed a hair over the boundary.
                final showAuthor = surname.isNotEmpty &&
                    _measure(title, titleStyle) +
                            _kTitleAuthorGap * scale +
                            _measure(surname, authorStyle) <=
                        box.maxWidth - 3;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    if (showAuthor) ...[
                      SizedBox(width: _kTitleAuthorGap * scale),
                      // NOT Flexible. Two flexible children split the spine
                      // evenly, which cut "Il Nome della Rosa" in half to make
                      // room for three letters of "Eco". The title is the one
                      // that may shrink; the name takes the width it needs, and
                      // it is only ever printed once both have been measured to
                      // fit whole.
                      Text(surname, maxLines: 1, style: authorStyle),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: '${book.title}, ${book.author}',
      child: PressableSpring(
        onPressed: onTap,
        child: spine,
      ),
    )
        // The books slide up onto the shelf, first ones first. Capped so a
        // fifty-book library still finishes settling in well under a second.
        .animate(delay: Duration(milliseconds: math.min(index * 22, 420)))
        .fadeIn(duration: AirbnbMotion.standard)
        .slideY(begin: 0.16, end: 0, curve: AirbnbMotion.enter);
  }

  /// Dark ink on a light cloth, cream on a dark one — whichever the spine can
  /// actually be read against. Both are warm, never pure black or white.
  static Color _readableInk(Color base) => base.computeLuminance() > 0.45
      ? const Color(0xFF2B2A26)
      : const Color(0xFFF3F0E6);

  /// A few cover palettes are near-white. Left alone they dissolve into the
  /// cream page; a touch of depth keeps them objects on a shelf.
  static Color _deepenIfPale(Color base) {
    if (base.computeLuminance() <= 0.86) return base;
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness - 0.07).clamp(0.0, 1.0)).toColor();
  }

  /// Spines carry the surname. "Italo Calvino" → "Calvino".
  static String _surname(String author) {
    final trimmed = author.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.last;
  }

  /// Laid-out width of a single line — the honest answer to "does this fit?".
  static double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _SpinePainter extends CustomPainter {
  _SpinePainter({
    required this.base,
    required this.accent,
    required this.seed,
  });

  final Color base;
  final Color accent;
  final int   seed;

  /// A spine is a curved surface: it turns away from the light at both edges.
  /// This one pass is what separates a book from a coloured rectangle.
  static const _volume = LinearGradient(
    begin: Alignment.centerLeft,
    end:   Alignment.centerRight,
    colors: [
      Color(0x26000000),
      Color(0x00000000),
      Color(0x00000000),
      Color(0x1A000000),
    ],
    stops: [0.0, 0.17, 0.73, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Heads are rounded, feet sit square on the board.
    final body = RRect.fromRectAndCorners(
      rect,
      topLeft:     const Radius.circular(3.5),
      topRight:    const Radius.circular(3.5),
      bottomLeft:  const Radius.circular(1),
      bottomRight: const Radius.circular(1),
    );

    canvas.save();
    canvas.clipRRect(body);

    canvas.drawRect(rect, Paint()..color = base);
    canvas.drawRect(rect, Paint()..shader = _volume.createShader(rect));

    // The two creases where the boards hinge onto the spine.
    final hinge = Paint()
      ..color = const Color(0xFF000000).withAlpha(24)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(3.5, 5), Offset(3.5, size.height), hinge);
    canvas.drawLine(
        Offset(size.width - 3.5, 5), Offset(size.width - 3.5, size.height), hinge);

    // Roughly half the shelf is bound with gilt rules at head and tail — the
    // variety is deterministic, so a given book always binds the same way.
    if (seed % 2 == 0) {
      final band = Paint()..color = accent.withAlpha(190);
      final inset = size.width * 0.16;
      final w = size.width - inset * 2;
      canvas.drawRect(Rect.fromLTWH(inset, size.height * 0.085, w, 1.6), band);
      canvas.drawRect(Rect.fromLTWH(inset, size.height * 0.885, w, 1.6), band);
    }

    canvas.restore();

    // Edge definition, so even a pale spine reads as its own object.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ScriptaColors.ink.withAlpha(30),
    );
  }

  @override
  bool shouldRepaint(covariant _SpinePainter old) =>
      old.base != base || old.accent != accent || old.seed != seed;
}
