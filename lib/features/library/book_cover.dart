import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colour palettes ──────────────────────────────────────────────────────────

class _Palette {
  const _Palette({
    required this.base,
    required this.accent,
    required this.text,
  });
  final Color base;
  final Color accent;
  final Color text;
}

const _kPalettes = <_Palette>[
  // ── Editorial darks (original 8) — for the "Penguin Classics" mood ────
  _Palette(base: Color(0xFF1A3A2A), accent: Color(0xFF6DB88A), text: Color(0xFFF2EDE4)), // 0  Forest
  _Palette(base: Color(0xFF3A1A1A), accent: Color(0xFFC98D8D), text: Color(0xFFF2EDE4)), // 1  Burgundy
  _Palette(base: Color(0xFF1A2A3A), accent: Color(0xFF8DAEC9), text: Color(0xFFF2EDE4)), // 2  Navy
  _Palette(base: Color(0xFF3A2A0A), accent: Color(0xFFC9A84C), text: Color(0xFFF2EDE4)), // 3  Amber
  _Palette(base: Color(0xFF24243A), accent: Color(0xFF9B9BD4), text: Color(0xFFF2EDE4)), // 4  Slate
  _Palette(base: Color(0xFF3A1F0A), accent: Color(0xFFC97A4C), text: Color(0xFFF2EDE4)), // 5  Terracotta
  _Palette(base: Color(0xFF2A0A3A), accent: Color(0xFFA84CC9), text: Color(0xFFF2EDE4)), // 6  Plum
  _Palette(base: Color(0xFF0A3A2A), accent: Color(0xFF4CC9A8), text: Color(0xFFF2EDE4)), // 7  Emerald

  // ── Vibrant solids (new 8) — for the "Standards Manual / Nickel Boys"
  //    mood: large flat color block + cream text + small accent shape ───
  _Palette(base: Color(0xFFB54B3A), accent: Color(0xFFE9D9C7), text: Color(0xFFF2EDE4)), // 8  Vermillion
  _Palette(base: Color(0xFFD89D2C), accent: Color(0xFF1B1814), text: Color(0xFF1B1814)), // 9  Saffron-on-cream
  _Palette(base: Color(0xFF4A7A35), accent: Color(0xFFF5EFE0), text: Color(0xFFF5EFE0)), // 10 Matcha
  _Palette(base: Color(0xFFEB6FA5), accent: Color(0xFF231F1A), text: Color(0xFFFCF7F0)), // 11 Coral-pink
  _Palette(base: Color(0xFF2B5F9E), accent: Color(0xFFFFD23F), text: Color(0xFFF2EDE4)), // 12 Cobalt
  _Palette(base: Color(0xFF0F5C56), accent: Color(0xFFE8D5A0), text: Color(0xFFF5EFE0)), // 13 Petrol
  _Palette(base: Color(0xFFF2C94C), accent: Color(0xFF1B1814), text: Color(0xFF1B1814)), // 14 Yellow on ink
  _Palette(base: Color(0xFFEDE7DE), accent: Color(0xFFB54B3A), text: Color(0xFF1B1814)), // 15 Bone (light cover)
];

// ─── Public widget ────────────────────────────────────────────────────────────

/// Deterministic editorial book cover — no network, no async.
/// Hash is derived entirely from [title] so covers are stable across builds.
class BookEditorialCover extends StatelessWidget {
  const BookEditorialCover({
    super.key,
    required this.title,
    required this.author,
    this.borderRadius = BorderRadius.zero,
  });

  final String title;
  final String author;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    // Mix title + author hash so two books with the same first letter
    // don't clump into the same palette/style. xor scatters bits well.
    final hash    = (title.hashCode ^ (author.hashCode << 1)).abs();
    final palette = _kPalettes[hash % _kPalettes.length];
    final style   = (hash >> 3) % 7;       // 7 styles now
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '?';

    final Widget cover;
    switch (style) {
      case 0:
        cover = _PenguinCover(palette: palette, initial: initial, title: title, author: author);
      case 1:
        cover = _NordicCover(palette: palette, initial: initial, title: title, author: author);
      case 2:
        cover = _SwissCover(palette: palette, initial: initial, title: title, author: author);
      case 3:
        cover = _DiagonalCover(palette: palette, initial: initial, title: title, author: author);
      case 4:
        cover = _FrameCover(palette: palette, initial: initial, title: title, author: author);
      case 5:
        // "Standards Manual" style — flat colour + offset accent disc.
        cover = _DiscCover(palette: palette, title: title, author: author, hash: hash);
      default:
        // "Nickel Boys" style — flat colour + small silhouette accent.
        cover = _BlockCover(palette: palette, title: title, author: author, hash: hash);
    }

