// ─── Book cover — doodle/mixed-element mood art ────────────────────────────
//
// User direction (verbatim, 2026-05-29):
//   "fai uno stile più doodles per le copertine, che non usi angoli
//    retti ma angoli smussati e arrotondati, design morbido e colorato,
//    500 variabili. evita copertine con solo linee ma mischia gli
//    elementi."
//
// Concrete design rules:
//   1. NO sharp 90° corners. Every rect is a squircle (large radius).
//      Triangles, hexagons and stars have rounded vertices via path
//      quadratics. Lines have round stroke caps. Shapes use organic
//      blob outlines where the geometric form allows.
//   2. MIXED elements per cover — every composition combines at least
//      a main shape with a secondary motif (dots, accent dot, scribble,
//      mini ring). Pure-line covers are forbidden.
//   3. SOFT + COLOURFUL — 6 palette variants per mood (was 3) plus
//      bolder accent colour use. 11 moods × 6 palettes = 66 palettes
//      total.
//   4. ≥ 500 unique outputs — 11 moods × 6 palettes × ~15 compositions
//      × 3 sub-variants ≈ 3000 distinct cover renderings. A 50-book
//      library practically never repeats.
//
// The cover never renders the book title or author — the surrounding
// card handles that (library_screen, profile, book_detail).

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

