import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Per-jam theme colour. A jam can store a `theme_color` hex string; the jam
/// detail screen tints its cards / boxes / accents with it. A null/empty value
/// means "use the default sage", in which case the screen keeps the exact
/// current look (primary / primaryDark / primaryFaint). For a custom colour we
/// derive a darker accent + a faint tint from the picked base in HSL space so
/// any colour yields a cohesive family.
class JamColor {
  /// Parse a stored hex string ("#C0CFB2", "C0CFB2" or "0xFFC0CFB2") into a
  /// Color. Returns [fallback] on null / empty / invalid input.
  static Color parse(String? hex, {Color fallback = ScriptaColors.primary}) {
    if (hex == null) return fallback;
    var s = hex.trim().replaceAll('#', '').replaceAll('0x', '').toUpperCase();
    if (s.isEmpty) return fallback;
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return fallback;
    final v = int.tryParse(s, radix: 16);
    return v == null ? fallback : Color(v);
  }

  /// A darker, slightly more saturated shade — for accent text/icons.
  static Color darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
        .toColor();
  }

  /// A very light, desaturated tint — for chip / box backgrounds.
  static Color faint(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + 0.28).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
        .toColor();
  }
}

// ─── Palette — Airbnb-clean (refined 2026-05-27) ───────────────────────────
//
// Design intent:
//   • Background: warm off-white, barely tinted green — gives the page a
//     calm, "paper" feel without announcing brand color.
//   • Surfaces: pure white cards with NO border — depth comes from a single
//     subtle shadow (Airbnb's signature lift).
//   • Type ink: graphite, never pure black, tinted slightly green.
//   • Accent: deep matcha for primary CTAs (the green is the brand promise).

class ScriptaColors {
  // Backgrounds — warm, paper-like
  static const background      = Color(0xFFFAFAF7); // warm off-white, "paper"
  static const surface         = Color(0xFFFFFFFF); // pure white cards
  static const surfaceElevated = Color(0xFFF2F2EF); // recessed inputs, chip bg

  // Text hierarchy — graphite tinted green, never pure black
  static const ink      = Color(0xFF1B1F1B); // hero text
  static const inkMuted = Color(0xFF6F756E); // body / secondary (Airbnb-spec #717171 tinted green)
  static const inkFaint = Color(0xFFB0B5AE); // tertiary / hints

  // Sage green — the brand color (#c0cfb2, founder-chosen), used as the single
  // green across the WHOLE app. It is light, so foregrounds on top of it use a
  // dark ink and accent text uses the darker `primaryDark` sage for legibility.
  static const sienna      = Color(0xFFC0CFB2);
  static const siennaLight = Color(0xFFD2DEC9);
  static const siennaFaint = Color(0xFFECF1E6);

  // Primary — sage fill + a readable darker sage for accent text/icons.
  static const primary      = Color(0xFFC0CFB2);
  static const primaryDark  = Color(0xFF8AA178);
  static const primaryFaint = Color(0xFFECF1E6);

  // Borders / rules — used SPARINGLY. Airbnb avoids borders; prefer shadow.
  static const rule      = Color(0xFFE6E6E1);
  static const ruleFaint = Color(0xFFEFEFEC);

  // Brand red — bookmark accent + destructive actions (delete/remove/danger).
  static const red = Color(0xFFB94A41);

  // Kindle highlight tints (unchanged)
  static const highlightAmber     = Color(0xFFFFF3C4);
  static const highlightSky       = Color(0xFFD4EBF7);
  static const highlightRose      = Color(0xFFFFE0E8);
  static const highlightTangerine = Color(0xFFFFE8C8);

  // Legacy aliases — unchanged for compatibility
  static const accent       = primary;
  static const accentLight  = sienna;
  static const text         = ink;
  static const textMuted    = inkMuted;
  static const border       = rule;
  static const violet       = primary;
  static const violetDark   = primaryDark;
  static const violetFaint  = primaryFaint;
  static const highlightYellow = highlightAmber;
  static const highlightBlue   = highlightSky;
  static const highlightPink   = highlightRose;
  static const highlightOrange = highlightTangerine;
}