    return ClipRRect(borderRadius: borderRadius, child: cover);
  }
}

// ─── Style 0 — Penguin (three horizontal bands + circle initial) ──────────────

class _PenguinCover extends StatelessWidget {
  const _PenguinCover({
    required this.palette,
    required this.initial,
    required this.title,
    required this.author,
  });
  final _Palette palette;
  final String initial;
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h       = c.maxHeight;
      final w       = c.maxWidth;
      final topH    = h * 0.30;
      final midH    = h * 0.40;
      final botH    = h - topH - midH;
      final circleR = math.min(w, midH) * 0.33;

      return Stack(children: [
        // ── bands
        Positioned(top: 0,              left: 0, right: 0, height: topH, child: Container(color: palette.base)),
        Positioned(top: topH,           left: 0, right: 0, height: midH, child: Container(color: palette.accent)),
        Positioned(top: topH + midH,   left: 0, right: 0, height: botH, child: Container(color: palette.base)),

        // ── thin rules
        Positioned(top: topH - 1,      left: 0, right: 0, height: 2,
          child: Container(color: palette.text.withAlpha(60))),
        Positioned(top: topH + midH - 1, left: 0, right: 0, height: 2,
          child: Container(color: palette.text.withAlpha(60))),

        // ── circle + initial in middle band
        Positioned(
          top:  topH + midH * 0.5 - circleR,
          left: w * 0.5 - circleR,
          width: circleR * 2,
          height: circleR * 2,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.base,
              border: Border.all(color: palette.text.withAlpha(100), width: 1.2),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: GoogleFonts.ebGaramond(
                fontSize: circleR * 0.95,
                fontWeight: FontWeight.w600,
                color: palette.text,
                height: 1,
              ),
            ),
          ),
        ),

        // ── title in top band
        Positioned(
          top: 0, height: topH, left: 10, right: 10,
          child: Center(
            child: Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: math.min(10.0, topH * 0.20),
                fontWeight: FontWeight.w700,
                color: palette.text,
                letterSpacing: 1.4,
                height: 1.3,
              ),
            ),
          ),
        ),

        // ── author in bottom band
        Positioned(
          bottom: 0, height: botH, left: 10, right: 10,
          child: Center(
            child: Text(
              _lastName(author).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: math.min(8.0, botH * 0.18),
                fontWeight: FontWeight.w500,
                color: palette.text.withAlpha(160),
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

// ─── Style 1 — Nordic (large faint initial + editorial title) ─────────────────

class _NordicCover extends StatelessWidget {
  const _NordicCover({
    required this.palette,
    required this.initial,
    required this.title,
    required this.author,
  });
  final _Palette palette;
  final String initial;
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight;
      return Stack(children: [
        // Dark base
        Container(color: palette.base),

        // Giant faint initial — bleeds off left edge intentionally
        Positioned(
          top: h * 0.04,
          left: -h * 0.06,
          child: Text(
            initial,
            style: GoogleFonts.ebGaramond(
              fontSize: h * 0.72,
              color: palette.accent.withAlpha(30),
              height: 1,
            ),
          ),
        ),

        // Accent rule
        Positioned(
          top: h * 0.44, left: 14, right: 14, height: 1,
          child: Container(color: palette.accent.withAlpha(150)),
        ),

        // Title below rule
        Positioned(
          top: h * 0.48, left: 14, right: 14,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ebGaramond(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: palette.text,
              height: 1.45,
            ),
          ),
        ),

        // Author bottom-left
        Positioned(
          bottom: 13, left: 14, right: 14,
          child: Text(
            _lastName(author).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: palette.accent,
              letterSpacing: 2.2,
            ),
          ),
        ),
      ]);
    });
  }
}

// ─── Style 2 — Swiss (top dark block + bold title + dot-grid texture) ─────────

