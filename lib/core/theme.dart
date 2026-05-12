import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Warm parchment — niente violetto. Tutto declinato sui toni della carta:
// Chapel White → Cream Beige → Antique Veil → Deep Taupe → Taupe →
// Rich Sabel → Burnt Oak.

class MarginaliaColors {
  // Backgrounds
  static const background      = Color(0xFFF1EEE7); // Chapel White
  static const surface         = Color(0xFFEAE3D3); // Cream Beige
  static const surfaceElevated = Color(0xFFF6F1E5); // tra Chapel e Cream

  // Text hierarchy
  static const ink      = Color(0xFF261E1D); // Burnt Oak
  static const inkMuted = Color(0xFF7B6F67); // Deep Taupe
  static const inkFaint = Color(0xFFB0A89E); // mid-tone

  // Warm accent — Taupe family (labels, light interactions)
  static const sienna      = Color(0xFF7F785B); // Taupe
  static const siennaLight = Color(0xFF9E9578);
  static const siennaFaint = Color(0xFFEDE5D5);

  // Primary action — Rich Sabel (CTA, gradient start)
  static const primary     = Color(0xFF4C3B3A); // Rich Sabel
  static const primaryDark = Color(0xFF261E1D); // Burnt Oak
  static const primaryFaint = Color(0xFFE8DED0);

  // Borders / dividers
  static const rule      = Color(0xFFD3CEC2); // Antique Veil
  static const ruleFaint = Color(0xFFE8E3D8);

  // Kindle highlight tints (warm-leaning)
  static const highlightAmber     = Color(0xFFF6E4B0);
  static const highlightSky       = Color(0xFFD4DCEA);
  static const highlightRose      = Color(0xFFEED4D8);
  static const highlightTangerine = Color(0xFFF5DBC0);

  // Legacy aliases (still referenced in some widgets)
  static const accent      = primary;
  static const accentLight = sienna;
  static const text        = ink;
  static const textMuted   = inkMuted;
  static const border      = rule;
  static const violet      = primary;       // alias per codice vecchio
  static const violetDark  = primaryDark;
  static const violetFaint = primaryFaint;
  static const highlightYellow = highlightAmber;
  static const highlightBlue   = highlightSky;
  static const highlightPink   = highlightRose;
  static const highlightOrange = highlightTangerine;
}

// ─── Tipografia ───────────────────────────────────────────────────────────────

class MarginaliaTextStyles {
  static TextStyle get highlightBody => GoogleFonts.lora(
        fontSize: 17,
        height: 1.85,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
      );

  static TextStyle get highlightBodySmall => GoogleFonts.lora(
        fontSize: 15,
        height: 1.75,
        color: MarginaliaColors.ink,
        letterSpacing: 0.1,
      );

  static TextStyle get bookTitle => GoogleFonts.lora(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.2,
        height: 1.3,
      );

  static TextStyle get bookTitleLarge => GoogleFonts.lora(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.5,
        height: 1.25,
      );

  static TextStyle get bookAuthor => const TextStyle(
        fontSize: 11,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w500,
        height: 1.4,
      );

  static TextStyle get label => const TextStyle(
        fontSize: 11,
        color: MarginaliaColors.inkFaint,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 2.2,
      );

  static TextStyle get quoteDecor => GoogleFonts.lora(
        fontSize: 96,
        height: 0.7,
        color: MarginaliaColors.siennaFaint,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get indexNumber => GoogleFonts.lora(
        fontSize: 13,
        color: MarginaliaColors.sienna,
        fontWeight: FontWeight.w400,
        height: 1,
      );
}

// ─── Decorazioni condivise ────────────────────────────────────────────────────

class MarginaliaDecorations {
  static BoxDecoration card({Color? color, double radius = 16}) => BoxDecoration(
        color: color ?? MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.rule, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12261E1D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x08261E1D),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      );

  // Hero card — Rich Sabel → Burnt Oak (caldo profondo)
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF4C3B3A), Color(0xFF261E1D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Color(0x33261E1D),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );

  // Auth / Jam header — Burnt Oak → Rich Sabel → Taupe
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF261E1D), Color(0xFF4C3B3A), Color(0xFF7F785B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Cover libri — solo toni caldi
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF7F785B), // Taupe
      Color(0xFF4C3B3A), // Rich Sabel
      Color(0xFF7B6F67), // Deep Taupe
      Color(0xFF261E1D), // Burnt Oak
      Color(0xFF9E9578), // siennaLight
      Color(0xFF6B5D54), // intermedio
      Color(0xFF8E7B5E), // dorato caldo
      Color(0xFF5C4A40), // marrone tabacco
    ];
    return covers[title.hashCode.abs() % covers.length];
  }
}

// ─── ThemeData ────────────────────────────────────────────────────────────────

ThemeData buildMarginaliaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      surface: MarginaliaColors.background,
      surfaceContainerHighest: MarginaliaColors.surface,
      primary: MarginaliaColors.primary,
      onPrimary: Color(0xFFF1EEE7),
      secondary: MarginaliaColors.sienna,
      onSurface: MarginaliaColors.ink,
      outline: MarginaliaColors.rule,
    ),
    scaffoldBackgroundColor: MarginaliaColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: Color(0x10261E1D),
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarginaliaColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: MarginaliaColors.primaryFaint,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: MarginaliaColors.primary, size: 22);
        }
        return const IconThemeData(color: MarginaliaColors.inkMuted, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: MarginaliaColors.primary,
            letterSpacing: 0.4,
          );
        }
        return const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: MarginaliaColors.inkMuted,
          letterSpacing: 0.4,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: MarginaliaColors.rule,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: MarginaliaColors.rule),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB54848), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB54848), width: 2),
      ),
      hintStyle: const TextStyle(color: MarginaliaColors.inkFaint, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MarginaliaColors.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarginaliaColors.primaryFaint,
      labelStyle: const TextStyle(
        color: MarginaliaColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MarginaliaColors.ink,
      contentTextStyle: const TextStyle(color: Color(0xFFF1EEE7), fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
