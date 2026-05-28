// ─── Marginalia Editions cover system ────────────────────────────────────────
//
// Designed top-down to read as a *series* — every book in the library is a
// volume of "Marginalia Editions". Constants imprint at the top, tripartite
// grid (imprint → middle → author), Bodoni Moda + Manrope across the board,
// 14-colour palette curated to feel like a single publisher's catalogue.
//
// Six variants share that scaffold but execute very different visual moves:
//
//   1. Spine       — pure typography, two horizontal rules
//   2. Disc        — flat colour + large disc bleeding off one corner
//   3. Banner      — top band in a paler tone + giant fade-out numeral
//   4. Silhouette  — one organic shape (leaf / eye / arch / mountain)
//   5. Frame       — double inset rectangle, centred title + ornament
//   6. Numeral     — Vignelli-style massive book number, title in small caps
//
// Selection is deterministic from `title.hashCode ^ (author.hashCode << 1)`
// so the same book gets the same cover across devices and reinstalls, but
// two books with the same first letter still differ.
//
// No external API calls. CustomPaint for shapes, Text widgets for type.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────

class _Palette {
  const _Palette(this.bg, this.fg, this.label);
  final Color  bg;
  final Color  fg;
  final String label; // for debugging only
}

const _kInkCream  = Color(0xFFF5EFE0);
const _kInkInk    = Color(0xFF1B1814);

const _kPalettes = <_Palette>[
  // G1 — Saturated solids (cream text)
  _Palette(Color(0xFFC2392A), _kInkCream, 'Vermillion'),
  _Palette(Color(0xFFD9A41C), _kInkInk,   'Saffron'),    // intentionally ink-on-yellow
  _Palette(Color(0xFF2A5DA4), _kInkCream, 'Cobalt'),
  _Palette(Color(0xFF0F5C56), _kInkCream, 'Petrol'),
  _Palette(Color(0xFF6D1F3E), _kInkCream, 'Plum'),
  _Palette(Color(0xFFB57F2D), _kInkCream, 'Ochre'),
  _Palette(Color(0xFF2E5230), _kInkCream, 'Forest'),
  _Palette(Color(0xFF1B1814), _kInkCream, 'Ink'),
  // G2 — Pale-but-bold (ink text)
  _Palette(Color(0xFFECE5D7), _kInkInk,   'Bone'),
  _Palette(Color(0xFFE8DFC8), _kInkInk,   'Linen'),
  _Palette(Color(0xFFB8C7A5), _kInkInk,   'Sage'),
  _Palette(Color(0xFFE8B89F), _kInkInk,   'Coral'),
  _Palette(Color(0xFFB8C5CC), _kInkInk,   'Mist'),
  _Palette(Color(0xFFE8D38E), _kInkInk,   'Sunbutter'),
];

// ─── Public widget ────────────────────────────────────────────────────────────

/// Deterministic editorial book cover — no network, no async.
/// Variant + palette + edition number derive from `title` and `author`.
class BookEditorialCover extends StatelessWidget {
  const BookEditorialCover({
    super.key,
    required this.title,
    required this.author,
    this.borderRadius = BorderRadius.zero,
  });

  final String       title;
  final String       author;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final hash      = (title.hashCode ^ (author.hashCode << 1)).abs();
    final palette   = _kPalettes[hash % _kPalettes.length];
    final variant   = (hash >> 4) % 6;
    // 3-digit "edition number" pinned by hash. Pad to 3 chars so all books
    // look like they belong to the same catalogue ("042", "317", "008").
    final editionNo = (hash % 999 + 1).toString().padLeft(3, '0');

    final Widget cover;
    switch (variant) {
      case 0:
        cover = _SpineVariant(p: palette, title: title, author: author, no: editionNo);
      case 1:
        cover = _DiscVariant(p: palette, title: title, author: author, no: editionNo, hash: hash);
      case 2:
        cover = _BannerVariant(p: palette, title: title, author: author, no: editionNo);
      case 3:
        cover = _SilhouetteVariant(p: palette, title: title, author: author, no: editionNo, hash: hash);
      case 4:
        cover = _FrameVariant(p: palette, title: title, author: author, no: editionNo);
      default:
        cover = _NumeralVariant(p: palette, title: title, author: author, no: editionNo);
    }