// ─── Typography ───────────────────────────────────────────────────────────────
//
// Two-font system:
//
//   Manrope     → all UI: nav labels, headings, buttons, metadata, section titles
//                 Geometric sans with subtle rounded apertures.
//                 Spirit: Airbnb Cereal without the trademark.
//                 Weights used: 400 · 500 · 600 · 700 · 800
//
//   EB Garamond → highlight body text ONLY — the literary heart of the app.
//                 Creates an intentional, legible contrast: clean UI vs. warm type.
//
// Scale (≈1.33× ratio): 10 · 12 · 14 · 16 · 20 · 26 · 34

class ScriptaTextStyles {

  // ── Highlight content — EB Garamond italic ────────────────────────────────

  /// Large highlight body — hero detail screen.
  // Roman, not italic. Garamond italic at body sizes (15-22pt) is
  // visually dense and slows reading — italic is a *display* feature in
  // editorial typography (titles, pull-quotes, attribution), not body
  // copy. Highlights are the user's most-read content in the app, so
  // they get the most legible setting: roman, slightly heavier weight
  // (500 instead of 400) for better screen rendering, same generous
  // line-height. The decorative quote-mark above the highlight carries
  // the "literary" register on its own; the text itself just needs to
  // be readable.
  static TextStyle get highlightBody => GoogleFonts.ebGaramond(
        fontSize: 22,
        height: 1.78,
        color: ScriptaColors.ink,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      );

  /// Small highlight body — cards and list items.
  static TextStyle get highlightBodySmall => GoogleFonts.ebGaramond(
        fontSize: 17,
        height: 1.68,
        color: ScriptaColors.ink,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.05,
      );

  /// Micro highlight — very compact contexts.
  static TextStyle get highlightBodyMicro => GoogleFonts.ebGaramond(
        fontSize: 14,
        height: 1.6,
        color: ScriptaColors.ink,
        fontWeight: FontWeight.w400,
      );

  // ── Book titles — Manrope ─────────────────────────────────────────────────

  static TextStyle get bookTitle => GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ScriptaColors.ink,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get bookTitleLarge => GoogleFonts.manrope(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: ScriptaColors.ink,
        letterSpacing: -0.7,
        height: 1.15,
      );

  // ── Authors — Manrope spaced uppercase ───────────────────────────────────

  static TextStyle get bookAuthor => GoogleFonts.manrope(
        fontSize: 10,
        color: ScriptaColors.inkMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        height: 1.4,
      );

  // ── UI labels — Manrope ──────────────────────────────────────────────────

  /// Small metadata label — dates, counts, tags.
  static TextStyle get label => GoogleFonts.manrope(
        fontSize: 11,
        color: ScriptaColors.inkFaint,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w500,
      );

