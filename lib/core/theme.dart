import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette — Airbnb-clean (refined 2026-05-27) ───────────────────────────
//
// Design intent:
//   • Background: warm off-white, barely tinted green — gives the page a
//     calm, "paper" feel without announcing brand color.
//   • Surfaces: pure white cards with NO border — depth comes from a single
//     subtle shadow (Airbnb's signature lift).
//   • Type ink: graphite, never pure black, tinted slightly green.
//   • Accent: deep matcha for primary CTAs (the green is the brand promise).

class MarginaliaColors {
  // Backgrounds — warm, paper-like
  static const background      = Color(0xFFFAFAF7); // warm off-white, "paper"
  static const surface         = Color(0xFFFFFFFF); // pure white cards
  static const surfaceElevated = Color(0xFFF2F2EF); // recessed inputs, chip bg

  // Text hierarchy — graphite tinted green, never pure black
  static const ink      = Color(0xFF1B1F1B); // hero text
  static const inkMuted = Color(0xFF6F756E); // body / secondary (Airbnb-spec #717171 tinted green)
  static const inkFaint = Color(0xFFB0B5AE); // tertiary / hints

  // Matcha accent — the brand color
  static const sienna      = Color(0xFF4A7A35);
  static const siennaLight = Color(0xFF6A9E52);
  static const siennaFaint = Color(0xFFE4EFD9);

  // Primary CTA — deep matcha
  static const primary      = Color(0xFF3A6624);
  static const primaryDark  = Color(0xFF254D16);
  static const primaryFaint = Color(0xFFE8F3E1);

  // Borders / rules — used SPARINGLY. Airbnb avoids borders; prefer shadow.
  static const rule      = Color(0xFFE6E6E1);
  static const ruleFaint = Color(0xFFEFEFEC);

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

class MarginaliaTextStyles {

  // ── Highlight content — EB Garamond italic ────────────────────────────────

  /// Large highlight body — hero detail screen.
  static TextStyle get highlightBody => GoogleFonts.ebGaramond(
        fontSize: 22,
        height: 1.82,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.1,
      );

  /// Small highlight body — cards and list items.
  static TextStyle get highlightBodySmall => GoogleFonts.ebGaramond(
        fontSize: 17,
        height: 1.68,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.05,
      );

  /// Micro highlight — very compact contexts.
  static TextStyle get highlightBodyMicro => GoogleFonts.ebGaramond(
        fontSize: 14,
        height: 1.6,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
      );

  // ── Book titles — Manrope ─────────────────────────────────────────────────

  static TextStyle get bookTitle => GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get bookTitleLarge => GoogleFonts.manrope(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: MarginaliaColors.ink,
        letterSpacing: -0.7,
        height: 1.15,
      );

  // ── Authors — Manrope spaced uppercase ───────────────────────────────────

  static TextStyle get bookAuthor => GoogleFonts.manrope(
        fontSize: 10,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        height: 1.4,
      );

  // ── UI labels — Manrope ──────────────────────────────────────────────────

  /// Small metadata label — dates, counts, tags.
  static TextStyle get label => GoogleFonts.manrope(
        fontSize: 11,
        color: MarginaliaColors.inkFaint,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w500,
      );

  /// Section header — ALL CAPS, spaced, magazine-style.
  static TextStyle get sectionTitle => GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.inkFaint,
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
        color: MarginaliaColors.ink,
        letterSpacing: -0.6,
        height: 1.15,
      );

  /// Section title within a screen. e.g. "Picked for you", "Recent".
  /// Bold sans, dark, tighter than hero.
  static TextStyle get sectionTitleClean => GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.3,
        height: 1.25,
      );

  /// Subtitle / supporting text under a hero or section title.
  static TextStyle get subtitle => GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 0,
        height: 1.45,
      );

  /// Body copy — default reading size, used for most paragraphs.
  static TextStyle get body => GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: MarginaliaColors.ink,
        letterSpacing: -0.1,
        height: 1.45,
      );

  // ── Wordmark ─────────────────────────────────────────────────────────────

  static TextStyle get wordmark => GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: MarginaliaColors.ink,
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
        color: MarginaliaColors.siennaFaint,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get indexNumber => GoogleFonts.manrope(
        fontSize: 12,
        color: MarginaliaColors.sienna,
        fontWeight: FontWeight.w700,
        height: 1,
      );
}

// ─── Decorations ─────────────────────────────────────────────────────────────

