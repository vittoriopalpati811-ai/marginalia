// ─── Book cover — abstract geometric mood art ──────────────────────────────
//
// User direction (verbatim, screenshot 2026-05-28):
//   "Mantieni le box dei libri nella libreria con il titolo e l'autore sotto,
//    modifica solo l'immagine relativa a ciascun libro generando per ciascuno
//    un'immagine colorata con disegni geometrici, dai colori tenui e vivaci
//    (prendi ispirazioni dai libri stessi a cui viene associata la copertina,
//    per esempio per 'L'Inferno' di Dante Alighieri colori piu' cruenti, per
//    'Orgoglio e Pregiudizio' colori piu' tenui e femminili). Le immagini
//    possono contenere linee dritte, ondulate, cerchi, ecc ma devono
//    mantenersi su uno stile minimal."
//
// Translation into a concrete design:
//
//   * The cover image is purely visual — NO text on the artwork itself. The
//     library card already shows the title + author below the cover, so
//     stacking the title on top of the art was visual duplication.
//
//   * Each book gets ONE mood, which selects ONE palette (background +
//     ink + accent colour) and a small subset of compatible compositions
//     (circle, arc, waves, dots, triangle, lines...). The composition is
//     then picked deterministically from the title+author hash so the
//     same book always looks the same across launches.
//
//   * Mood detection cascades:
//       1. Curated lookup — ~50 famous books mapped by hand
//       2. Keyword analysis — scan the title for words like "inferno",
//          "amore", "morte", "stelle" -> mood
//       3. Hash fallback — deterministic spread across all moods
//
//   * The minimal style is enforced by the constraint that each
//     composition uses AT MOST 3 elements (one ink, one accent, maybe
//     one tiny dot). No "AI slop" multi-shape overlays.

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
  melancholic,   // Cent'anni di solitudine, Pessoa, Buzzati
  adventurous,   // Don Chisciotte, Tolkien, Verne
  mystical,      // Bulgakov, Eco Foucault, Borges
  intellectual,  // Calvino, Eco Rosa, Pirandello
  natural,       // Hesse Siddhartha, Walden
  contemplative, // Il vecchio e il mare, Camus
  celestial,     // Stars / sky / night books
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

// Each mood has a hand-tuned palette. Backgrounds skew low-chroma (so the
// covers read as "paper" or "field"), inks pick the brand-defining hue,
// accents are the small bright counterpoint.
const _palettes = <_Mood, _Palette>{
  _Mood.fiery: _Palette(
    bg:     Color(0xFF3A1810),
    ink:    Color(0xFFC73E1D),
    accent: Color(0xFFE89B3C),
  ),
  _Mood.dark: _Palette(
    bg:     Color(0xFF15171A),
    ink:    Color(0xFF6B1818),
    accent: Color(0xFFA8A89E),
  ),
  _Mood.romantic: _Palette(
    bg:     Color(0xFFF3D9D9),
    ink:    Color(0xFFB9747E),
    accent: Color(0xFF73403C),
  ),
  _Mood.gentle: _Palette(
    bg:     Color(0xFFF6EFDD),
    ink:    Color(0xFFB89B6F),
    accent: Color(0xFF5B4733),
  ),
  _Mood.melancholic: _Palette(
    bg:     Color(0xFF38516B),
    ink:    Color(0xFFA1B7CC),
    accent: Color(0xFFE1DCCB),
  ),
  _Mood.adventurous: _Palette(
    bg:     Color(0xFF1F3A2A),
    ink:    Color(0xFF89B07A),
    accent: Color(0xFFE8D89D),
  ),
  _Mood.mystical: _Palette(
    bg:     Color(0xFF2A1740),
    ink:    Color(0xFF9C6BC9),
    accent: Color(0xFFF0D88B),
  ),
  _Mood.intellectual: _Palette(
    bg:     Color(0xFF1A2A3A),
    ink:    Color(0xFF8FAACF),
    accent: Color(0xFFE5DDBF),
  ),
  _Mood.natural: _Palette(
    bg:     Color(0xFFE6E0CC),
    ink:    Color(0xFF6B8F3C),
    accent: Color(0xFF8B6F47),
  ),
  _Mood.contemplative: _Palette(
    bg:     Color(0xFFDDE0D8),
    ink:    Color(0xFF5C7A7E),
    accent: Color(0xFF8F7C5F),
  ),
  _Mood.celestial: _Palette(
    bg:     Color(0xFF0F2640),
    ink:    Color(0xFFE5C56A),
    accent: Color(0xFFD8E0EC),
  ),
};