  /// Section header — ALL CAPS, spaced, magazine-style.
  static TextStyle get sectionTitle => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: ScriptaColors.inkFaint,
        letterSpacing: 1.0,
      );

  // ── Airbnb-clean hierarchy ──────────────────────────────────────────────
  //
  // Use these for new layouts. The contrast steps follow Airbnb's
  // scale: hero (28-32) → section (20-22) → body (14-15) → label (11-12).

  /// Screen-level hero title. e.g. "Your library", "Reading stats".
  /// Bold sans, tight tracking, almost-black ink. NO subtitle below this
  /// without 4-8px of breathing room.
  static TextStyle get heroTitle => GoogleFonts.manrope(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: ScriptaColors.ink,
        letterSpacing: -0.6,
        height: 1.15,
      );

  /// Section title within a screen. e.g. "Picked for you", "Recent".
  /// Bold sans, dark, tighter than hero.
  static TextStyle get sectionTitleClean => GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ScriptaColors.ink,
        letterSpacing: -0.3,
        height: 1.25,
      );

  /// Subtitle / supporting text under a hero or section title.
  static TextStyle get subtitle => GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: ScriptaColors.inkMuted,
        letterSpacing: 0,
        height: 1.45,
      );

  /// Body copy — default reading size, used for most paragraphs.
  static TextStyle get body => GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: ScriptaColors.ink,
        letterSpacing: -0.1,
        height: 1.45,
      );

  // ── Wordmark ─────────────────────────────────────────────────────────────

  static TextStyle get wordmark => GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: ScriptaColors.ink,
        letterSpacing: -0.5,
        height: 1,
      );

  static TextStyle get wordmarkLight => GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: const Color(0xFFF5F2EC),
        letterSpacing: -0.5,
        height: 1,
      );

  // ── Decorative ────────────────────────────────────────────────────────────

  static TextStyle get quoteDecor => GoogleFonts.ebGaramond(
        fontSize: 96,
        height: 0.7,
        color: ScriptaColors.siennaFaint,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get indexNumber => GoogleFonts.manrope(
        fontSize: 12,
        color: ScriptaColors.sienna,
        fontWeight: FontWeight.w700,
        height: 1,
      );
}

// ─── Decorations ─────────────────────────────────────────────────────────────

class ScriptaDecorations {
  /// Card — pure white, Airbnb-style layered shadow, no border.
  /// Two-layer shadow: tight ambient + soft diffuse, like Airbnb listings.
  static BoxDecoration card({Color? color, double radius = 16}) => BoxDecoration(
        color: color ?? ScriptaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000), // tight, 5% opacity
            blurRadius: 6,
            spreadRadius: 0,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x0A000000), // soft halo, 4% opacity
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset(0, 6),
          ),
        ],
      );

  /// Quiet card — even lower elevation, used for inline list items where
  /// you want gentle separation without competing with the screen content.
  /// Single very-soft shadow, no border, 14px radius default.
  static BoxDecoration quietCard({Color? color, double radius = 14}) => BoxDecoration(
        color: color ?? ScriptaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // ~3% opacity
            blurRadius: 14,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ],
      );

  /// Hero card — deep matcha gradient (unchanged)
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF3A6624), Color(0xFF1C3A10)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Color(0x303A6624),
        blurRadius: 32,
        offset: Offset(0, 10),
      ),
    ],
  );

  /// Gradient header — for jam/hero screens
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF254D16), Color(0xFF3A6624), Color(0xFF4A7A35)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Status-bar overlay for screens whose TOP is a dark [gradientHeader].
  ///
  /// The global default (set once in main.dart) uses DARK status-bar icons,
  /// which is correct over the cream content screens but renders the iOS
  /// clock/battery nearly invisible against the dark green gradient — the
  /// reported "sovrapposizione grafica" at the top of the screen. Plain
  /// Container headers (no AppBar) don't auto-correct this the way Material's
  /// AppBar does, so each must wrap its header in an
  /// `AnnotatedRegion<SystemUiOverlayStyle>` with this value to switch the
  /// system icons to light (white).
  static const SystemUiOverlayStyle lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark, // iOS: dark background → light icons
    statusBarIconBrightness: Brightness.light, // Android
  );

  /// Page card — recessed, no shadow (list item variant)
  static BoxDecoration pageCard({double radius = 12}) => BoxDecoration(
        color: ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Curated mood-board palette (Pantone references from the user) — reused
  /// across avatars, profile backgrounds and procedural book covers for a
  /// richer, more varied look than the previous matcha-only set.
  static const Color pVintageWine = Color(0xFF3F1521);
  static const Color pPastelYellow = Color(0xFFF2E6B1);
  static const Color pReseda = Color(0xFFA1AD92);
  static const Color pChive = Color(0xFF3E4123);
  static const Color pPowderBlue = Color(0xFF94B2C4);
  static const Color pDeepNavy = Color(0xFF13344C);
  static const Color pCocoa = Color(0xFF6C5042);
  static const Color pCoconut = Color(0xFFF0EDE5);

  /// Book cover / avatar / profile background colour — richer multi-hue palette
  /// (deep tones, so white initials stay legible) inspired by the mood-board.
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF3F1521), // vintage wine
      Color(0xFF3E4123), // chive (deep olive)
      Color(0xFF13344C), // deep navy
      Color(0xFF6C5042), // cocoa brown
      Color(0xFF254D16), // matcha deep (brand)
      Color(0xFF4A7035), // matcha (brand)
      Color(0xFF4E6E84), // powder-blue (deepened)
      Color(0xFF5E6B4F), // reseda (deepened)
    ];
    return covers[title.hashCode.abs() % covers.length];
  }
}

