// ─── Book cover — manuscript-proof aesthetic ────────────────────────────────
//
// Earlier iterations tried to *simulate* designed book covers procedurally
// — 6 variants, 14 palettes, fake "MARGINALIA EDITIONS · 042" imprint,
// floating shapes per hash. The user kept reading these as AI-slop because
// the very existence of procedural variation is the tell: real publishers
// commission individual designers for each cover, so an algorithm
// generating 6 templates × 14 colours signals "this is fake."
//
// New direction: full restraint. One single design, applied identically to
// every book in the user's library, on the cream paper background the rest
// of the app uses. The ONLY variation between books is a thin coloured
// strip at the top (hash-derived hue) — like Penguin Modern Classics, which
// is the entire reason their library looks like a series rather than a
// random pile.
//
// Reads as: "the user's library, typeset on uncovered proof paper, waiting
// for its real cover" — which is precisely what it is. No imprint that
// doesn't exist, no edition number that's made up, no procedural shape that
// pretends to be art. Just title + author, set well.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Strip palette ───────────────────────────────────────────────────────────
// Twelve restrained editorial hues — each gives the cover a subtle "category"
// tint without flooding the page with a saturated background. Hash maps a
// book to one of these; the cream paper underneath stays the same.
const _kStripPalette = <Color>[
  Color(0xFFB54B3A), // terracotta
  Color(0xFFA77B2C), // ochre
  Color(0xFF4A7A35), // matcha
  Color(0xFF2A5DA4), // cobalt
  Color(0xFF0F5C56), // petrol
  Color(0xFF6D1F3E), // plum
  Color(0xFF8B3A2E), // pencil red
  Color(0xFF2E5230), // forest
  Color(0xFF1B1814), // ink
  Color(0xFF7C6E4F), // taupe
  Color(0xFF34588E), // navy
  Color(0xFF8A5A2B), // bronze
];

const _kPaper = Color(0xFFF5EFE0); // shared cream paper (matches privacy/terms)
const _kInk   = Color(0xFF1B1814);
const _kRule  = Color(0xFFDCD3BC);

// ─── Public widget ────────────────────────────────────────────────────────────

/// Manuscript-proof cover. Identical layout for every book; the only
/// difference between two books is the colour of the thin top strip.
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
    // Single source of variation: the strip colour. Mix title and author so
    // two books with the same first letter don't share a strip.
    final hash  = (title.hashCode ^ (author.hashCode << 1)).abs();
    final strip = _kStripPalette[hash % _kStripPalette.length];

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(builder: (_, c) {
        final h     = c.maxHeight;
        final scale = (h / 240).clamp(0.55, 1.4);
        final pad   = 14.0 * scale;

        return Container(
          color: _kPaper,
          padding: EdgeInsets.fromLTRB(pad, pad * 1.6, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top coloured strip — the only thing that changes per book.
              Container(height: 3 * scale, color: strip),

              const Spacer(flex: 3),

              // Title — Garamond italic, large, takes whatever vertical
              // space it needs. Up to 5 lines so long titles fit gracefully.
              Text(
                title,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ebGaramond(
                  fontSize: 18 * scale,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: _kInk,
                  height: 1.22,
                  letterSpacing: -0.2,
                ),
              ),

              SizedBox(height: 12 * scale),

              // Thin pencil rule — matches the divider on privacy/terms.
              Container(height: 0.7, color: _kRule),

              SizedBox(height: 10 * scale),

              // Author — small caps, ink, generous letter-spacing.
              Text(
                _lastNameFirst(author).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 8.5 * scale,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                  letterSpacing: 2.2 * scale,
                  height: 1,
                ),
              ),

              const Spacer(flex: 5),
            ],
          ),
        );
      }),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Returns the author rendered surname-first if there are at least two
/// tokens — "EBOU MIRA" reads more like a bibliography entry than
/// "MIRA EBOU". Single-token names pass through unchanged.
String _lastNameFirst(String author) {
  final parts = author.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return author;
  return '${parts.last} ${parts.first}';
}