// ═══════════════════════════════════════════════════════════════════════════
// Curated lookup — ~50 famous books mapped by hand
// ═══════════════════════════════════════════════════════════════════════════
//
// Lowercased substring match against the title. Entries are ordered most-
// specific first so e.g. "divina commedia" wins over a generic "commedia".

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
// Keyword fallback — substring match anywhere in the title
// ═══════════════════════════════════════════════════════════════════════════

const _keywords = <String, _Mood>{
  // dark
  'morte':       _Mood.dark,
  'sangue':      _Mood.dark,
  'guerra':      _Mood.dark,
  'ombra':       _Mood.dark,
  'ombre':       _Mood.dark,
  'paura':       _Mood.dark,
  'death':       _Mood.dark,
  'blood':       _Mood.dark,
  'shadow':      _Mood.dark,
  'dark':        _Mood.dark,

  // fiery
  'fuoco':       _Mood.fiery,
  'fiamma':      _Mood.fiery,
  'rivoluzione': _Mood.fiery,
  'fire':        _Mood.fiery,
  'flame':       _Mood.fiery,

  // romantic
  'amore':       _Mood.romantic,
  'cuore':       _Mood.romantic,
  'rosa':        _Mood.romantic,
  'love':        _Mood.romantic,
  'heart':       _Mood.romantic,
  'rose':        _Mood.romantic,

  // gentle
  'bambino':     _Mood.gentle,
  'bambina':     _Mood.gentle,
  'piccolo':     _Mood.gentle,
  'piccola':     _Mood.gentle,
  'child':       _Mood.gentle,
  'little':      _Mood.gentle,

  // melancholic
  'memoria':     _Mood.melancholic,
  'ricordi':     _Mood.melancholic,
  'solitudine':  _Mood.melancholic,
  'pioggia':     _Mood.melancholic,
  'inverno':     _Mood.melancholic,
  'silenzio':    _Mood.melancholic,
  'memory':      _Mood.melancholic,
  'rain':        _Mood.melancholic,
  'winter':      _Mood.melancholic,
  'lonely':      _Mood.melancholic,
  'solitude':    _Mood.melancholic,

  // adventurous
  'viaggio':     _Mood.adventurous,
  'avventura':   _Mood.adventurous,
  'montagna':    _Mood.adventurous,
  'isola':       _Mood.adventurous,
  'journey':     _Mood.adventurous,
  'voyage':      _Mood.adventurous,
  'island':      _Mood.adventurous,

  // contemplative — sea reads contemplative more than adventurous
  'mare':        _Mood.contemplative,
  'sea':         _Mood.contemplative,

  // mystical
  'sogno':       _Mood.mystical,
  'magia':       _Mood.mystical,
  'mistero':     _Mood.mystical,
  'dream':       _Mood.mystical,
  'magic':       _Mood.mystical,
  'mystery':     _Mood.mystical,

  // intellectual
  'storia':      _Mood.intellectual,
  'libro':       _Mood.intellectual,
  'verita':      _Mood.intellectual,
  'biblioteca':  _Mood.intellectual,
  'book':        _Mood.intellectual,
  'library':     _Mood.intellectual,

  // natural
  'foresta':     _Mood.natural,
  'bosco':       _Mood.natural,
  'giardino':    _Mood.natural,
  'campo':       _Mood.natural,
  'forest':      _Mood.natural,
  'garden':      _Mood.natural,
  'wood':        _Mood.natural,

  // celestial
  'stella':      _Mood.celestial,
  'stelle':      _Mood.celestial,
  'cielo':       _Mood.celestial,
  'luna':        _Mood.celestial,
  'sole':        _Mood.celestial,
  'star':        _Mood.celestial,
  'sky':         _Mood.celestial,
  'moon':        _Mood.celestial,
  'sun':         _Mood.celestial,
};

_Mood _detectMood(String title) {
  final t = title.toLowerCase().trim();
  if (t.isEmpty) return _Mood.contemplative;

  // 1. Curated — first substring match wins
  for (final entry in _curated.entries) {
    if (t.contains(entry.key)) return entry.value;
  }

  // 2. Keyword fallback
  for (final entry in _keywords.entries) {
    if (t.contains(entry.key)) return entry.value;
  }

  // 3. Hash fallback — spread evenly across all moods
  final h = t.hashCode.abs();
  return _Mood.values[h % _Mood.values.length];
}

// ═══════════════════════════════════════════════════════════════════════════
// Compositions
// ═══════════════════════════════════════════════════════════════════════════