class MarginaliaDecorations {
  /// Card — pure white, Airbnb-style layered shadow, no border.
  /// Two-layer shadow: tight ambient + soft diffuse, like Airbnb listings.
  static BoxDecoration card({Color? color, double radius = 16}) => BoxDecoration(
        color: color ?? MarginaliaColors.surface,
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
        color: color ?? MarginaliaColors.surface,
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

  /// Page card — recessed, no shadow (list item variant)
  static BoxDecoration pageCard({double radius = 12}) => BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Book cover — matcha-toned palette (unchanged)
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF4A7035),
      Color(0xFF3A6624),
      Color(0xFF4E5E3A),
      Color(0xFF254D16),
      Color(0xFF5C8040),
      Color(0xFF2D4B1E),
      Color(0xFF506040),
      Color(0xFF3D5C2A),
    ];
    return covers[title.hashCode.abs() % covers.length];
  }
}

// ─── Spacing ─────────────────────────────────────────────────────────────────
// 4pt scale: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64

class MarginaliaSpacing {
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

class MarginaliaColorsDark {
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

ThemeData buildMarginaliaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      surface: MarginaliaColors.background,
      surfaceContainerHighest: MarginaliaColors.surfaceElevated,
      primary: MarginaliaColors.primary,
      onPrimary: Colors.white,
      secondary: MarginaliaColors.sienna,
      onSurface: MarginaliaColors.ink,
      outline: MarginaliaColors.rule,
    ),
    scaffoldBackgroundColor: MarginaliaColors.background,

    // ── AppBar ──────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.3,
      shadowColor: const Color(0x0A000000),
      centerTitle: false,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: MarginaliaColors.ink,
        letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(
        color: MarginaliaColors.ink,
        size: 24,
      ),
    ),

    // ── Divider ─────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: MarginaliaColors.rule,
      space: 1,
      thickness: 0.5,
    ),

    // ── Card ────────────────────────────────────────────────────────────────
    // Airbnb: no border, shadow-only elevation
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
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
      fillColor: MarginaliaColors.surfaceElevated,
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
            color: MarginaliaColors.primary, width: 1.5),
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
        color: MarginaliaColors.inkFaint,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: GoogleFonts.manrope(
        color: MarginaliaColors.inkMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),

    // ── Buttons ─────────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MarginaliaColors.primary,
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
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
        backgroundColor: MarginaliaColors.primary,
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
        foregroundColor: MarginaliaColors.ink,
        side: const BorderSide(color: MarginaliaColors.rule, width: 1.5),
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
      backgroundColor: MarginaliaColors.primaryFaint,
      labelStyle: GoogleFonts.manrope(
        color: MarginaliaColors.primary,
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
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MarginaliaColors.ink,
      contentTextStyle: GoogleFonts.manrope(
        color: const Color(0xFFF5F5F5),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),

    // ── ListTile ────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
      ),
      subtitleTextStyle: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: MarginaliaColors.inkMuted,
      ),
    ),
  );
}

ThemeData buildMarginaliaDarkTheme() {
  const cs = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: MarginaliaColorsDark.primary,
    onPrimary: Colors.white,
    primaryContainer: MarginaliaColorsDark.primaryFaint,
    secondary: MarginaliaColorsDark.sienna,
    onSecondary: Colors.white,
    surface: MarginaliaColorsDark.surface,
    onSurface: MarginaliaColorsDark.ink,
    surfaceContainerHighest: MarginaliaColorsDark.surfaceElevated,
    outline: MarginaliaColorsDark.rule,
    outlineVariant: MarginaliaColorsDark.ruleFaint,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: MarginaliaColorsDark.background,
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColorsDark.background,
      foregroundColor: MarginaliaColorsDark.ink,
      elevation: 0,
      scrolledUnderElevation: 0.3,
      shadowColor: const Color(0x28000000),
      centerTitle: false,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: MarginaliaColorsDark.ink,
        letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(
        color: MarginaliaColorsDark.ink,
        size: 24,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MarginaliaColorsDark.rule,
      space: 1,
      thickness: 0.5,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColorsDark.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColorsDark.surfaceElevated,
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
            color: MarginaliaColorsDark.primary, width: 1.5),
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
        color: MarginaliaColorsDark.inkFaint,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      labelStyle: GoogleFonts.manrope(
        color: MarginaliaColorsDark.inkMuted,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MarginaliaColorsDark.primary,
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColorsDark.primary,
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
        backgroundColor: MarginaliaColorsDark.primary,
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
        foregroundColor: MarginaliaColorsDark.ink,
        side: const BorderSide(color: MarginaliaColorsDark.rule, width: 1.5),
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
      backgroundColor: MarginaliaColorsDark.primaryFaint,
      labelStyle: GoogleFonts.manrope(
        color: MarginaliaColorsDark.sienna,
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
      backgroundColor: MarginaliaColorsDark.surfaceElevated,
      contentTextStyle: GoogleFonts.manrope(
        color: MarginaliaColorsDark.ink,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: MarginaliaColorsDark.ink,
      ),
      subtitleTextStyle: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: MarginaliaColorsDark.inkMuted,
      ),
    ),
  );
}
