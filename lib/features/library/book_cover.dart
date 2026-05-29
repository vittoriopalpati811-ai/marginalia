// ─── Book cover — Philographics-inspired mood art ──────────────────────────
//
// Reference: Genis Carreras' "Philographics" poster series — one bold,
// saturated background colour per concept, with a single geometric
// composition (circle, X, triangle, plus, domino chain, venn, grid…)
// that *visually rhymes* with the concept. Minimal but never timid.
//
// User direction:
//   "Modifica le immagini di copertina prendendo di riferimento queste
//    immagini, rendi le copertine più dinamiche e più diversificate tra
//    loro evitando ripetizioni tra le copertine."
//
// Cover catalogue:
//   • 11 moods (mapped to ~70 famous books + keyword fallback)
//   • 3 palette variants per mood (33 distinct palettes total) — pure-
//     saturated reds for fiery, ink-black/wine for dark, dusty rose for
//     romantic, etc. Hash picks the variant so two books of the same
//     mood don't necessarily share a palette.
//   • 20 compositions — each mood lists 6–8 compatible compositions,
//     hash picks one. With 11 moods × 6 compositions × 3 palettes ≈
//     200 unique outputs, a 30-book library should land on essentially
//     no duplicates.
//
// The cover never renders the book title or author — the surrounding
// card (library_screen, profile, book_detail) handles that.

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Moods
// ═══════════════════════════════════════════════════════════════════════════

enum _Mood {
  fiery,         // Inferno, war, fire
  dark,          // 1984, Kafka, Delitto e castigo
  romantic,      // Austen, Anna Karenina
  gentle,        // Il piccolo principe, I promessi sposi
  melancholic,   // Cent'anni, Pessoa, Buzzati
  adventurous,   // Don Chisciotte, Tolkien, Verne
  mystical,      // Bulgakov, Eco Foucault, Borges
  intellectual,  // Calvino, Eco Rosa, Pirandello
  natural,       // Hesse Siddhartha, Walden
  contemplative, // Il vecchio e il mare, Camus
  celestial,     // Star / sky / night books
}

class _Palette {
  const _Palette({
    required this.bg,
    required this.ink,
    required this.accent,
  });
  final Color bg;
  final Color ink;
  final Color accent;
}