// ─── Spacing ─────────────────────────────────────────────────────────────────
// 4pt scale: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64

class ScriptaSpacing {
  static const xs   =  4.0;
  static const sm   =  8.0;
  static const md   = 12.0;
  static const lg   = 16.0;
  static const xl   = 24.0;
  static const xxl  = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;
}

// ─── Dark palette ─────────────────────────────────────────────────────────────

class ScriptaColorsDark {
  static const background      = Color(0xFF111411); // very dark, green-tinted OLED
  static const surface         = Color(0xFF1C211C);
  static const surfaceElevated = Color(0xFF252C25);

  static const ink      = Color(0xFFF2F5F2);
  static const inkMuted = Color(0xFFA8ADA8);
  static const inkFaint = Color(0xFF6A706A);

  static const sienna      = Color(0xFF6ABF4B);
  static const siennaLight = Color(0xFF8BD468);
  static const siennaFaint = Color(0xFF1A3A10);

  static const primary      = Color(0xFF52A832);
  static const primaryDark  = Color(0xFF3A7A22);
  static const primaryFaint = Color(0xFF183A10);

  static const rule      = Color(0xFF282E28);
  static const ruleFaint = Color(0xFF1E231E);
}

// ─── ThemeData ────────────────────────────────────────────────────────────────

ThemeData buildScriptaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      surface: ScriptaColors.background,
      surfaceContainerHighest: ScriptaColors.surfaceElevated,
      primary: ScriptaColors.primary,
      onPrimary: ScriptaColors.ink,
      secondary: ScriptaColors.sienna,
      onSurface: ScriptaColors.ink,
      outline: ScriptaColors.rule,
    ),
    scaffoldBackgroundColor: ScriptaColors.background,

    // ── AppBar ──────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: ScriptaColors.background,
      foregroundColor: ScriptaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.3,
      shadowColor: const Color(0x0A000000),
      centerTitle: false,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: ScriptaColors.ink,
        letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(
        color: ScriptaColors.ink,
        size: 24,
      ),
    ),

    // ── Divider ─────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: ScriptaColors.rule,
      space: 1,
      thickness: 0.5,
    ),

    // ── Card ────────────────────────────────────────────────────────────────
    // Airbnb: no border, shadow-only elevation
    cardTheme: CardTheme(
      color: ScriptaColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    // ── Input ───────────────────────────────────────────────────────────────
    // Airbnb: filled, fully rounded, NO visible border at rest
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ScriptaColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
            color: ScriptaColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF8B2E2E), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Color(0xFF8B2E2E), width: 1.5),
      ),
      hintStyle: GoogleFonts.manrope(
        color: ScriptaColors.inkFaint,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: GoogleFonts.manrope(
        color: ScriptaColors.inkMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),

    // ── Text selection ──────────────────────────────────────────────────────
    // Without this, Flutter web renders the highlight as the primary matcha
    // at ~40% opacity AND the drag handles at 100% opacity — producing the
    // "two greens" effect the user reported (a soft matcha rectangle with
    // dark matcha dots on top of it).
    //
    // We commit to the app's core metaphor: text selection IS a highlighter
    // mark. The selection background is the same warm amber used for
    // Kindle highlights elsewhere in the app, and the drag handles match
    // it with a deeper ochre — same color story, full saturation, no more
    // tone-on-tone matcha. The cursor stays matcha so it still reads as
    // "the brand is acting on this field."
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor:          ScriptaColors.primary,
      selectionColor:       Color(0x99FFE066),   // highlighter amber @ ~60%
      selectionHandleColor: Color(0xFFB07F0F),   // deep ochre — readable handles
    ),

    // ── Buttons ─────────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ScriptaColors.primaryDark,
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ScriptaColors.primary,
        foregroundColor: ScriptaColors.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ScriptaColors.primary,
        foregroundColor: ScriptaColors.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ScriptaColors.ink,
        side: const BorderSide(color: ScriptaColors.rule, width: 1.5),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── Chip ────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: ScriptaColors.primaryFaint,
      labelStyle: GoogleFonts.manrope(
        color: ScriptaColors.primaryDark,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    // Sage-green (brand) instead of black, dark ink text for contrast, and a
    // bottom inset that floats it ABOVE the liquid-glass bottom nav bar
    // (~64px bar + safe area) instead of overlapping it.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ScriptaColors.primary,
      contentTextStyle: GoogleFonts.manrope(
        color: ScriptaColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 5, 16, 100),
      elevation: 3,
    ),

    // ── ListTile ────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ScriptaColors.ink,
      ),
      subtitleTextStyle: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: ScriptaColors.inkMuted,
      ),
    ),
  );
}

