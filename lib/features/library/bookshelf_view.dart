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

/// Highlights at which a spine reaches full thickness.
const int _kThickAt = 40;

/// Leftover space on the last shelf needed before the final book leans.
const double _kLeanThreshold = 26;

/// Breathing room between the title and the author along a spine.
const double _kTitleAuthorGap = 7;

/// The shelf board.
const double _kPlankTop = 8;   // the face the books stand on
const double _kPlankLip = 5;   // the front edge you see from slightly above

// Warm oak, muted so it sits beside the app's cream and sage instead of
// shouting over them.
const Color _kOakFace = Color(0xFFD8CDBA);
const Color _kOakLip  = Color(0xFFBCAE99);

// ─── Data ────────────────────────────────────────────────────────────────────

/// One book plus the only extra fact the shelf needs: how heavily it is marked.
class ShelfEntry {
  const ShelfEntry({required this.book, required this.highlightCount});

  final Book book;
  final int  highlightCount;
}

// ─── Public widget ───────────────────────────────────────────────────────────

class BookshelfView extends StatelessWidget {
  const BookshelfView({
    super.key,
    required this.entries,
    required this.onOpen,
  });

  final List<ShelfEntry>      entries;
  final void Function(Book)   onOpen;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final specs   = entries.map(_SpineSpec.from).toList();
        final shelves = _packIntoShelves(specs, constraints.maxWidth);

        // Free space left on the bottom shelf — the room a leaning book needs.
        // It also needs neighbours to fall against: a single book tipping over
        // on an otherwise empty shelf reads as a bug, not as a flourish.
        final last = shelves.last;
        final lastWidth = last.fold<double>(0, (sum, s) => sum + s.width) +
            _kGap * (last.length - 1);
        final leanLast = last.length >= 3 &&
            (constraints.maxWidth - lastWidth) >= _kLeanThreshold;

        var seen = 0;
        final rows = <Widget>[];
        for (var i = 0; i < shelves.length; i++) {
          rows.add(_Shelf(
            specs:       shelves[i],
            indexOffset: seen,
            leanLast:    leanLast && i == shelves.length - 1,
            onOpen:      onOpen,
          ));
          seen += shelves[i].length;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
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
    required this.book,
    required this.width,
    required this.height,
    required this.colors,
    required this.seed,
  });

  final Book       book;
  final double     width;
  final double     height;
  final BookColors colors;
  final int        seed;

  /// Every dimension is a pure function of the book, so a shelf looks the same
  /// on every rebuild, every launch and every device.
  factory _SpineSpec.from(ShelfEntry entry) {
    final book = entry.book;
    final seed = bookArtSeed(book.title, book.author);

    // Two independent pseudo-random draws from the one seed.
    double draw(int salt) => ((seed ~/ (3 + salt * 7)) % 997) / 997.0;

    final marked = math.min(entry.highlightCount, _kThickAt) / _kThickAt;

    return _SpineSpec(
      book:   book,
      // Ragged tops — the single strongest cue that these are objects.
      height: _kMinHeight + draw(1) * (_kMaxHeight - _kMinHeight),
      // Mostly "how much did I mark this", plus a little natural variation.
      width: _kMinWidth +
          draw(2) * 8 +
          marked * (_kMaxWidth - _kMinWidth - 8),
      colors: bookColorsFor(book.title, book.author),
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
    required this.onOpen,
  });

  final List<_SpineSpec>    specs;
  final int                 indexOffset;
  final bool                leanLast;
  final void Function(Book) onOpen;

  @override
  Widget build(BuildContext context) {
    final tallest = specs.fold<double>(0, (m, s) => math.max(m, s.height));

    final books = <Widget>[];
    for (var i = 0; i < specs.length; i++) {
      if (i > 0) books.add(const SizedBox(width: _kGap));

      final isLeaner = leanLast && i == specs.length - 1;
      Widget spine = _Spine(
        spec:  specs[i],
        index: indexOffset + i,
        onTap: () => onOpen(specs[i].book),
      );

      if (isLeaner) {
        // Nothing to its right holds it up, so it tips LEFT onto its
        // neighbours, pivoting on the bottom corner that stays planted.
        spine = Transform.rotate(
          angle: -0.085,
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
          const _Plank(),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

// ─── The board ───────────────────────────────────────────────────────────────

class _Plank extends StatelessWidget {
  const _Plank();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kPlankTop + _kPlankLip,
      child: CustomPaint(painter: _PlankPainter(), child: const SizedBox.expand()),
    );
  }
}

class _PlankPainter extends CustomPainter {
  // The shadow the books cast where they meet the board.
  static const _contact = LinearGradient(
    begin: Alignment.topCenter,
    end:   Alignment.bottomCenter,
    colors: [Color(0x1F1B1F1B), Color(0x001B1F1B)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(2.5);

    // Board face — the plane the books rest on.
    final face = Rect.fromLTWH(0, 0, size.width, _kPlankTop);
    canvas.drawRRect(
      RRect.fromRectAndCorners(face, topLeft: radius, topRight: radius),
      Paint()..color = _kOakFace,
    );

    // Front edge — one darker band is all the depth this needs.
    final lip = Rect.fromLTWH(0, _kPlankTop, size.width, _kPlankLip);
    canvas.drawRRect(
      RRect.fromRectAndCorners(lip,
          bottomLeft: radius, bottomRight: radius),
      Paint()..color = _kOakLip,
    );

    // Contact shadow, only across the top third of the face.
    final shade = Rect.fromLTWH(0, 0, size.width, _kPlankTop * 0.62);
    canvas.drawRect(shade, Paint()..shader = _contact.createShader(shade));

    // Two grain lines. Any more and it stops being furniture and starts
    // being texture for its own sake.
    final grain = Paint()
      ..color = ScriptaColors.ink.withAlpha(12)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(size.width * 0.08, _kPlankTop * 0.72),
      Offset(size.width * 0.62, _kPlankTop * 0.72),
      grain,
    );
    canvas.drawLine(
      Offset(size.width * 0.55, _kPlankTop * 0.42),
      Offset(size.width * 0.94, _kPlankTop * 0.42),
      grain,
    );
  }

  @override
  bool shouldRepaint(covariant _PlankPainter oldDelegate) => false;
}

// ─── One spine ───────────────────────────────────────────────────────────────

class _Spine extends StatelessWidget {
  const _Spine({
    required this.spec,
    required this.index,
    required this.onTap,
  });

  final _SpineSpec  spec;
  final int         index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = spec.book;
    final ink  = _readableInk(spec.colors.base);

    final title   = book.title.trim();
    final surname = _surname(book.author);

    final titleStyle = GoogleFonts.ebGaramond(
      fontSize: 11.5,
      height: 1.0,
      fontWeight: FontWeight.w600,
      color: ink,
      letterSpacing: 0.1,
    );
    final authorStyle = GoogleFonts.manrope(
      fontSize: 7.5,
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
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 5),
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
                final showAuthor = surname.isNotEmpty &&
                    _measure(title, titleStyle) +
                            _kTitleAuthorGap +
                            _measure(surname, authorStyle) <=
                        box.maxWidth;

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
                      const SizedBox(width: _kTitleAuthorGap),
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