// Three palette variants per mood — the hash picks one. Bolder, more
// saturated than the previous single-palette version.
const _palettes = <_Mood, List<_Palette>>{
  _Mood.fiery: [
    _Palette(bg: Color(0xFF3A1810), ink: Color(0xFFC73E1D), accent: Color(0xFFE89B3C)), // sienna burnt
    _Palette(bg: Color(0xFFE63946), ink: Color(0xFFFCD34D), accent: Color(0xFF240B0B)), // saturated crimson
    _Palette(bg: Color(0xFFE84B27), ink: Color(0xFFFFE8C8), accent: Color(0xFF1B1814)), // orange flame
  ],
  _Mood.dark: [
    _Palette(bg: Color(0xFF15171A), ink: Color(0xFF6B1818), accent: Color(0xFFA8A89E)), // near black, wine
    _Palette(bg: Color(0xFF2C2D2F), ink: Color(0xFFE5E5E0), accent: Color(0xFFC73E1D)), // charcoal, bone
    _Palette(bg: Color(0xFF0E1018), ink: Color(0xFF8B0F2A), accent: Color(0xFFE8D89D)), // ink, blood
  ],
  _Mood.romantic: [
    _Palette(bg: Color(0xFFF3D9D9), ink: Color(0xFFB9747E), accent: Color(0xFF73403C)), // dusty rose
    _Palette(bg: Color(0xFFFBC2D3), ink: Color(0xFFE63277), accent: Color(0xFF400D26)), // hot pink, vivid
    _Palette(bg: Color(0xFFE4B7B0), ink: Color(0xFF8B3A3E), accent: Color(0xFFF7E2DA)), // muted terracotta
  ],
  _Mood.gentle: [
    _Palette(bg: Color(0xFFF6EFDD), ink: Color(0xFFB89B6F), accent: Color(0xFF5B4733)), // cream paper
    _Palette(bg: Color(0xFFFFE2A8), ink: Color(0xFF8B5A2B), accent: Color(0xFF2C1F12)), // warm yellow
    _Palette(bg: Color(0xFFEDE7DE), ink: Color(0xFF4A7A35), accent: Color(0xFFB54B3A)), // matcha on cream
  ],
  _Mood.melancholic: [
    _Palette(bg: Color(0xFF38516B), ink: Color(0xFFA1B7CC), accent: Color(0xFFE1DCCB)), // slate blue
    _Palette(bg: Color(0xFF2B4F9E), ink: Color(0xFFE5DDBF), accent: Color(0xFF0E1A3A)), // royal blue
    _Palette(bg: Color(0xFF4A5969), ink: Color(0xFFD8E0EC), accent: Color(0xFF8B3A3E)), // grey-blue
  ],
  _Mood.adventurous: [
    _Palette(bg: Color(0xFF1F3A2A), ink: Color(0xFF89B07A), accent: Color(0xFFE8D89D)), // forest
    _Palette(bg: Color(0xFF4A7A35), ink: Color(0xFFFFE2A8), accent: Color(0xFF1B1814)), // matcha bold
    _Palette(bg: Color(0xFF2F5234), ink: Color(0xFFE7CB57), accent: Color(0xFFF4F0E0)), // pine + gold
  ],
  _Mood.mystical: [
    _Palette(bg: Color(0xFF2A1740), ink: Color(0xFF9C6BC9), accent: Color(0xFFF0D88B)), // deep violet
    _Palette(bg: Color(0xFF5C2D7B), ink: Color(0xFFF0D88B), accent: Color(0xFFFFE2A8)), // bishop purple
    _Palette(bg: Color(0xFF1B0E2E), ink: Color(0xFFE63277), accent: Color(0xFFD8E0EC)), // night violet
  ],
  _Mood.intellectual: [
    _Palette(bg: Color(0xFF1A2A3A), ink: Color(0xFF8FAACF), accent: Color(0xFFE5DDBF)), // ink blue
    _Palette(bg: Color(0xFF065A82), ink: Color(0xFFE5DDBF), accent: Color(0xFFFCD34D)), // teal-navy
    _Palette(bg: Color(0xFFF2EDE4), ink: Color(0xFF1A2A3A), accent: Color(0xFFC73E1D)), // parchment
  ],
  _Mood.natural: [
    _Palette(bg: Color(0xFFE6E0CC), ink: Color(0xFF6B8F3C), accent: Color(0xFF8B6F47)), // linen
    _Palette(bg: Color(0xFF6BBA29), ink: Color(0xFFF4F0E0), accent: Color(0xFF1F3A2A)), // bright leaf
    _Palette(bg: Color(0xFFF5EFE0), ink: Color(0xFFB89B6F), accent: Color(0xFF4A7A35)), // sand + sage
  ],
  _Mood.contemplative: [
    _Palette(bg: Color(0xFFDDE0D8), ink: Color(0xFF5C7A7E), accent: Color(0xFF8F7C5F)), // mist grey
    _Palette(bg: Color(0xFF4FC1E9), ink: Color(0xFFF4F0E0), accent: Color(0xFF0F5C56)), // sky teal
    _Palette(bg: Color(0xFFAFC4C0), ink: Color(0xFF2F4F4F), accent: Color(0xFFF5EFE0)), // sage cool
  ],
  _Mood.celestial: [
    _Palette(bg: Color(0xFF0F2640), ink: Color(0xFFE5C56A), accent: Color(0xFFD8E0EC)), // night sky
    _Palette(bg: Color(0xFF1A1338), ink: Color(0xFFFFE8C8), accent: Color(0xFFE5C56A)), // cosmos
    _Palette(bg: Color(0xFF050720), ink: Color(0xFFFCD34D), accent: Color(0xFFF4F0E0)), // deep void
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// Curated lookup — ~70 famous books mapped by hand
// ═══════════════════════════════════════════════════════════════════════════

const _curated = <String, _Mood>{
  // Dante
  'inferno':                    _Mood.fiery,
  'divina commedia':            _Mood.mystical,
  'purgatorio':                 _Mood.contemplative,
  'paradiso':                   _Mood.celestial,

  // Manzoni
  'promessi sposi':             _Mood.gentle,

  // Calvino
  'barone rampante':            _Mood.natural,
  'visconte dimezzato':         _Mood.melancholic,
  'cavaliere inesistente':      _Mood.adventurous,
  'citta invisibili':           _Mood.intellectual,
  "se una notte d'inverno":     _Mood.intellectual,

  // Eco
  'nome della rosa':            _Mood.intellectual,
  'pendolo di foucault':        _Mood.mystical,

  // Primo Levi
  'se questo e un uomo':        _Mood.melancholic,
  'se questo e\' un uomo':      _Mood.melancholic,

  // Marquez
  "cent'anni di solitudine":    _Mood.melancholic,
  'cento anni di solitudine':   _Mood.melancholic,
  'amore ai tempi del colera':  _Mood.romantic,

  // Saint-Exupery
  'piccolo principe':           _Mood.celestial,
  'petit prince':               _Mood.celestial,

  // Cervantes
  'don chisciotte':             _Mood.adventurous,
  'don quijote':                _Mood.adventurous,

  // Austen
  'orgoglio e pregiudizio':     _Mood.romantic,
  'pride and prejudice':        _Mood.romantic,
  'sense and sensibility':      _Mood.romantic,
  'emma':                       _Mood.romantic,

  // Orwell
  '1984':                       _Mood.dark,
  'fattoria degli animali':     _Mood.dark,
  'animal farm':                _Mood.dark,

  // Tolstoy
  'anna karenina':              _Mood.romantic,
  'guerra e pace':              _Mood.melancholic,
  'war and peace':              _Mood.melancholic,

  // Dostoyevsky
  'fratelli karamazov':         _Mood.melancholic,
  'delitto e castigo':          _Mood.dark,
  'crime and punishment':       _Mood.dark,
  'idiota':                     _Mood.melancholic,

  // Hesse
  'siddharta':                  _Mood.contemplative,
  'siddhartha':                 _Mood.contemplative,
  'lupo della steppa':          _Mood.melancholic,

  // Kafka
  'metamorfosi':                _Mood.dark,
  'il processo':                _Mood.dark,
  'castello':                   _Mood.melancholic,

  // Hemingway
  'vecchio e il mare':          _Mood.contemplative,
  'addio alle armi':            _Mood.melancholic,

  // Camus
  'lo straniero':               _Mood.dark,
  'la peste':                   _Mood.dark,

  // Saramago
  'cecita':                     _Mood.dark,

  // Pessoa
  "libro dell'inquietudine":    _Mood.melancholic,

  // Suskind
  'profumo':                    _Mood.dark,

  // Wilde
  'ritratto di dorian gray':    _Mood.dark,
  'picture of dorian gray':     _Mood.dark,

  // Bulgakov
  'maestro e margherita':       _Mood.mystical,

  // Tolkien
  'signore degli anelli':       _Mood.adventurous,
  'lord of the rings':          _Mood.adventurous,
  'hobbit':                     _Mood.adventurous,

  // Murakami
  'norwegian wood':             _Mood.melancholic,
  'tokyo blues':                _Mood.melancholic,
  'kafka sulla spiaggia':       _Mood.mystical,
  '1q84':                       _Mood.mystical,

  // Tomasi di Lampedusa
  'gattopardo':                 _Mood.melancholic,

  // Sciascia
  'giorno della civetta':       _Mood.dark,

  // D'Annunzio
  'il piacere':                 _Mood.romantic,

  // Pirandello
  'fu mattia pascal':           _Mood.melancholic,
  'uno, nessuno e centomila':   _Mood.intellectual,

  // Svevo
  'coscienza di zeno':          _Mood.intellectual,

  // Buzzati
  'deserto dei tartari':        _Mood.melancholic,

  // Ferrante
  'amica geniale':              _Mood.gentle,

  // Giordano
  'solitudine dei numeri primi':_Mood.melancholic,

  // Saviano
  'gomorra':                    _Mood.dark,

  // Verne
  'ventimila leghe':            _Mood.adventurous,
  'giro del mondo':             _Mood.adventurous,

  // Stevenson
  'isola del tesoro':           _Mood.adventurous,
  'jekyll':                     _Mood.dark,

  // Shelley
  'frankenstein':               _Mood.dark,

  // Stoker
  'dracula':                    _Mood.dark,

  // Melville
  'moby dick':                  _Mood.adventurous,

  // Steinbeck
  'furore':                     _Mood.melancholic,
  'grapes of wrath':            _Mood.melancholic,
  'uomini e topi':              _Mood.melancholic,

  // Fitzgerald
  'gatsby':                     _Mood.romantic,
  'great gatsby':               _Mood.romantic,
};

// ═══════════════════════════════════════════════════════════════════════════
// Keyword fallback
// ═══════════════════════════════════════════════════════════════════════════

const _keywords = <String, _Mood>{
  'morte':      _Mood.dark, 'sangue':    _Mood.dark, 'guerra':   _Mood.dark,
  'ombra':      _Mood.dark, 'ombre':     _Mood.dark, 'paura':    _Mood.dark,
  'death':      _Mood.dark, 'blood':     _Mood.dark, 'shadow':   _Mood.dark,
  'dark':       _Mood.dark,
  'fuoco':      _Mood.fiery, 'fiamma':   _Mood.fiery, 'rivoluzione': _Mood.fiery,
  'fire':       _Mood.fiery, 'flame':    _Mood.fiery,
  'amore':      _Mood.romantic, 'cuore': _Mood.romantic, 'rosa': _Mood.romantic,
  'love':       _Mood.romantic, 'heart': _Mood.romantic, 'rose': _Mood.romantic,
  'bambino':    _Mood.gentle, 'bambina': _Mood.gentle,
  'piccolo':    _Mood.gentle, 'piccola': _Mood.gentle,
  'child':      _Mood.gentle, 'little':  _Mood.gentle,
  'memoria':    _Mood.melancholic, 'ricordi':    _Mood.melancholic,
  'solitudine': _Mood.melancholic, 'pioggia':    _Mood.melancholic,
  'inverno':    _Mood.melancholic, 'silenzio':   _Mood.melancholic,
  'memory':     _Mood.melancholic, 'rain':       _Mood.melancholic,
  'winter':     _Mood.melancholic, 'lonely':     _Mood.melancholic,
  'solitude':   _Mood.melancholic,
  'viaggio':    _Mood.adventurous, 'avventura': _Mood.adventurous,
  'montagna':   _Mood.adventurous, 'isola':     _Mood.adventurous,
  'journey':    _Mood.adventurous, 'voyage':    _Mood.adventurous,
  'island':     _Mood.adventurous,
  'mare':       _Mood.contemplative, 'sea':     _Mood.contemplative,
  'sogno':      _Mood.mystical, 'magia':      _Mood.mystical,
  'mistero':    _Mood.mystical, 'dream':      _Mood.mystical,
  'magic':      _Mood.mystical, 'mystery':    _Mood.mystical,
  'storia':     _Mood.intellectual, 'libro':   _Mood.intellectual,
  'verita':     _Mood.intellectual, 'biblioteca': _Mood.intellectual,
  'book':       _Mood.intellectual, 'library': _Mood.intellectual,
  'foresta':    _Mood.natural, 'bosco':     _Mood.natural,
  'giardino':   _Mood.natural, 'campo':     _Mood.natural,
  'forest':     _Mood.natural, 'garden':    _Mood.natural, 'wood': _Mood.natural,
  'stella':     _Mood.celestial, 'stelle': _Mood.celestial,
  'cielo':      _Mood.celestial, 'luna':   _Mood.celestial,
  'sole':       _Mood.celestial, 'star':   _Mood.celestial,
  'sky':        _Mood.celestial, 'moon':   _Mood.celestial, 'sun': _Mood.celestial,
};

_Mood _detectMood(String title) {
  final t = title.toLowerCase().trim();
  if (t.isEmpty) return _Mood.contemplative;
  for (final e in _curated.entries) {
    if (t.contains(e.key)) return e.value;
  }
  for (final e in _keywords.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return _Mood.values[t.hashCode.abs() % _Mood.values.length];
}

// ═══════════════════════════════════════════════════════════════════════════
// Compositions — 20 variants
// ═══════════════════════════════════════════════════════════════════════════

enum _Composition {
  bigCircle,
  concentricRings,
  sunArc,
  wavyHorizon,
  threeDots,
  triangle,
  invertedTriangle,
  stackedArcs,
  verticalLines,
  plus,
  diagonalSlash,
  xMark,
  vennCircles,
  nestedSquares,
  dotGrid,
  hexagon,
  star,
  dominoFall,
  bigSquare,
  horizontalBar,
}

// Each mood lists 6–8 compositions whose visual language matches the mood.
// Hash picks one. With ~6 options and 3 palettes (= 18 unique looks per
// mood) the chance of two same-mood books colliding is small.
const _moodCompositions = <_Mood, List<_Composition>>{
  _Mood.fiery: [
    _Composition.bigCircle,
    _Composition.concentricRings,
    _Composition.sunArc,
    _Composition.triangle,
    _Composition.dominoFall,
    _Composition.plus,
    _Composition.star,
  ],
  _Mood.dark: [
    _Composition.bigCircle,
    _Composition.verticalLines,
    _Composition.xMark,
    _Composition.invertedTriangle,
    _Composition.diagonalSlash,
    _Composition.horizontalBar,
    _Composition.nestedSquares,
    _Composition.bigSquare,
  ],
  _Mood.romantic: [
    _Composition.wavyHorizon,
    _Composition.bigCircle,
    _Composition.stackedArcs,
    _Composition.sunArc,
    _Composition.vennCircles,
    _Composition.threeDots,
    _Composition.hexagon,
  ],
  _Mood.gentle: [
    _Composition.stackedArcs,
    _Composition.wavyHorizon,
    _Composition.sunArc,
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.hexagon,
    _Composition.dotGrid,
  ],
  _Mood.melancholic: [
    _Composition.wavyHorizon,
    _Composition.verticalLines,
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.invertedTriangle,
    _Composition.horizontalBar,
    _Composition.diagonalSlash,
  ],
  _Mood.adventurous: [
    _Composition.triangle,
    _Composition.stackedArcs,
    _Composition.verticalLines,
    _Composition.diagonalSlash,
    _Composition.dominoFall,
    _Composition.star,
    _Composition.hexagon,
  ],
  _Mood.mystical: [
    _Composition.concentricRings,
    _Composition.threeDots,
    _Composition.verticalLines,
    _Composition.bigCircle,
    _Composition.xMark,
    _Composition.star,
    _Composition.vennCircles,
  ],
  _Mood.intellectual: [
    _Composition.verticalLines,
    _Composition.bigCircle,
    _Composition.triangle,
    _Composition.concentricRings,
    _Composition.dotGrid,
    _Composition.nestedSquares,
    _Composition.plus,
    _Composition.bigSquare,
  ],
  _Mood.natural: [
    _Composition.stackedArcs,
    _Composition.wavyHorizon,
    _Composition.triangle,
    _Composition.sunArc,
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.hexagon,
  ],
  _Mood.contemplative: [
    _Composition.wavyHorizon,
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.sunArc,
    _Composition.concentricRings,
    _Composition.horizontalBar,
    _Composition.vennCircles,
  ],
  _Mood.celestial: [
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.concentricRings,
    _Composition.sunArc,
    _Composition.star,
    _Composition.plus,
    _Composition.dotGrid,
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// Public widget
// ═══════════════════════════════════════════════════════════════════════════

/// Philographics-inspired geometric cover. 20 compositions × 3 palettes
/// per mood means a 30-book library practically never repeats itself.
/// No text on the cover — title + author belong in the surrounding card.
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
    // Mix title and author hashes hard so two books with similar titles
    // diverge in seed (and therefore in palette + composition + position).
    final seed = (title.hashCode * 1315423911) ^ (author.hashCode * 2654435769);
    final s    = seed.abs();

    final mood       = _detectMood(title);
    final palettes   = _palettes[mood]!;
    final palette    = palettes[(s ~/ 7) % palettes.length];
    final comps      = _moodCompositions[mood]!;
    final composition = comps[s % comps.length];

    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: _MoodPainter(
          palette:     palette,
          composition: composition,
          seed:        s,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Painter
// ═══════════════════════════════════════════════════════════════════════════

class _MoodPainter extends CustomPainter {
  _MoodPainter({
    required this.palette,
    required this.composition,
    required this.seed,
  });

  final _Palette     palette;
  final _Composition composition;
  final int          seed;

  // Deterministic pseudo-noise for shape offsets.
  double _f(int n) => ((seed * 9301 + n * 49297) % 233280) / 233280.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.bg);

    switch (composition) {
      case _Composition.bigCircle:        _drawBigCircle(canvas, size);
      case _Composition.concentricRings:  _drawConcentricRings(canvas, size);
      case _Composition.sunArc:           _drawSunArc(canvas, size);
      case _Composition.wavyHorizon:      _drawWavyHorizon(canvas, size);
      case _Composition.threeDots:        _drawThreeDots(canvas, size);
      case _Composition.triangle:         _drawTriangle(canvas, size, pointDown: false);
      case _Composition.invertedTriangle: _drawTriangle(canvas, size, pointDown: true);
      case _Composition.stackedArcs:      _drawStackedArcs(canvas, size);
      case _Composition.verticalLines:    _drawVerticalLines(canvas, size);
      case _Composition.plus:             _drawPlus(canvas, size);
      case _Composition.diagonalSlash:    _drawDiagonalSlash(canvas, size);
      case _Composition.xMark:            _drawXMark(canvas, size);
      case _Composition.vennCircles:      _drawVennCircles(canvas, size);
      case _Composition.nestedSquares:    _drawNestedSquares(canvas, size);
      case _Composition.dotGrid:          _drawDotGrid(canvas, size);
      case _Composition.hexagon:          _drawHexagon(canvas, size);
      case _Composition.star:             _drawStar(canvas, size);
      case _Composition.dominoFall:       _drawDominoFall(canvas, size);
      case _Composition.bigSquare:        _drawBigSquare(canvas, size);
      case _Composition.horizontalBar:    _drawHorizontalBar(canvas, size);
    }
  }

  // ── 1. Big circle ──────────────────────────────────────────────────────
  void _drawBigCircle(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.42;
    final cx = size.width  * (0.32 + 0.36 * _f(1));
    final cy = size.height * (0.30 + 0.20 * _f(2));
    canvas.drawCircle(Offset(cx, cy), radius, Paint()..color = palette.ink);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.78),
      size.shortestSide * 0.025,
      Paint()..color = palette.accent,
    );
  }

  // ── 2. Concentric rings ────────────────────────────────────────────────
  void _drawConcentricRings(Canvas canvas, Size size) {
    final cx = size.width  * (0.40 + 0.20 * _f(1));
    final cy = size.height * (0.40 + 0.20 * _f(2));
    final stroke = Paint()
      ..color = palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.014;
    final base = size.shortestSide * 0.16;
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(Offset(cx, cy), base + i * base * 0.55, stroke);
    }
    canvas.drawCircle(Offset(cx, cy), size.shortestSide * 0.030,
        Paint()..color = palette.accent);
  }

  // ── 3. Sun arc ─────────────────────────────────────────────────────────
  void _drawSunArc(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.48;
    final cx = size.width * (0.45 + 0.10 * _f(1));
    canvas.drawCircle(Offset(cx, size.height * 1.05), radius,
        Paint()..color = palette.ink);
    final y = size.height * 0.62;
    canvas.drawLine(
      Offset(size.width * 0.10, y),
      Offset(size.width * 0.90, y),
      Paint()..color = palette.accent..strokeWidth = size.height * 0.008,
    );
  }

  // ── 4. Wavy horizon ────────────────────────────────────────────────────
  void _drawWavyHorizon(Canvas canvas, Size size) {
    final midY      = size.height * (0.46 + 0.10 * _f(1));
    final amplitude = size.height * 0.08;
    final waves     = 1.8 + _f(2) * 1.2;
    const steps     = 60;

    void drawWave(double y, double phase, Color color, double width) {
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = size.width * t;
        final yi = y + math.sin(t * math.pi * 2 * waves + phase) * amplitude * 0.85;
        if (i == 0) {
          path.moveTo(x, yi);
        } else {
          path.lineTo(x, yi);
        }
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round);
    }

    drawWave(midY,                      0.0, palette.ink,    size.shortestSide * 0.020);
    drawWave(midY + amplitude * 1.6,    1.2, palette.accent, size.shortestSide * 0.012);
  }

  // ── 5. Three dots ──────────────────────────────────────────────────────
  void _drawThreeDots(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.055;
    final ink = Paint()..color = palette.ink;
    final accent = Paint()..color = palette.accent;
    canvas.drawCircle(Offset(size.width  * (0.22 + 0.10 * _f(1)),
                              size.height * (0.28 + 0.10 * _f(2))), r,        ink);
    canvas.drawCircle(Offset(size.width  * (0.62 + 0.10 * _f(3)),
                              size.height * (0.48 + 0.10 * _f(4))), r * 0.82, ink);
    canvas.drawCircle(Offset(size.width  * (0.38 + 0.15 * _f(5)),
                              size.height * (0.76 + 0.10 * _f(6))), r * 0.70, accent);
  }

  // ── 6 + 7. Triangle (up or down) ───────────────────────────────────────
  void _drawTriangle(Canvas canvas, Size size, {required bool pointDown}) {
    final cx = size.width  * 0.50;
    final cy = size.height * 0.50;
    final h  = size.shortestSide * 0.54;
    final path = Path();
    if (pointDown) {
      path.moveTo(cx - h * 0.55, cy - h * 0.35);
      path.lineTo(cx + h * 0.55, cy - h * 0.35);
      path.lineTo(cx,            cy + h * 0.50);
    } else {
      path.moveTo(cx - h * 0.55, cy + h * 0.35);
      path.lineTo(cx + h * 0.55, cy + h * 0.35);
      path.lineTo(cx,            cy - h * 0.50);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = palette.ink);
    final y = pointDown ? cy - h * 0.35 : cy + h * 0.35;
    canvas.drawLine(
      Offset(size.width * 0.05, y),
      Offset(size.width * 0.95, y),
      Paint()..color = palette.accent..strokeWidth = size.height * 0.008,
    );
  }

  // ── 8. Stacked arcs ────────────────────────────────────────────────────
  void _drawStackedArcs(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * (0.35 + 0.20 * _f(1)), size.height * 1.05),
      size.width * 0.85,
      Paint()..color = palette.ink,
    );
    canvas.drawCircle(
      Offset(size.width * (0.65 - 0.20 * _f(2)), size.height * 1.08),
      size.width * 0.55,
      Paint()..color = palette.accent,
    );
  }

  // ── 9. Vertical lines ──────────────────────────────────────────────────
  void _drawVerticalLines(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = palette.ink
      ..strokeWidth = size.shortestSide * 0.020
      ..strokeCap = StrokeCap.round;
    final count = _f(1) > 0.5 ? 3 : 2;
    final topPad    = size.height * 0.18;
    final bottomPad = size.height * 0.18;
    for (var i = 0; i < count; i++) {
      final t = (i + 1) / (count + 1);
      final x = size.width * (t + (_f(i + 2) - 0.5) * 0.10);
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        stroke,
      );
    }
    final tickY = size.height * 0.74;
    canvas.drawLine(
      Offset(size.width * 0.18, tickY),
      Offset(size.width * 0.40, tickY),
      Paint()
        ..color = palette.accent
        ..strokeWidth = size.shortestSide * 0.012
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── 10. Plus (Philographics: Positivism, Atheism) ─────────────────────
  void _drawPlus(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * 0.50;
    final arm   = size.shortestSide * 0.36;
    final thick = size.shortestSide * 0.18;
    final ink = Paint()..color = palette.ink;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: arm * 2,   height: thick),
      ink,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: thick, height: arm * 2),
      ink,
    );
    // accent: tiny corner dot for visual rhythm
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.18),
      size.shortestSide * 0.022,
      Paint()..color = palette.accent,
    );
  }

  // ── 11. Diagonal slash (Philographics: Scepticism) ────────────────────
  void _drawDiagonalSlash(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = palette.ink
      ..strokeWidth = size.shortestSide * 0.075
      ..strokeCap = StrokeCap.square;
    // bias slope: 60% top-left → bottom-right, 40% the opposite
    final downhill = _f(1) > 0.4;
    if (downhill) {
      canvas.drawLine(
        Offset(size.width * 0.10, size.height * 0.18),
        Offset(size.width * 0.90, size.height * 0.82),
        stroke,
      );
    } else {
      canvas.drawLine(
        Offset(size.width * 0.10, size.height * 0.82),
        Offset(size.width * 0.90, size.height * 0.18),
        stroke,
      );
    }
    // tiny accent square at one end
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width * 0.84, size.height * 0.18),
        width: size.shortestSide * 0.06,
        height: size.shortestSide * 0.06,
      ),
      Paint()..color = palette.accent,
    );
  }

  // ── 12. X mark (Philographics: Nihilism) ──────────────────────────────
  void _drawXMark(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = palette.ink
      ..strokeWidth = size.shortestSide * 0.085
      ..strokeCap = StrokeCap.square;
    final pad = size.shortestSide * 0.22;
    canvas.drawLine(
      Offset(pad,                pad),
      Offset(size.width - pad,   size.height - pad),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width - pad,   pad),
      Offset(pad,                size.height - pad),
      stroke,
    );
  }

  // ── 13. Venn (Philographics: Dualism) ─────────────────────────────────
  void _drawVennCircles(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.30;
    final cy = size.height * (0.46 + 0.06 * _f(1));
    final dx = radius * 0.78;
    canvas.drawCircle(
      Offset(size.width * 0.5 - dx, cy),
      radius,
      Paint()..color = palette.ink..blendMode = BlendMode.srcOver,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5 + dx, cy),
      radius,
      Paint()..color = palette.accent..blendMode = BlendMode.multiply,
    );
  }

  // ── 14. Nested squares (Philographics: Idealism) ──────────────────────
  void _drawNestedSquares(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * (0.46 + 0.08 * _f(1));
    final outer = size.shortestSide * 0.62;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: outer, height: outer),
      Paint()..color = palette.ink,
    );
    final mid = outer * 0.60;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: mid, height: mid),
      Paint()..color = palette.accent,
    );
    final inner = mid * 0.55;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: inner, height: inner),
      Paint()..color = palette.bg,
    );
  }

  // ── 15. Dot grid (Philographics: Reductionism) ────────────────────────
  void _drawDotGrid(Canvas canvas, Size size) {
    const cols = 5;
    const rows = 5;
    final cellW = size.width / (cols + 1);
    final cellH = (size.height * 0.78) / (rows + 1);
    final topPad = size.height * 0.11;
    final r = math.min(cellW, cellH) * 0.30;
    // accent at a deterministic but off-centre cell
    final accentCol = (seed >> 3) % cols;
    final accentRow = (seed >> 7) % rows;
    for (var ry = 0; ry < rows; ry++) {
      for (var cx = 0; cx < cols; cx++) {
        final x = cellW * (cx + 1);
        final y = topPad + cellH * (ry + 1);
        final isAccent = cx == accentCol && ry == accentRow;
        canvas.drawCircle(
          Offset(x, y),
          isAccent ? r * 0.6 : r,
          Paint()..color = isAccent ? palette.accent : palette.ink,
        );
      }
    }
  }

  // ── 16. Hexagon (Philographics: Utilitarianism) ───────────────────────
  void _drawHexagon(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * (0.48 + 0.06 * _f(1));
    final r  = size.shortestSide * 0.36;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = palette.ink);
    // accent: thin outline slightly larger
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.012,
    );
  }

  // ── 17. Five-point star (Philographics: Marxism) ──────────────────────
  void _drawStar(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * (0.46 + 0.06 * _f(1));
    final outerR = size.shortestSide * 0.34;
    final innerR = outerR * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = (math.pi / 5) * i - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = palette.ink);
  }

  // ── 18. Domino fall (Philographics: Determinism) ──────────────────────
  // A small row of tipped-over rectangles, suggesting momentum.
  void _drawDominoFall(Canvas canvas, Size size) {
    final baseY = size.height * 0.62;
    final w = size.width * 0.085;
    final h = size.height * 0.40;
    final spacing = w * 1.6;
    final ink = Paint()..color = palette.ink;
    final startX = size.width * 0.18;
    final tips = [
      0.0, -0.10, -0.25, -0.45, -0.65, -0.90,
    ];
    for (var i = 0; i < tips.length; i++) {
      final cx = startX + i * spacing;
      canvas.save();
      canvas.translate(cx, baseY);
      canvas.rotate(tips[i]);
      canvas.drawRect(
        Rect.fromLTWH(-w / 2, -h, w, h),
        ink,
      );
      canvas.restore();
    }
    // tiny ball above the leading domino
    canvas.drawCircle(
      Offset(startX + tips.length * spacing, baseY - h * 0.8),
      size.shortestSide * 0.035,
      Paint()..color = palette.accent,
    );
  }

  // ── 19. Big solid square (Philographics: Realism) ─────────────────────
  void _drawBigSquare(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.70;
    final cx = size.width  * 0.50;
    final cy = size.height * (0.50 + 0.06 * _f(1));
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: side, height: side),
      Paint()..color = palette.ink,
    );
  }

  // ── 20. Horizontal bar (Philographics: Dogma) ─────────────────────────
  void _drawHorizontalBar(Canvas canvas, Size size) {
    final barH = size.height * 0.12;
    final cy = size.height * (0.50 + 0.10 * (_f(1) - 0.5));
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width * 0.50, cy),
        width: size.width * 0.78,
        height: barH,
      ),
      Paint()..color = palette.ink,
    );
    // accent: small square at one corner
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.18),
        width: size.shortestSide * 0.06,
        height: size.shortestSide * 0.06,
      ),
      Paint()..color = palette.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _MoodPainter old) =>
      old.palette     != palette ||
      old.composition != composition ||
      old.seed        != seed;
}