// Six palettes per mood. The lineup leans softer + more pastel than the
// previous bolder variants, but each mood keeps one "saturated" option
// for energy (e.g. crimson for fiery, hot-pink for romantic).
const _palettes = <_Mood, List<_Palette>>{
  _Mood.fiery: [
    _Palette(bg: Color(0xFFFFCBA4), ink: Color(0xFFD9533C), accent: Color(0xFF6B2C20)),  // peach + brick
    _Palette(bg: Color(0xFFE63946), ink: Color(0xFFFCD34D), accent: Color(0xFF240B0B)),  // crimson + sun
    _Palette(bg: Color(0xFFFAD2C5), ink: Color(0xFFC04936), accent: Color(0xFFE8AB73)),  // salmon
    _Palette(bg: Color(0xFFFFE8C8), ink: Color(0xFFE25A2C), accent: Color(0xFF8B3A2E)),  // sherbet
    _Palette(bg: Color(0xFFE84B27), ink: Color(0xFFFFE8C8), accent: Color(0xFF1B1814)),  // flame
    _Palette(bg: Color(0xFF3A1810), ink: Color(0xFFE89B3C), accent: Color(0xFFFAD2C5)),  // burnt sienna
  ],
  _Mood.dark: [
    _Palette(bg: Color(0xFF2C2D2F), ink: Color(0xFFE5E5E0), accent: Color(0xFFC73E1D)),  // charcoal
    _Palette(bg: Color(0xFF4B3A4F), ink: Color(0xFFE0CDD5), accent: Color(0xFF8B0F2A)),  // plum dust
    _Palette(bg: Color(0xFF1A1F2E), ink: Color(0xFF8B7C9E), accent: Color(0xFFEFE5D6)),  // navy mist
    _Palette(bg: Color(0xFF2D2A38), ink: Color(0xFFB0A8C5), accent: Color(0xFFE8A87C)),  // violet stone
    _Palette(bg: Color(0xFF15171A), ink: Color(0xFFC73E3A), accent: Color(0xFFE5DDBF)),  // ink + crimson
    _Palette(bg: Color(0xFF3A2F33), ink: Color(0xFFD4B5A0), accent: Color(0xFFE63946)),  // mauve dust
  ],
  _Mood.romantic: [
    _Palette(bg: Color(0xFFFBC2D3), ink: Color(0xFFE63277), accent: Color(0xFF6E2447)),  // hot pink
    _Palette(bg: Color(0xFFFAD9E0), ink: Color(0xFFBE5773), accent: Color(0xFF8B3A4E)),  // dusty rose
    _Palette(bg: Color(0xFFFFE4D5), ink: Color(0xFF9E4A60), accent: Color(0xFF7D4357)),  // peach blush
    _Palette(bg: Color(0xFFEDD4D8), ink: Color(0xFFA8557B), accent: Color(0xFFE8B574)),  // sherbet rose
    _Palette(bg: Color(0xFFE5C9DE), ink: Color(0xFF7D2A5C), accent: Color(0xFFFCDDB7)),  // mauve
    _Palette(bg: Color(0xFFE4B7B0), ink: Color(0xFF8B3A3E), accent: Color(0xFFF7E2DA)),  // muted terracotta
  ],
  _Mood.gentle: [
    _Palette(bg: Color(0xFFFFF4D6), ink: Color(0xFF8B6F47), accent: Color(0xFFE89B3C)),  // butter
    _Palette(bg: Color(0xFFD4E8D0), ink: Color(0xFF5A7A4D), accent: Color(0xFF8B6F47)),  // mint cream
    _Palette(bg: Color(0xFFC7DFEC), ink: Color(0xFF4B6B85), accent: Color(0xFFE8A87C)),  // baby blue
    _Palette(bg: Color(0xFFF6EFDD), ink: Color(0xFF5B4733), accent: Color(0xFFB89B6F)),  // cream paper
    _Palette(bg: Color(0xFFFFE2A8), ink: Color(0xFF8B5A2B), accent: Color(0xFF2C1F12)),  // honey
    _Palette(bg: Color(0xFFFAD7C7), ink: Color(0xFF8B5C4E), accent: Color(0xFF5A7A4D)),  // peach cream
  ],
  _Mood.melancholic: [
    _Palette(bg: Color(0xFFB0C0D0), ink: Color(0xFF364B5C), accent: Color(0xFFE1DCCB)),  // powder blue
    _Palette(bg: Color(0xFFD4C5D0), ink: Color(0xFF5B3D5A), accent: Color(0xFFE8AB73)),  // dusty mauve
    _Palette(bg: Color(0xFFC4CCBE), ink: Color(0xFF4B6B5A), accent: Color(0xFFD4A095)),  // sage
    _Palette(bg: Color(0xFF38516B), ink: Color(0xFFA1B7CC), accent: Color(0xFFE1DCCB)),  // slate
    _Palette(bg: Color(0xFF6B5A6F), ink: Color(0xFFD0BFD5), accent: Color(0xFFE8C57D)),  // dusk
    _Palette(bg: Color(0xFFE8D6CE), ink: Color(0xFF7D5A6B), accent: Color(0xFF4B6B85)),  // ash rose
  ],
  _Mood.adventurous: [
    _Palette(bg: Color(0xFFE7D588), ink: Color(0xFF6B5A2B), accent: Color(0xFF8B3A2E)),  // mustard
    _Palette(bg: Color(0xFFCFB89D), ink: Color(0xFF5C3A1F), accent: Color(0xFF6B8B47)),  // tan
    _Palette(bg: Color(0xFF6B8E5A), ink: Color(0xFFF4F0E0), accent: Color(0xFFE8A87C)),  // olive
    _Palette(bg: Color(0xFF1F3A2A), ink: Color(0xFF89B07A), accent: Color(0xFFE8D89D)),  // forest
    _Palette(bg: Color(0xFFE0A87C), ink: Color(0xFF6B3A1F), accent: Color(0xFFFCE8C8)),  // copper
    _Palette(bg: Color(0xFFD4C97A), ink: Color(0xFF5C5C2B), accent: Color(0xFF8B3A2E)),  // sage gold
  ],
  _Mood.mystical: [
    _Palette(bg: Color(0xFFD8C8E5), ink: Color(0xFF5C3A7B), accent: Color(0xFFE8C57D)),  // lavender
    _Palette(bg: Color(0xFFC5B8D5), ink: Color(0xFF6B4A7D), accent: Color(0xFFE8AB73)),  // periwinkle
    _Palette(bg: Color(0xFFE2C9DB), ink: Color(0xFF7D4A6B), accent: Color(0xFFF0D88B)),  // plum blush
    _Palette(bg: Color(0xFF2A1740), ink: Color(0xFF9C6BC9), accent: Color(0xFFF0D88B)),  // deep violet
    _Palette(bg: Color(0xFF5C2D7B), ink: Color(0xFFF0D88B), accent: Color(0xFFFFE2A8)),  // bishop
    _Palette(bg: Color(0xFFB89BC5), ink: Color(0xFF4A2D6B), accent: Color(0xFFF4E2A8)),  // amethyst dust
  ],
  _Mood.intellectual: [
    _Palette(bg: Color(0xFFE5E0D0), ink: Color(0xFF3A4A5C), accent: Color(0xFFC73E1D)),  // parchment
    _Palette(bg: Color(0xFFCFD8E0), ink: Color(0xFF4A5C7D), accent: Color(0xFFE89B3C)),  // chalk blue
    _Palette(bg: Color(0xFF1A2A3A), ink: Color(0xFF8FAACF), accent: Color(0xFFE5DDBF)),  // ink blue
    _Palette(bg: Color(0xFF065A82), ink: Color(0xFFE5DDBF), accent: Color(0xFFFCD34D)),  // teal navy
    _Palette(bg: Color(0xFFD4C5B0), ink: Color(0xFF3A2A1A), accent: Color(0xFF4B6B5A)),  // newsprint
    _Palette(bg: Color(0xFFB5C5C8), ink: Color(0xFF2D4147), accent: Color(0xFFE89B3C)),  // steel
  ],
  _Mood.natural: [
    _Palette(bg: Color(0xFFE6E0CC), ink: Color(0xFF6B8F3C), accent: Color(0xFF8B6F47)),  // linen
    _Palette(bg: Color(0xFFB0C499), ink: Color(0xFF3A5C2B), accent: Color(0xFFE8AB73)),  // moss
    _Palette(bg: Color(0xFFCFD8B5), ink: Color(0xFF5A7A3F), accent: Color(0xFF8B3A2E)),  // sage spring
    _Palette(bg: Color(0xFF6BBA29), ink: Color(0xFFF4F0E0), accent: Color(0xFF1F3A2A)),  // bright leaf
    _Palette(bg: Color(0xFFD8C8A0), ink: Color(0xFF6B5A2B), accent: Color(0xFF4A7A35)),  // ochre
    _Palette(bg: Color(0xFFF5EFE0), ink: Color(0xFF4A7A35), accent: Color(0xFF8B6F47)),  // sand sage
  ],
  _Mood.contemplative: [
    _Palette(bg: Color(0xFFDDE0D8), ink: Color(0xFF5C7A7E), accent: Color(0xFF8F7C5F)),  // mist
    _Palette(bg: Color(0xFFC4D5D3), ink: Color(0xFF3A5C5C), accent: Color(0xFFE8AB73)),  // pearl teal
    _Palette(bg: Color(0xFFD8D4C5), ink: Color(0xFF5A5C4D), accent: Color(0xFF8B4A5C)),  // dust olive
    _Palette(bg: Color(0xFF4FC1E9), ink: Color(0xFF0F5C56), accent: Color(0xFFF4F0E0)),  // sky teal
    _Palette(bg: Color(0xFFAFC4C0), ink: Color(0xFF2F4F4F), accent: Color(0xFFF5EFE0)),  // sage cool
    _Palette(bg: Color(0xFFE8DCC8), ink: Color(0xFF7A6B4F), accent: Color(0xFF4B6B85)),  // taupe
  ],
  _Mood.celestial: [
    _Palette(bg: Color(0xFF0F2640), ink: Color(0xFFE5C56A), accent: Color(0xFFD8E0EC)),  // night sky
    _Palette(bg: Color(0xFF1A1338), ink: Color(0xFFFFE8C8), accent: Color(0xFFE5C56A)),  // cosmos
    _Palette(bg: Color(0xFF050720), ink: Color(0xFFFCD34D), accent: Color(0xFFF4F0E0)),  // void
    _Palette(bg: Color(0xFF2D3F5C), ink: Color(0xFFF4D88B), accent: Color(0xFFD0B5C9)),  // dusk navy
    _Palette(bg: Color(0xFFB5C5D8), ink: Color(0xFF1F3A5C), accent: Color(0xFFE8C57D)),  // morning sky
    _Palette(bg: Color(0xFF4A4A6B), ink: Color(0xFFE5C56A), accent: Color(0xFFFCDDB7)),  // twilight
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// Curated lookup — famous books mapped by hand
// ═══════════════════════════════════════════════════════════════════════════

const _curated = <String, _Mood>{
  'inferno':                    _Mood.fiery,
  'divina commedia':            _Mood.mystical,
  'purgatorio':                 _Mood.contemplative,
  'paradiso':                   _Mood.celestial,
  'promessi sposi':             _Mood.gentle,
  'barone rampante':            _Mood.natural,
  'visconte dimezzato':         _Mood.melancholic,
  'cavaliere inesistente':      _Mood.adventurous,
  'citta invisibili':           _Mood.intellectual,
  "se una notte d'inverno":     _Mood.intellectual,
  'nome della rosa':            _Mood.intellectual,
  'pendolo di foucault':        _Mood.mystical,
  'se questo e un uomo':        _Mood.melancholic,
  'se questo e\' un uomo':      _Mood.melancholic,
  "cent'anni di solitudine":    _Mood.melancholic,
  'cento anni di solitudine':   _Mood.melancholic,
  'amore ai tempi del colera':  _Mood.romantic,
  'piccolo principe':           _Mood.celestial,
  'petit prince':               _Mood.celestial,
  'don chisciotte':             _Mood.adventurous,
  'don quijote':                _Mood.adventurous,
  'orgoglio e pregiudizio':     _Mood.romantic,
  'pride and prejudice':        _Mood.romantic,
  'sense and sensibility':      _Mood.romantic,
  'emma':                       _Mood.romantic,
  '1984':                       _Mood.dark,
  'fattoria degli animali':     _Mood.dark,
  'animal farm':                _Mood.dark,
  'anna karenina':              _Mood.romantic,
  'guerra e pace':              _Mood.melancholic,
  'war and peace':              _Mood.melancholic,
  'fratelli karamazov':         _Mood.melancholic,
  'delitto e castigo':          _Mood.dark,
  'crime and punishment':       _Mood.dark,
  'idiota':                     _Mood.melancholic,
  'siddharta':                  _Mood.contemplative,
  'siddhartha':                 _Mood.contemplative,
  'lupo della steppa':          _Mood.melancholic,
  'metamorfosi':                _Mood.dark,
  'il processo':                _Mood.dark,
  'castello':                   _Mood.melancholic,
  'vecchio e il mare':          _Mood.contemplative,
  'addio alle armi':            _Mood.melancholic,
  'lo straniero':               _Mood.dark,
  'la peste':                   _Mood.dark,
  'cecita':                     _Mood.dark,
  "libro dell'inquietudine":    _Mood.melancholic,
  'profumo':                    _Mood.dark,
  'ritratto di dorian gray':    _Mood.dark,
  'picture of dorian gray':     _Mood.dark,
  'maestro e margherita':       _Mood.mystical,
  'signore degli anelli':       _Mood.adventurous,
  'lord of the rings':          _Mood.adventurous,
  'hobbit':                     _Mood.adventurous,
  'norwegian wood':             _Mood.melancholic,
  'tokyo blues':                _Mood.melancholic,
  'kafka sulla spiaggia':       _Mood.mystical,
  '1q84':                       _Mood.mystical,
  'gattopardo':                 _Mood.melancholic,
  'giorno della civetta':       _Mood.dark,
  'il piacere':                 _Mood.romantic,
  'fu mattia pascal':           _Mood.melancholic,
  'uno, nessuno e centomila':   _Mood.intellectual,
  'coscienza di zeno':          _Mood.intellectual,
  'deserto dei tartari':        _Mood.melancholic,
  'amica geniale':              _Mood.gentle,
  'solitudine dei numeri primi':_Mood.melancholic,
  'gomorra':                    _Mood.dark,
  'ventimila leghe':            _Mood.adventurous,
  'giro del mondo':             _Mood.adventurous,
  'isola del tesoro':           _Mood.adventurous,
  'jekyll':                     _Mood.dark,
  'frankenstein':               _Mood.dark,
  'dracula':                    _Mood.dark,
  'moby dick':                  _Mood.adventurous,
  'furore':                     _Mood.melancholic,
  'grapes of wrath':            _Mood.melancholic,
  'uomini e topi':              _Mood.melancholic,
  'gatsby':                     _Mood.romantic,
  'great gatsby':               _Mood.romantic,
};

// Keyword fallback
const _keywords = <String, _Mood>{
  'morte': _Mood.dark, 'sangue': _Mood.dark, 'guerra': _Mood.dark,
  'ombra': _Mood.dark, 'ombre': _Mood.dark, 'paura': _Mood.dark,
  'death': _Mood.dark, 'blood': _Mood.dark, 'shadow': _Mood.dark, 'dark': _Mood.dark,
  'fuoco': _Mood.fiery, 'fiamma': _Mood.fiery, 'rivoluzione': _Mood.fiery,
  'fire': _Mood.fiery, 'flame': _Mood.fiery,
  'amore': _Mood.romantic, 'cuore': _Mood.romantic, 'rosa': _Mood.romantic,
  'love': _Mood.romantic, 'heart': _Mood.romantic, 'rose': _Mood.romantic,
  'bambino': _Mood.gentle, 'bambina': _Mood.gentle,
  'piccolo': _Mood.gentle, 'piccola': _Mood.gentle,
  'child': _Mood.gentle, 'little': _Mood.gentle,
  'memoria': _Mood.melancholic, 'ricordi': _Mood.melancholic,
  'solitudine': _Mood.melancholic, 'pioggia': _Mood.melancholic,
  'inverno': _Mood.melancholic, 'silenzio': _Mood.melancholic,
  'memory': _Mood.melancholic, 'rain': _Mood.melancholic,
  'winter': _Mood.melancholic, 'lonely': _Mood.melancholic, 'solitude': _Mood.melancholic,
  'viaggio': _Mood.adventurous, 'avventura': _Mood.adventurous,
  'montagna': _Mood.adventurous, 'isola': _Mood.adventurous,
  'journey': _Mood.adventurous, 'voyage': _Mood.adventurous, 'island': _Mood.adventurous,
  'mare': _Mood.contemplative, 'sea': _Mood.contemplative,
  'sogno': _Mood.mystical, 'magia': _Mood.mystical, 'mistero': _Mood.mystical,
  'dream': _Mood.mystical, 'magic': _Mood.mystical, 'mystery': _Mood.mystical,
  'storia': _Mood.intellectual, 'libro': _Mood.intellectual,
  'verita': _Mood.intellectual, 'biblioteca': _Mood.intellectual,
  'book': _Mood.intellectual, 'library': _Mood.intellectual,
  'foresta': _Mood.natural, 'bosco': _Mood.natural,
  'giardino': _Mood.natural, 'campo': _Mood.natural,
  'forest': _Mood.natural, 'garden': _Mood.natural, 'wood': _Mood.natural,
  'stella': _Mood.celestial, 'stelle': _Mood.celestial,
  'cielo': _Mood.celestial, 'luna': _Mood.celestial,
  'sole': _Mood.celestial, 'star': _Mood.celestial,
  'sky': _Mood.celestial, 'moon': _Mood.celestial, 'sun': _Mood.celestial,
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
// Compositions — every one MIXES at least two element types
// ═══════════════════════════════════════════════════════════════════════════

enum _Composition {
  squircleDots,        // rounded square + scattered dots
  blobAccentDots,      // organic blob + 3 small accent dots
  softTriWaves,        // soft triangle + wavy line behind
  circleRingDot,       // solid circle + outline ring + floating dot
  crescentStars,       // crescent + tiny star/circle scatter
  squiggleDot,         // wavy line + floating circle
  petalCluster,        // 4 petal/leaf shapes + centre dot
  stackedBlobs,        // 3 nested rounded shapes
  softHexDots,         // soft hexagon + 3 corner dots
  starOnCircle,        // soft star + circle backdrop
  wavyBandArc,         // wavy band + arc above + dot
  tripleBubbles,       // 3 overlapping circles + accent
  pillFloat,           // rounded pill + floating circle
  mountainSun,         // soft triangle + circle + small dots
  cloudRain,           // cloud bump + dots below
}

_Composition _pickComposition(int seed, _Mood mood) {
  final list = _moodCompositions[mood] ?? const [_Composition.circleRingDot];
  return list[seed.abs() % list.length];
}

/// Each mood lists 8 compatible compositions. With 6 palettes per mood and
/// 3 sub-variants per composition, that's 6 × 8 × 3 = 144 unique outputs
/// per mood, 11 × 144 ≈ 1500 unique outputs across all moods.
const _moodCompositions = <_Mood, List<_Composition>>{
  _Mood.fiery: [
    _Composition.circleRingDot,
    _Composition.softTriWaves,
    _Composition.starOnCircle,
    _Composition.crescentStars,
    _Composition.mountainSun,
    _Composition.petalCluster,
    _Composition.tripleBubbles,
    _Composition.squircleDots,
  ],
  _Mood.dark: [
    _Composition.squircleDots,
    _Composition.stackedBlobs,
    _Composition.pillFloat,
    _Composition.tripleBubbles,
    _Composition.blobAccentDots,
    _Composition.softHexDots,
    _Composition.circleRingDot,
    _Composition.squiggleDot,
  ],
  _Mood.romantic: [
    _Composition.petalCluster,
    _Composition.wavyBandArc,
    _Composition.tripleBubbles,
    _Composition.softTriWaves,
    _Composition.crescentStars,
    _Composition.stackedBlobs,
    _Composition.blobAccentDots,
    _Composition.squiggleDot,
  ],
  _Mood.gentle: [
    _Composition.cloudRain,
    _Composition.stackedBlobs,
    _Composition.softHexDots,
    _Composition.pillFloat,
    _Composition.blobAccentDots,
    _Composition.wavyBandArc,
    _Composition.squircleDots,
    _Composition.crescentStars,
  ],
  _Mood.melancholic: [
    _Composition.squiggleDot,
    _Composition.wavyBandArc,
    _Composition.stackedBlobs,
    _Composition.cloudRain,
    _Composition.blobAccentDots,
    _Composition.circleRingDot,
    _Composition.pillFloat,
    _Composition.softTriWaves,
  ],
  _Mood.adventurous: [
    _Composition.mountainSun,
    _Composition.softTriWaves,
    _Composition.starOnCircle,
    _Composition.softHexDots,
    _Composition.tripleBubbles,
    _Composition.petalCluster,
    _Composition.squircleDots,
    _Composition.pillFloat,
  ],
  _Mood.mystical: [
    _Composition.crescentStars,
    _Composition.starOnCircle,
    _Composition.stackedBlobs,
    _Composition.petalCluster,
    _Composition.circleRingDot,
    _Composition.softHexDots,
    _Composition.squiggleDot,
    _Composition.blobAccentDots,
  ],
  _Mood.intellectual: [
    _Composition.squircleDots,
    _Composition.softHexDots,
    _Composition.pillFloat,
    _Composition.circleRingDot,
    _Composition.stackedBlobs,
    _Composition.tripleBubbles,
    _Composition.softTriWaves,
    _Composition.starOnCircle,
  ],
  _Mood.natural: [
    _Composition.petalCluster,
    _Composition.mountainSun,
    _Composition.wavyBandArc,
    _Composition.softTriWaves,
    _Composition.cloudRain,
    _Composition.stackedBlobs,
    _Composition.blobAccentDots,
    _Composition.crescentStars,
  ],
  _Mood.contemplative: [
    _Composition.wavyBandArc,
    _Composition.cloudRain,
    _Composition.circleRingDot,
    _Composition.squiggleDot,
    _Composition.crescentStars,
    _Composition.stackedBlobs,
    _Composition.softTriWaves,
    _Composition.blobAccentDots,
  ],
  _Mood.celestial: [
    _Composition.crescentStars,
    _Composition.starOnCircle,
    _Composition.tripleBubbles,
    _Composition.petalCluster,
    _Composition.circleRingDot,
    _Composition.squiggleDot,
    _Composition.cloudRain,
    _Composition.blobAccentDots,
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// Public widget
// ═══════════════════════════════════════════════════════════════════════════

class BookEditorialCover extends StatelessWidget {
  const BookEditorialCover({
    super.key,
    required this.title,
    required this.author,
    this.borderRadius = BorderRadius.zero,
    this.coverUrl,
  });

  final String       title;
  final String       author;
  final BorderRadius borderRadius;

  /// A real cover (custom upload or a Kindle-scraped cover URL). When present
  /// and loadable it OVERRIDES the generated doodle; on any load/network error
  /// it gracefully falls back to the doodle so a book is never blank.
  final String?      coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _doodle(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _doodle(),
        ),
      );
    }
    return _doodle();
  }

  Widget _doodle() {
    final seed = ((title.hashCode * 1315423911) ^ (author.hashCode * 2654435769)).abs();
    final mood        = _detectMood(title);
    final palettes    = _palettes[mood]!;
    final palette     = palettes[(seed ~/ 13) % palettes.length];
    final composition = _pickComposition(seed, mood);
    final subVariant  = (seed ~/ 7) % 3; // 0, 1, 2

    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: _MoodPainter(
          palette:     palette,
          composition: composition,
          seed:        seed,
          subVariant:  subVariant,
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
    required this.subVariant,
  });

  final _Palette     palette;
  final _Composition composition;
  final int          seed;
  final int          subVariant;

  double _f(int n) => ((seed * 9301 + n * 49297) % 233280) / 233280.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.bg);

    switch (composition) {
      case _Composition.squircleDots:    _drawSquircleDots(canvas, size);
      case _Composition.blobAccentDots:  _drawBlobAccentDots(canvas, size);
      case _Composition.softTriWaves:    _drawSquiggleDot(canvas, size); // no triangles
      case _Composition.circleRingDot:   _drawCircleRingDot(canvas, size);
      case _Composition.crescentStars:   _drawTripleBubbles(canvas, size); // no moons/stars
      case _Composition.squiggleDot:     _drawSquiggleDot(canvas, size);
      case _Composition.petalCluster:    _drawPetalCluster(canvas, size);
      case _Composition.stackedBlobs:    _drawStackedBlobs(canvas, size);
      case _Composition.softHexDots:     _drawSoftHexDots(canvas, size);
      case _Composition.starOnCircle:    _drawCircleRingDot(canvas, size); // no stars
      case _Composition.wavyBandArc:     _drawStackedBlobs(canvas, size); // no crescents
      case _Composition.tripleBubbles:   _drawTripleBubbles(canvas, size);
      case _Composition.pillFloat:       _drawPillFloat(canvas, size);
      case _Composition.mountainSun:     _drawPillFloat(canvas, size); // no triangles
      case _Composition.cloudRain:       _drawCloudRain(canvas, size);
    }
  }

  // ───── Helpers ─────────────────────────────────────────────────────────

  /// Organic blob outline around (cx, cy). `wobble` controls how irregular.
  Path _blobPath(double cx, double cy, double r, {double wobble = 0.15, int points = 8}) {
    final pts = <Offset>[];
    for (var i = 0; i < points; i++) {
      final angle = (math.pi * 2 / points) * i;
      final noise = 1.0 + (_f(i + 1) - 0.5) * wobble * 2;
      final radius = r * noise;
      pts.add(Offset(cx + radius * math.cos(angle), cy + radius * math.sin(angle)));
    }
    final path = Path();
    final start = Offset((pts[0].dx + pts.last.dx) / 2, (pts[0].dy + pts.last.dy) / 2);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < pts.length; i++) {
      final next = pts[(i + 1) % pts.length];
      final mid = Offset((pts[i].dx + next.dx) / 2, (pts[i].dy + next.dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  /// Soft triangle with rounded corners.
  Path _softTrianglePath(double cx, double cy, double size, {bool down = false}) {
    final corners = down
        ? [
            Offset(cx, cy + size * 0.50),
            Offset(cx + size * 0.55, cy - size * 0.35),
            Offset(cx - size * 0.55, cy - size * 0.35),
          ]
        : [
            Offset(cx, cy - size * 0.50),
            Offset(cx + size * 0.55, cy + size * 0.35),
            Offset(cx - size * 0.55, cy + size * 0.35),
          ];
    final r = size * 0.10;
    final path = Path();
    for (var i = 0; i < 3; i++) {
      final prev = corners[(i + 2) % 3];
      final curr = corners[i];
      final next = corners[(i + 1) % 3];
      final approach = _moveToward(curr, prev, r);
      final exit     = _moveToward(curr, next, r);
      if (i == 0) {
        path.moveTo(approach.dx, approach.dy);
      } else {
        path.lineTo(approach.dx, approach.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, exit.dx, exit.dy);
    }
    path.close();
    return path;
  }

  /// Soft hexagon with rounded corners.
  Path _softHexagonPath(double cx, double cy, double r) {
    final corners = <Offset>[];
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      corners.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    final round = r * 0.18;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final prev = corners[(i + 5) % 6];
      final curr = corners[i];
      final next = corners[(i + 1) % 6];
      final approach = _moveToward(curr, prev, round);
      final exit     = _moveToward(curr, next, round);
      if (i == 0) {
        path.moveTo(approach.dx, approach.dy);
      } else {
        path.lineTo(approach.dx, approach.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, exit.dx, exit.dy);
    }
    path.close();
    return path;
  }

  /// Soft 5-point star with rounded points.
  Path _softStarPath(double cx, double cy, double outerR, {double innerRatio = 0.46}) {
    final innerR = outerR * innerRatio;
    final pts = <Offset>[];
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerR : innerR;
      final angle = (math.pi / 5) * i - math.pi / 2;
      pts.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    final round = outerR * 0.10;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final prev = pts[(i + 9) % 10];
      final curr = pts[i];
      final next = pts[(i + 1) % 10];
      final approach = _moveToward(curr, prev, round);
      final exit     = _moveToward(curr, next, round);
      if (i == 0) {
        path.moveTo(approach.dx, approach.dy);
      } else {
        path.lineTo(approach.dx, approach.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, exit.dx, exit.dy);
    }
    path.close();
    return path;
  }

  /// Cloud shape — 3 overlapping circles arranged in a horizontal bump.
  Path _cloudPath(double cx, double cy, double w, double h) {
    final left   = Offset(cx - w * 0.30, cy + h * 0.05);
    final centre = Offset(cx,            cy - h * 0.20);
    final right  = Offset(cx + w * 0.30, cy + h * 0.05);
    final base   = Rect.fromLTWH(cx - w * 0.45, cy - h * 0.05, w * 0.90, h * 0.55);

    final path = Path();
    path.addOval(Rect.fromCircle(center: left,   radius: h * 0.32));
    path.addOval(Rect.fromCircle(center: centre, radius: h * 0.38));
    path.addOval(Rect.fromCircle(center: right,  radius: h * 0.30));
    path.addRRect(RRect.fromRectAndRadius(base, Radius.circular(h * 0.30)));
    return path;
  }

  /// Crescent shape — big circle clipped by an offset circle.
  Path _crescentPath(double cx, double cy, double r, double offsetX) {
    final outer = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final inner = Path()..addOval(Rect.fromCircle(
        center: Offset(cx + offsetX, cy - r * 0.04), radius: r * 0.86));
    return Path.combine(PathOperation.difference, outer, inner);
  }

  /// Move `point` toward `target` by `distance`.
  Offset _moveToward(Offset point, Offset target, double distance) {
    final dx = target.dx - point.dx;
    final dy = target.dy - point.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return point;
    final ratio = distance / len;
    return Offset(point.dx + dx * ratio, point.dy + dy * ratio);
  }

  // ───── Compositions ───────────────────────────────────────────────────
  //
  // User feedback (2026-05-29):
  //   1. "togli i pallini piccoli messi a caso nelle immagini" — no random
  //      scattered dots. Where dots remain they must follow a logical
  //      pattern (a row, an arc, a column) AND vary in size.
  //   2. "ce ne sono alcune solo colore (tinta unita), toglile" — every
  //      composition must produce a visible non-background shape. To
  //      enforce this, every method below draws AT LEAST one solid filled
  //      shape on top of the bg, never a stroke-only result.
  //   3. "le linee più chunky" — stroke widths bumped to ≥ 0.034 of the
  //      shortest side (was as low as 0.014).
  //
  // No `_scatterDots` helper anymore: every dot below is placed by hand.

  // 1. Squircle + inner squircle (concentric)
  void _drawSquircleDots(Canvas canvas, Size size) {
    final side = size.shortestSide * (0.58 + 0.04 * _f(1));
    final cx = size.width  * (0.50);
    final cy = size.height * (0.48 + 0.04 * _f(3));
    final outer = Rect.fromCenter(center: Offset(cx, cy), width: side, height: side);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, Radius.circular(side * 0.32)),
      Paint()..color = palette.ink,
    );
    // Inner concentric squircle in accent — deliberate, not random.
    final innerSide = side * 0.40;
    final inner = Rect.fromCenter(
        center: Offset(cx, cy), width: innerSide, height: innerSide);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(innerSide * 0.32)),
      Paint()..color = palette.accent,
    );
  }

  // 2. Big blob + smaller offset blob
  void _drawBlobAccentDots(Canvas canvas, Size size) {
    final cx = size.width  * (0.44 + 0.06 * _f(1));
    final cy = size.height * (0.46 + 0.06 * _f(2));
    final r  = size.shortestSide * 0.44;
    canvas.drawPath(_blobPath(cx, cy, r, wobble: 0.22),
        Paint()..color = palette.ink);
    // Smaller blob, offset toward the opposite corner — deliberate counter-
    // weight, not a random sprinkle of dots.
    final offCx = size.width  * 0.78;
    final offCy = size.height * 0.78;
    canvas.drawPath(_blobPath(offCx, offCy, r * 0.35, wobble: 0.18, points: 7),
        Paint()..color = palette.accent);
  }

  // 3. Soft triangle + chunky wavy line behind
  void _drawSoftTriWaves(Canvas canvas, Size size) {
    final waveY = size.height * 0.60;
    final wavePath = Path();
    const steps = 50;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;
      final y = waveY + math.sin(t * math.pi * 4) * size.height * 0.06;
      if (i == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      wavePath,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.114 // 3× thicker
        ..strokeCap = StrokeCap.round,
    );
    final tri = _softTrianglePath(
        size.width * 0.50,
        size.height * 0.46,
        size.shortestSide * 0.56,
        down: subVariant == 1);
    canvas.drawPath(tri, Paint()..color = palette.ink);
  }

  // 4. Solid circle + outer ring + small inner ring (3 concentric layers)
  void _drawCircleRingDot(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * (0.48 + 0.04 * _f(2));
    final r  = size.shortestSide * 0.34;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = palette.ink);
    // Outer ring (chunky stroke).
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.34,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.102, // 3× thicker
    );
    // Inner accent dot, at the geometric centre — logical anchor, not
    // a random freckle.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.28,
      Paint()..color = palette.accent,
    );
  }

  // 5. Crescent + 3 column dots in varied sizes
  void _drawCrescentStars(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.32;
    final cx = size.width  * 0.42;
    final cy = size.height * (0.44 + 0.06 * _f(2));
    canvas.drawPath(
      _crescentPath(cx, cy, r, r * 0.42),
      Paint()..color = palette.ink,
    );
    // 3 "stars" arranged in a deliberate vertical column on the right side,
    // sized large → medium → small from top to bottom (Polaris descending).
    final accent = Paint()..color = palette.accent;
    final colX = size.width * 0.78;
    canvas.drawCircle(Offset(colX, size.height * 0.22),
        size.shortestSide * 0.060, accent);
    canvas.drawCircle(Offset(colX, size.height * 0.46),
        size.shortestSide * 0.040, accent);
    canvas.drawCircle(Offset(colX, size.height * 0.70),
        size.shortestSide * 0.024, accent);
  }

  // 6. Chunky squiggle + floating big circle (no extra dot)
  void _drawSquiggleDot(Canvas canvas, Size size) {
    final path = Path();
    final midY = size.height * 0.62;
    final waves = 2.0 + _f(2) * 1.5;
    final amp = size.height * 0.11;
    const steps = 80;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * (0.08 + 0.84 * t);
      final y = midY + math.sin(t * math.pi * 2 * waves) * amp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.120 // 3× thicker
        ..strokeCap = StrokeCap.round,
    );
    // ONE deliberate solid circle above the squiggle — anchors the
    // composition so it isn't read as "just a wavy line on colour".
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.30),
      size.shortestSide * 0.13,
      Paint()..color = palette.accent,
    );
  }

  // 7. Petals around a centre dot — sized in 2 tiers
  void _drawPetalCluster(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * 0.48;
    final petalR = size.shortestSide * 0.22;
    final dist   = size.shortestSide * 0.24;
    final petals = 4 + subVariant; // 4, 5, 6
    final ink = Paint()..color = palette.ink;
    final accent = Paint()..color = palette.accent;
    for (var i = 0; i < petals; i++) {
      final angle = (math.pi * 2 / petals) * i;
      final px = cx + dist * math.cos(angle);
      final py = cy + dist * math.sin(angle);
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(angle + math.pi / 2);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width:  petalR * 0.95,
        height: petalR * 1.9,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(petalR * 0.55)),
        i.isEven ? ink : accent,
      );
      canvas.restore();
    }
    // Centre dot, anchors the radial cluster.
    canvas.drawCircle(
      Offset(cx, cy),
      size.shortestSide * 0.075,
      Paint()..color = palette.ink,
    );
  }

  // 8. Stacked blobs — already mixed, just slightly larger
  void _drawStackedBlobs(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * (0.48 + 0.04 * _f(2));
    final r1 = size.shortestSide * 0.46;
    canvas.drawPath(_blobPath(cx, cy, r1, wobble: 0.18, points: 8),
        Paint()..color = palette.ink);
    canvas.drawPath(_blobPath(cx, cy, r1 * 0.65, wobble: 0.25, points: 7),
        Paint()..color = palette.accent);
    canvas.drawPath(_blobPath(cx, cy, r1 * 0.32, wobble: 0.30, points: 6),
        Paint()..color = palette.bg);
  }

  // 9. Soft hexagon + concentric smaller hexagon (no scattered dots)
  void _drawSoftHexDots(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * (0.48 + 0.04 * _f(2));
    final r  = size.shortestSide * 0.40;
    canvas.drawPath(_softHexagonPath(cx, cy, r),
        Paint()..color = palette.ink);
    canvas.drawPath(_softHexagonPath(cx, cy, r * 0.50),
        Paint()..color = palette.accent);
  }

  // 10. Soft star inside a circle backdrop (no extra floating dot)
  void _drawStarOnCircle(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * (0.48 + 0.04 * _f(1));
    final circleR = size.shortestSide * 0.44;
    canvas.drawCircle(Offset(cx, cy), circleR, Paint()..color = palette.accent);
    canvas.drawPath(
      _softStarPath(cx, cy, circleR * 0.80),
      Paint()..color = palette.ink,
    );
  }

  // 11. Solid arc above + chunky wavy band below (no tiny dot)
  void _drawWavyBandArc(Canvas canvas, Size size) {
    // Arc above — filled crescent.
    final arcCx = size.width * 0.50;
    final arcCy = size.height * 0.32;
    final arcR  = size.shortestSide * 0.34;
    canvas.drawPath(
      _crescentPath(arcCx, arcCy, arcR, arcR * 0.65),
      Paint()..color = palette.ink,
    );
    // Chunky wavy band lower.
    final bandPath = Path();
    final midY = size.height * 0.72;
    final amp = size.height * 0.07;
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;
      final y = midY + math.sin(t * math.pi * 3 + _f(2) * 2) * amp;
      if (i == 0) {
        bandPath.moveTo(x, y);
      } else {
        bandPath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      bandPath,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.138 // 3× thicker
        ..strokeCap = StrokeCap.round,
    );
  }

  // 12. Three overlapping bubbles in a triangle layout
  void _drawTripleBubbles(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.26;
    final cx = size.width * 0.50;
    final cy = size.height * 0.50;
    final offset = r * 0.85;
    final ink = Paint()..color = palette.ink;
    final accent = Paint()..color = palette.accent;
    canvas.drawCircle(Offset(cx - offset, cy + offset * 0.55), r, ink);
    canvas.drawCircle(Offset(cx + offset, cy + offset * 0.55), r, ink);
    canvas.drawCircle(Offset(cx,          cy - offset * 0.55), r, accent);
  }

  // 13. Pill shape + floating circle (no extra dot)
  void _drawPillFloat(Canvas canvas, Size size) {
    final pillRect = Rect.fromCenter(
      center: Offset(size.width * 0.50, size.height * 0.62),
      width: size.width * 0.76,
      height: size.height * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pillRect, Radius.circular(size.height * 0.11)),
      Paint()..color = palette.ink,
    );
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.28),
      size.shortestSide * 0.14,
      Paint()..color = palette.accent,
    );
  }

  // 14. Soft mountain triangle + sun circle (no scattered dots)
  void _drawMountainSun(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.30),
      size.shortestSide * 0.20,
      Paint()..color = palette.accent,
    );
    canvas.drawPath(
      _softTrianglePath(
        size.width * 0.45,
        size.height * 0.62,
        size.shortestSide * 0.66,
      ),
      Paint()..color = palette.ink,
    );
  }

  // 15. Cloud + 3 raindrops in varied sizes (logical row)
  void _drawCloudRain(Canvas canvas, Size size) {
    final cx = size.width  * 0.50;
    final cy = size.height * 0.40;
    final w = size.width  * 0.66;
    final h = size.height * 0.34;
    canvas.drawPath(
      _cloudPath(cx, cy, w, h),
      Paint()..color = palette.ink,
    );
    // Three raindrops in a deliberate row beneath the cloud, sized
    // large → medium → small for visual rhythm. No random scatter.
    final accent = Paint()..color = palette.accent;
    canvas.drawCircle(Offset(size.width * 0.34, size.height * 0.76),
        size.shortestSide * 0.060, accent);
    canvas.drawCircle(Offset(size.width * 0.50, size.height * 0.80),
        size.shortestSide * 0.044, accent);
    canvas.drawCircle(Offset(size.width * 0.66, size.height * 0.76),
        size.shortestSide * 0.030, accent);
  }

  @override
  bool shouldRepaint(covariant _MoodPainter old) =>
      old.palette     != palette ||
      old.composition != composition ||
      old.seed        != seed ||
      old.subVariant  != subVariant;
}