    return ClipRRect(borderRadius: borderRadius, child: cover);
  }
}

// ─── Shared chrome (imprint + author + rule) ─────────────────────────────────
//
// Every variant uses the same top-imprint and bottom-author treatment so the
// library reads as a coherent series. Pass `scale` so the same widget works
// at 80×120 (grid) and 200×300 (detail) without recalculating sizes
// per variant.

class _Imprint extends StatelessWidget {
  const _Imprint({required this.p, required this.no, this.scale = 1.0});
  final _Palette p;
  final String   no;
  final double   scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      'MARGINALIA EDITIONS · $no',
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: GoogleFonts.manrope(
        fontSize: 8 * scale,
        fontWeight: FontWeight.w800,
        color: p.fg.withAlpha(180),
        letterSpacing: 1.8 * scale,
        height: 1,
      ),
    );
  }
}

class _AuthorLine extends StatelessWidget {
  const _AuthorLine({
    required this.p,
    required this.author,
    this.scale = 1.0,
    this.align = TextAlign.left,
  });
  final _Palette  p;
  final String    author;
  final double    scale;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      _spreadCaps(_lastName(author)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: GoogleFonts.manrope(
        fontSize: 8.5 * scale,
        fontWeight: FontWeight.w700,
        color: p.fg,
        letterSpacing: 2.4 * scale,
        height: 1,
      ),
    );
  }
}

class _ThinRule extends StatelessWidget {
  const _ThinRule({required this.p});
  final _Palette p;

  @override
  Widget build(BuildContext context) => Container(height: 0.7, color: p.fg.withAlpha(120));
}

// ─── Variant 1 — Spine (pure type) ────────────────────────────────────────────

class _SpineVariant extends StatelessWidget {
  const _SpineVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final scale = (c.maxHeight / 240).clamp(0.55, 1.4);
      final pad   = 14.0 * scale;
      return Container(
        color: p.bg,
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Imprint(p: p, no: no, scale: scale),
            SizedBox(height: 6 * scale),
            _ThinRule(p: p),
            const Spacer(),
            Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.bodoniModa(
                fontSize: 17 * scale,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: p.fg,
                height: 1.16,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 6 * scale),
            const Spacer(),
            _ThinRule(p: p),
            SizedBox(height: 8 * scale),
            _AuthorLine(p: p, author: author, scale: scale),
          ],
        ),
      );
    });
  }
}

// ─── Variant 2 — Disc (giant flat disc bleeding off corner) ──────────────────

class _DiscVariant extends StatelessWidget {
  const _DiscVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
    required this.hash,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;
  final int      hash;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final w     = c.maxWidth;
      final h     = c.maxHeight;
      final scale = (h / 240).clamp(0.55, 1.4);
      final pad   = 14.0 * scale;
      final r     = h * 0.42; // disc radius

      // Disc corner: 0 TL, 1 TR, 2 BL, 3 BR
      final corner = hash % 4;
      late double left, top;
      switch (corner) {
        case 0: left = -r * 0.55; top = -r * 0.40; break;
        case 1: left = w - r * 1.45; top = -r * 0.45; break;
        case 2: left = -r * 0.60; top = h - r * 1.60; break;
        default: left = w - r * 1.40; top = h - r * 1.50;
      }

      return Stack(children: [
        Container(color: p.bg),
        Positioned(
          left: left,
          top:  top,
          width:  r * 2,
          height: r * 2,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.fg.withAlpha(225),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Imprint(p: p, no: no, scale: scale),
              const Spacer(),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bodoniModa(
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w600,
                  color: p.fg,
                  height: 1.12,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 10 * scale),
              _AuthorLine(p: p, author: author, scale: scale),
            ],
          ),
        ),
      ]);
    });
  }
}

// ─── Variant 3 — Banner (top band + faded numeral) ───────────────────────────

class _BannerVariant extends StatelessWidget {
  const _BannerVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h       = c.maxHeight;
      final scale   = (h / 240).clamp(0.55, 1.4);
      final pad     = 14.0 * scale;
      final bandH   = h * 0.32;
      final bandClr = _lightenBg(p.bg, p.fg);