class _SwissCover extends StatelessWidget {
  const _SwissCover({
    required this.palette,
    required this.initial,
    required this.title,
    required this.author,
  });
  final _Palette palette;
  final String initial;
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h   = c.maxHeight;
      final w   = c.maxWidth;
      final topH = h * 0.42;

      return Stack(children: [
        // Light bottom background (warm cream tint)
        Container(color: _lightenedBg(palette.accent)),

        // Dark top block
        Positioned(
          top: 0, left: 0, right: 0, height: topH,
          child: Container(color: palette.base),
        ),

        // Accent rule at break
        Positioned(
          top: topH, left: 0, right: 0, height: 3,
          child: Container(color: palette.accent),
        ),

        // Title in the dark top block
        Positioned(
          top: 10, left: 12, right: 10,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: palette.text,
              height: 1.18,
              letterSpacing: -0.3,
            ),
          ),
        ),

        // Big faint initial watermark in bottom half
        Positioned(
          top: topH + 4, left: 6,
          child: Text(
            initial,
            style: GoogleFonts.ebGaramond(
              fontSize: h * 0.34,
              color: palette.base.withAlpha(22),
              height: 1,
            ),
          ),
        ),

        // Dot-grid texture — bottom-right corner
        Positioned(
          bottom: 20, right: 10,
          child: SizedBox(
            width: math.min(w * 0.35, 40),
            height: math.min(h * 0.18, 40),
            child: CustomPaint(
              painter: _DotGridPainter(color: palette.base.withAlpha(35)),
            ),
          ),
        ),

        // Author bottom-right
        Positioned(
          bottom: 11, right: 12,
          child: Text(
            _lastName(author).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: GoogleFonts.manrope(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: palette.base.withAlpha(130),
              letterSpacing: 1.8,
            ),
          ),
        ),
      ]);
    });
  }

  // Pastel-light accent as cover bg
  static Color _lightenedBg(Color accent) {
    final r = (accent.red   * 0.10 + 236).round().clamp(0, 255);
    final g = (accent.green * 0.10 + 230).round().clamp(0, 255);
    final b = (accent.blue  * 0.10 + 224).round().clamp(0, 255);
    return Color.fromARGB(255, r, g, b);
  }
}

// ─── Style 3 — Diagonal (triangle CustomPainter + large initial) ─────────────

class _DiagonalCover extends StatelessWidget {
  const _DiagonalCover({
    required this.palette,
    required this.initial,
    required this.title,
    required this.author,
  });
  final _Palette palette;
  final String initial;
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight;
      return Stack(children: [
        // Dark base
        Container(color: palette.base),

        // Diagonal accent triangle (bottom-right)
        Positioned.fill(
          child: CustomPaint(
            painter: _DiagPainter(color: palette.accent.withAlpha(185)),
          ),
        ),

        // Large initial — top-left
        Positioned(
          top: 4, left: 6,
          child: Text(
            initial,
            style: GoogleFonts.ebGaramond(
              fontSize: h * 0.40,
              fontWeight: FontWeight.w600,
              color: palette.text.withAlpha(215),
              height: 1,
            ),
          ),
        ),

        // Title above footer
        Positioned(
          bottom: 34, left: 12, right: 12,
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ebGaramond(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: palette.text,
              height: 1.38,
            ),
          ),
        ),

        // Author at very bottom
        Positioned(
          bottom: 12, left: 12, right: 12,
          child: Text(
            _lastName(author).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 7.5,
              fontWeight: FontWeight.w600,
              color: palette.text.withAlpha(150),
              letterSpacing: 2.0,
            ),
          ),
        ),
      ]);
    });
  }
}

// ─── Style 4 — Frame (double inset RRect border + centered Garamond title) ────

class _FrameCover extends StatelessWidget {
  const _FrameCover({
    required this.palette,
    required this.initial,
    required this.title,
    required this.author,
  });
  final _Palette palette;
  final String initial;
  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight;
      return Stack(children: [
        // Dark base
        Container(color: palette.base),

        // Faint giant initial — bottom center
        Positioned(
          bottom: -h * 0.06, left: 0, right: 0,
          child: Center(
            child: Text(
              initial,
              style: GoogleFonts.ebGaramond(
                fontSize: h * 0.58,
                color: palette.accent.withAlpha(18),
                height: 1,
              ),
            ),
          ),
        ),

        // Double inset frame
        Positioned.fill(
          child: CustomPaint(
            painter: _FramePainter(color: palette.accent.withAlpha(160)),
          ),
        ),

        // Centered content
        Positioned(
          top: 0, bottom: 0, left: 16, right: 16,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.ebGaramond(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: palette.text,
                  height: 1.50,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                width: 28, height: 1,
                color: palette.accent.withAlpha(180),
              ),
              const SizedBox(height: 9),
              Text(
                _lastName(author).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w600,
                  color: palette.accent,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          ),
        ),
      ]);
    });
  }
}