enum _Composition {
  bigCircle,         // single large filled circle, off-centre
  concentricRings,   // 3 nested unfilled rings
  sunArc,            // semicircle at the bottom
  wavyHorizon,       // gentle sine wave across the middle
  threeDots,         // three small filled dots
  triangle,          // single equilateral, pointing up or down
  stackedArcs,       // 2 arcs nested at the top (rolling hills)
  verticalLines,     // 2-3 thin vertical lines
}

// Each mood pairs with 3-4 compatible compositions. The composition is
// chosen by hashing (title + author) and picking within the compatible
// set, so the same book is always the same shape, but two adjacent books
// in a library look different.
const _moodCompositions = <_Mood, List<_Composition>>{
  _Mood.fiery: [
    _Composition.bigCircle,
    _Composition.concentricRings,
    _Composition.sunArc,
    _Composition.triangle,
  ],
  _Mood.dark: [
    _Composition.bigCircle,
    _Composition.verticalLines,
    _Composition.threeDots,
    _Composition.triangle,
  ],
  _Mood.romantic: [
    _Composition.wavyHorizon,
    _Composition.bigCircle,
    _Composition.stackedArcs,
    _Composition.sunArc,
  ],
  _Mood.gentle: [
    _Composition.stackedArcs,
    _Composition.wavyHorizon,
    _Composition.sunArc,
    _Composition.threeDots,
  ],
  _Mood.melancholic: [
    _Composition.wavyHorizon,
    _Composition.verticalLines,
    _Composition.threeDots,
    _Composition.bigCircle,
  ],
  _Mood.adventurous: [
    _Composition.triangle,
    _Composition.stackedArcs,
    _Composition.verticalLines,
    _Composition.bigCircle,
  ],
  _Mood.mystical: [
    _Composition.concentricRings,
    _Composition.threeDots,
    _Composition.verticalLines,
    _Composition.bigCircle,
  ],
  _Mood.intellectual: [
    _Composition.verticalLines,
    _Composition.bigCircle,
    _Composition.triangle,
    _Composition.concentricRings,
  ],
  _Mood.natural: [
    _Composition.stackedArcs,
    _Composition.wavyHorizon,
    _Composition.triangle,
    _Composition.sunArc,
  ],
  _Mood.contemplative: [
    _Composition.wavyHorizon,
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.sunArc,
  ],
  _Mood.celestial: [
    _Composition.threeDots,
    _Composition.bigCircle,
    _Composition.concentricRings,
    _Composition.sunArc,
  ],
};

_Composition _pickComposition(int seed, _Mood mood) {
  final compatible = _moodCompositions[mood]!;
  return compatible[seed.abs() % compatible.length];
}

// ═══════════════════════════════════════════════════════════════════════════
// Public widget
// ═══════════════════════════════════════════════════════════════════════════