ThemeData buildScriptaDarkTheme() {
  const cs = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: ScriptaColorsDark.primary,
    onPrimary: Colors.white,
    primaryContainer: ScriptaColorsDark.primaryFaint,
    secondary: ScriptaColorsDark.sienna,
    onSecondary: Colors.white,
    surface: ScriptaColorsDark.surface,
    onSurface: ScriptaColorsDark.ink,
    surfaceContainerHighest: ScriptaColorsDark.surfaceElevated,
    outline: ScriptaColorsDark.rule,
    outlineVariant: ScriptaColorsDark.ruleFaint,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: ScriptaColorsDark.background,
    appBarTheme: AppBarTheme(
      backgroundColor: ScriptaColorsDark.background,
      foregroundColor: ScriptaColorsDark.ink,
      elevation: 0,
      scrolledUnderElevation: 0.3,
      shadowColor: const Color(0x28000000),
      centerTitle: false,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: ScriptaColorsDark.ink,
        letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(
        color: ScriptaColorsDark.ink,
        size: 24,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ScriptaColorsDark.rule,
      space: 1,
      thickness: 0.5,
    ),
    cardTheme: CardTheme(
      color: ScriptaColorsDark.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ScriptaColorsDark.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
            color: ScriptaColorsDark.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFCF6679), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Color(0xFFCF6679), width: 1.5),
      ),
      hintStyle: GoogleFonts.manrope(
        color: ScriptaColorsDark.inkFaint,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: GoogleFonts.manrope(
        color: ScriptaColorsDark.inkMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),

    // Same highlighter selection as light theme — but slightly stronger
    // amber so it remains visible against the deep paper background.
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor:          ScriptaColorsDark.primary,
      selectionColor:       Color(0xB3FFE066),   // amber @ 70% for dark bg
      selectionHandleColor: Color(0xFFD4A017),   // ochre handles
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ScriptaColorsDark.primary,
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ScriptaColorsDark.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ScriptaColorsDark.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ScriptaColorsDark.ink,
        side: const BorderSide(color: ScriptaColorsDark.rule, width: 1.5),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ScriptaColorsDark.primaryFaint,
      labelStyle: GoogleFonts.manrope(
        color: ScriptaColorsDark.sienna,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ScriptaColors.primary,
      contentTextStyle: GoogleFonts.manrope(
        color: ScriptaColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 5, 16, 100),
      elevation: 3,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ScriptaColorsDark.ink,
      ),
      subtitleTextStyle: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: ScriptaColorsDark.inkMuted,
      ),
    ),
  );
}