      return Stack(children: [
        Container(color: p.bg),
        Positioned(
          top: 0, left: 0, right: 0, height: bandH,
          child: Container(color: bandClr),
        ),

        // Faded edition number in lower 2/3
        Positioned(
          top: bandH + (h - bandH) * 0.10,
          left: 0, right: 0,
          child: Center(
            child: Text(
              no,
              style: GoogleFonts.bodoniModa(
                fontSize: h * 0.42,
                fontWeight: FontWeight.w400,
                color: p.fg.withAlpha(28),
                height: 1,
              ),
            ),
          ),
        ),

        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imprint sits inside the top band — ink colour for contrast.
              Text(
                'MARGINALIA EDITIONS · $no',
                maxLines: 1,
                style: GoogleFonts.manrope(
                  fontSize: 8 * scale,
                  fontWeight: FontWeight.w800,
                  color: _kInkInk.withAlpha(170),
                  letterSpacing: 1.8 * scale,
                  height: 1,
                ),
              ),
              SizedBox(height: 6 * scale),
              SizedBox(
                height: bandH - pad - 10 * scale,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.bodoniModa(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                      color: _kInkInk,
                      height: 1.14,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _ThinRule(p: p),
              SizedBox(height: 8 * scale),
              _AuthorLine(p: p, author: author, scale: scale),
            ],
          ),
        ),
      ]);
    });
  }
}

// ─── Variant 4 — Silhouette (one organic white shape) ────────────────────────

class _SilhouetteVariant extends StatelessWidget {
  const _SilhouetteVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
    required this.hash,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;
  final int      hash;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h     = c.maxHeight;
      final scale = (h / 240).clamp(0.55, 1.4);
      final pad   = 14.0 * scale;
      final shapeIdx = hash % 4;

      return Stack(children: [
        Container(color: p.bg),

        // The hero shape sits in the central middle 50% area.
        Positioned(
          top: h * 0.22, left: 0, right: 0, height: h * 0.50,
          child: CustomPaint(painter: _SilhouettePainter(
            color: p.fg.withAlpha(230),
            shapeIdx: shapeIdx,
          )),
        ),

        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Imprint(p: p, no: no, scale: scale),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bodoniModa(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: p.fg,
                  height: 1.16,
                ),
              ),
              SizedBox(height: 8 * scale),
              _AuthorLine(p: p, author: author, scale: scale),
            ],
          ),
        ),
      ]);
    });
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({required this.color, required this.shapeIdx});
  final Color color;
  final int   shapeIdx;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..isAntiAlias = true;
    final w = size.width;
    final h = size.height;

    final path = Path();
    switch (shapeIdx) {
      case 0: // Leaf (vertical almond, like a sycamore key)
        final cx = w / 2;
        path
          ..moveTo(cx, 0)
          ..quadraticBezierTo(w * 0.95, h * 0.50, cx, h)
          ..quadraticBezierTo(w * 0.05, h * 0.50, cx, 0)
          ..close();
        canvas.drawPath(path, paint);
        // Center vein
        final vein = Paint()
          ..color = Colors.transparent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0;
        canvas.drawLine(Offset(cx, h * 0.06), Offset(cx, h * 0.94), vein);
        break;

      case 1: // Eye / almond shape, horizontal
        final cy = h / 2;
        path
          ..moveTo(0, cy)
          ..quadraticBezierTo(w * 0.5, -h * 0.10, w, cy)
          ..quadraticBezierTo(w * 0.5, h * 1.10, 0, cy)
          ..close();
        canvas.drawPath(path, paint);
        // Iris
        canvas.drawCircle(Offset(w * 0.5, cy), h * 0.18, Paint()..color = Colors.transparent);
        break;

      case 2: // Doorway / archway
        final left  = w * 0.25;
        final right = w * 0.75;
        final base  = h * 0.95;
        final top   = h * 0.18;
        path
          ..moveTo(left, base)
          ..lineTo(left, h * 0.42)
          ..quadraticBezierTo(left, top, w / 2, top)
          ..quadraticBezierTo(right, top, right, h * 0.42)
          ..lineTo(right, base)
          ..close();
        canvas.drawPath(path, paint);
        break;

      default: // Mountain — two overlapping triangles
        path
          ..moveTo(w * 0.05, h * 0.85)
          ..lineTo(w * 0.42, h * 0.18)
          ..lineTo(w * 0.62, h * 0.55)
          ..lineTo(w * 0.95, h * 0.85)
          ..close();
        canvas.drawPath(path, paint);
        // smaller foothill
        final p2 = Path()
          ..moveTo(w * 0.30, h * 0.85)
          ..lineTo(w * 0.55, h * 0.42)
          ..lineTo(w * 0.78, h * 0.85)
          ..close();
        canvas.drawPath(p2, paint..color = color.withAlpha(160));
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.color != color || old.shapeIdx != shapeIdx;
}