/// Minimal geometric mood cover. The artwork is a single composition
/// (circle, arc, waves, dots...) in a palette chosen from the book's
/// mood, which is derived from a curated lookup of famous titles +
/// keyword analysis + a deterministic hash fallback.
///
/// The cover does NOT render the book title or author — the surrounding
/// card (in library_screen, profile, book_detail) is responsible for that.
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
    final mood        = _detectMood(title);
    final palette     = _palettes[mood]!;
    final seed        = (title.hashCode ^ (author.hashCode << 1)).abs();
    final composition = _pickComposition(seed, mood);

    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: _MoodPainter(
          palette:     palette,
          composition: composition,
          seed:        seed,
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

  // Small deterministic helper so positions vary per book but stay stable
  // for the same (title + author) hash.
  double _f(int n) => ((seed * 9301 + n * 49297) % 233280) / 233280.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Fill the background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.bg,
    );

    // 2. Draw the chosen composition.
    switch (composition) {
      case _Composition.bigCircle:       _drawBigCircle(canvas, size);
      case _Composition.concentricRings: _drawConcentricRings(canvas, size);
      case _Composition.sunArc:          _drawSunArc(canvas, size);
      case _Composition.wavyHorizon:     _drawWavyHorizon(canvas, size);
      case _Composition.threeDots:       _drawThreeDots(canvas, size);
      case _Composition.triangle:        _drawTriangle(canvas, size);
      case _Composition.stackedArcs:     _drawStackedArcs(canvas, size);
      case _Composition.verticalLines:   _drawVerticalLines(canvas, size);
    }
  }

  // ── 1. Big circle ──────────────────────────────────────────────────────
  // Single large filled disc, offset toward the top so the bottom of the
  // cover stays visually grounded.
  void _drawBigCircle(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.42;
    final cx = size.width  * (0.32 + 0.36 * _f(1));
    final cy = size.height * (0.30 + 0.20 * _f(2));
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()..color = palette.ink,
    );
    // tiny accent dot, distant from the main circle
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.78),
      size.shortestSide * 0.025,
      Paint()..color = palette.accent,
    );
  }

  // ── 2. Concentric rings ─────────────────────────────────────────────────
  // Three thin nested rings, centred slightly off the cover's centre.
  void _drawConcentricRings(Canvas canvas, Size size) {
    final cx = size.width  * (0.40 + 0.20 * _f(1));
    final cy = size.height * (0.40 + 0.20 * _f(2));
    final stroke = Paint()
      ..color = palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.012;
    final base = size.shortestSide * 0.18;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(cx, cy), base + i * base * 0.55, stroke);
    }
    canvas.drawCircle(
      Offset(cx, cy),
      size.shortestSide * 0.028,
      Paint()..color = palette.accent,
    );
  }

  // ── 3. Sun arc ──────────────────────────────────────────────────────────
  // Half-disc emerging from the bottom edge, like a sunrise.
  void _drawSunArc(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.48;
    final cx = size.width * (0.45 + 0.10 * _f(1));
    final cy = size.height * 1.05;
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()..color = palette.ink,
    );
    final y = size.height * 0.62;
    canvas.drawLine(
      Offset(size.width * 0.10, y),
      Offset(size.width * 0.90, y),
      Paint()
        ..color = palette.accent
        ..strokeWidth = size.height * 0.008,
    );
  }

  // ── 4. Wavy horizon ─────────────────────────────────────────────────────
  // Single low-amplitude sine wave across the middle, with a fainter
  // second wave below it for depth.
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
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    drawWave(midY,                       0.0, palette.ink,    size.shortestSide * 0.018);
    drawWave(midY + amplitude * 1.6,     1.2, palette.accent, size.shortestSide * 0.010);
  }

  // ── 5. Three dots ───────────────────────────────────────────────────────
  // Sparse minimalist dots — 2 ink, 1 accent.
  void _drawThreeDots(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.052;
    final ink = Paint()..color = palette.ink;
    final accent = Paint()..color = palette.accent;
    canvas.drawCircle(
      Offset(size.width  * (0.22 + 0.10 * _f(1)),
             size.height * (0.30 + 0.10 * _f(2))),
      r, ink,
    );
    canvas.drawCircle(
      Offset(size.width  * (0.62 + 0.10 * _f(3)),
             size.height * (0.48 + 0.10 * _f(4))),
      r * 0.85, ink,
    );
    canvas.drawCircle(
      Offset(size.width  * (0.40 + 0.15 * _f(5)),
             size.height * (0.74 + 0.10 * _f(6))),
      r * 0.70, accent,
    );
  }

  // ── 6. Triangle ─────────────────────────────────────────────────────────
  // Single equilateral. 70% chance pointing up, 30% pointing down — the
  // downward triangles read more melancholic.
  void _drawTriangle(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * 0.50;
    final h  = size.shortestSide * 0.52;
    final pointDown = _f(1) > 0.7;
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
      Paint()
        ..color = palette.accent
        ..strokeWidth = size.height * 0.008,
    );
  }

  // ── 7. Stacked arcs ─────────────────────────────────────────────────────
  // Two huge overlapping circles emerging from the bottom — like rolling
  // hills behind each other.
  void _drawStackedArcs(Canvas canvas, Size size) {
    // Back hill (taller, ink)
    canvas.drawCircle(
      Offset(size.width  * (0.35 + 0.20 * _f(1)),
             size.height * 1.05),
      size.width * 0.85,
      Paint()..color = palette.ink,
    );
    // Front hill (shorter, accent), overlapping in front
    canvas.drawCircle(
      Offset(size.width  * (0.65 - 0.20 * _f(2)),
             size.height * 1.08),
      size.width * 0.55,
      Paint()..color = palette.accent,
    );
  }

  // ── 8. Vertical lines ───────────────────────────────────────────────────
  // 2 or 3 thin vertical lines — the simplest possible composition.
  void _drawVerticalLines(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = palette.ink
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeCap = StrokeCap.round;
    final count = _f(1) > 0.5 ? 3 : 2;
    final topPad    = size.height * 0.20;
    final bottomPad = size.height * 0.20;
    for (var i = 0; i < count; i++) {
      final t = (i + 1) / (count + 1);
      final x = size.width * (t + (_f(i + 2) - 0.5) * 0.08);
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        stroke,
      );
    }
    // accent: short horizontal tick
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

  @override
  bool shouldRepaint(covariant _MoodPainter old) =>
      old.palette     != palette ||
      old.composition != composition ||
      old.seed        != seed;
}