// ─── Custom painters ──────────────────────────────────────────────────────────

class _DiagPainter extends CustomPainter {
  const _DiagPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path  = Path()
      ..moveTo(size.width, size.height * 0.38)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DiagPainter old) => old.color != color;
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(7, 7, size.width - 7, size.height - 7),
        const Radius.circular(3),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(12, 12, size.width - 12, size.height - 12),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint   = Paint()..color = color;
    const spacing = 7.0;
    const r       = 1.4;
    for (var x = r; x < size.width; x += spacing) {
      for (var y = r; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

// ─── Style 5 — Disc (flat colour + large offset disc, "Standards Manual") ────

class _DiscCover extends StatelessWidget {
  const _DiscCover({
    required this.palette,
    required this.title,
    required this.author,
    required this.hash,
  });
  final _Palette palette;
  final String title;
  final String author;
  final int hash;

  @override
  Widget build(BuildContext context) {
    // Disc position scattered by hash so every book lands the disc somewhere
    // distinctive — bleeding off the top, bottom, left or right edge.
    final corner = hash % 4;
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final discSize = h * 0.62;

      late double left, top;
      switch (corner) {
        case 0: left = -discSize * 0.28; top = -discSize * 0.20; break; // top-left
        case 1: left = w - discSize * 0.72; top = -discSize * 0.25; break; // top-right
        case 2: left = -discSize * 0.30; top = h - discSize * 0.70; break; // bottom-left
        default: left = w - discSize * 0.70; top = h - discSize * 0.75;     // bottom-right
      }

      return Stack(children: [
        Container(color: palette.base),

        // Big offset disc — the literal "Lem" / Standards Manual move.
        Positioned(
          left: left,
          top:  top,
          width:  discSize,
          height: discSize,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent,
            ),
          ),
        ),

        // Title — top-left
        Positioned(
          top: 14, left: 14, right: 14,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: palette.text,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),
        ),

        // Author — bottom
        Positioned(
          bottom: 12, left: 14, right: 14,
          child: Text(
            _lastName(author).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: palette.text.withAlpha(190),
              letterSpacing: 2.4,
            ),
          ),
        ),
      ]);
    });
  }
}

// ─── Style 6 — Block (flat colour + cut horizon block, "Nickel Boys") ────────

class _BlockCover extends StatelessWidget {
  const _BlockCover({
    required this.palette,
    required this.title,
    required this.author,
    required this.hash,
  });
  final _Palette palette;
  final String title;
  final String author;
  final int hash;

  @override
  Widget build(BuildContext context) {
    // The "block" cuts the cover into two flat zones at a random horizon
    // line — book becomes a piece of architecture instead of a typography
    // exercise. Variation by hash so books in the same palette differ.
    final horizon = 0.30 + ((hash >> 7) % 35) * 0.01; // 0.30 .. 0.65

    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight;
      final topH = h * horizon;

      return Stack(children: [
        // Top band = accent (the punchy colour)
        Positioned(
          top: 0, left: 0, right: 0, height: topH,
          child: Container(color: palette.accent),
        ),
        // Bottom band = base
        Positioned(
          top: topH, left: 0, right: 0, bottom: 0,
          child: Container(color: palette.base),
        ),

        // Title sits in the bottom (base) band, large editorial Garamond.
        Positioned(
          top: topH + 14, left: 14, right: 14,
          child: Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ebGaramond(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: palette.text,
              height: 1.22,
            ),
          ),
        ),

        // Author bottom, tiny + spaced — like a publisher imprint.
        Positioned(
          bottom: 11, left: 14, right: 14,
          child: Text(
            _lastName(author).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: palette.text.withAlpha(180),
              letterSpacing: 2.2,
            ),
          ),
        ),
      ]);
    });
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _lastName(String author) {
  final parts = author.trim().split(' ');
  return parts.isEmpty ? author : parts.last;
}