// ─── Variant 5 — Frame (double inset, centred title, ornament) ───────────────

class _FrameVariant extends StatelessWidget {
  const _FrameVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h     = c.maxHeight;
      final scale = (h / 240).clamp(0.55, 1.4);

      return Stack(children: [
        Container(color: p.bg),
        Positioned.fill(
          child: CustomPaint(painter: _FramePainter(color: p.fg.withAlpha(150))),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 18 * scale),
          child: Column(
            children: [
              _Imprint(p: p, no: no, scale: scale),
              const Spacer(),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.bodoniModa(
                  fontSize: 17 * scale,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: p.fg,
                  height: 1.20,
                ),
              ),
              SizedBox(height: 8 * scale),
              Text(
                '·',
                style: GoogleFonts.bodoniModa(
                  fontSize: 16 * scale,
                  color: p.fg.withAlpha(200),
                ),
              ),
              SizedBox(height: 6 * scale),
              _AuthorLine(p: p, author: author, scale: scale, align: TextAlign.center),
              const Spacer(),
            ],
          ),
        ),
      ]);
    });
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(
      Rect.fromLTRB(7, 7, size.width - 7, size.height - 7), paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(11, 11, size.width - 11, size.height - 11), paint,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

// ─── Variant 6 — Numeral (Vignelli subway-sign book number) ──────────────────

class _NumeralVariant extends StatelessWidget {
  const _NumeralVariant({
    required this.p,
    required this.title,
    required this.author,
    required this.no,
  });
  final _Palette p;
  final String   title;
  final String   author;
  final String   no;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h     = c.maxHeight;
      final scale = (h / 240).clamp(0.55, 1.4);
      final pad   = 14.0 * scale;

      return Container(
        color: p.bg,
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top: imprint + title in small caps
            _Imprint(p: p, no: no, scale: scale),
            SizedBox(height: 6 * scale),
            _ThinRule(p: p),
            SizedBox(height: 8 * scale),
            Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 9.5 * scale,
                fontWeight: FontWeight.w800,
                color: p.fg,
                letterSpacing: 1.2 * scale,
                height: 1.3,
              ),
            ),

            // The number takes the centre
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    no,
                    style: GoogleFonts.bodoniModa(
                      fontSize: 180,
                      fontWeight: FontWeight.w500,
                      color: p.fg,
                      height: 1,
                      letterSpacing: -6,
                    ),
                  ),
                ),
              ),
            ),

            // Bottom: rule + author
            SizedBox(height: 8 * scale),
            _ThinRule(p: p),
            SizedBox(height: 8 * scale),
            _AuthorLine(p: p, author: author, scale: scale),
          ],
        ),
      );
    });
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _lastName(String author) {
  final parts = author.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return author;
  return parts.last;
}

/// Spreads a name out in caps with single-space tracking — typical
/// publisher-imprint treatment of an author surname on a Penguin spine.
String _spreadCaps(String s) {
  final clean = s.toUpperCase();
  return clean.split('').join(' ');
}

/// Mixes the background colour toward the text colour so the banner / band
/// reads as a softer version of the hero, never a totally separate hue.
Color _lightenBg(Color bg, Color fg) {
  // If fg is cream, lighten toward cream; if fg is ink, deepen toward ink.
  final t = 0.78; // how strongly we move toward fg
  return Color.fromARGB(
    255,
    (bg.red   * (1 - t) + fg.red   * t).round().clamp(0, 255),
    (bg.green * (1 - t) + fg.green * t).round().clamp(0, 255),
    (bg.blue  * (1 - t) + fg.blue  * t).round().clamp(0, 255),
  );
}
