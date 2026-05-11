import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Modern literary: warm-white base, electric violet primary, amber pops.
// Inspired by Readwise/Matter — clean but not sterile.

class MarginaliaColors {
  // Backgrounds
  static const background = Color(0xFFF9F8F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);

  // Text
  static const ink = Color(0xFF09090B);
  static const inkMuted = Color(0xFF71717A);
  static const inkFaint = Color(0xFFA1A1AA);

  // Violet — primary accent
  static const sienna = Color(0xFF7C3AED);
  static const siennaLight = Color(0xFF8B5CF6);
  static const siennaFaint = Color(0xFFEDE9FE);

  // Amber — warm pop
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFEF3C7);

  // Coral — secondary highlight
  static const coral = Color(0xFFE07A5F);

  // Rules & borders
  static const rule = Color(0xFFE4E4E7);
  static const ruleFaint = Color(0xFFF4F4F5);

  // Kindle highlight palette
  static const highlightAmber = Color(0xFFFEF3C7);
  static const highlightSky = Color(0xFFDBEAFE);
  static const highlightRose = Color(0xFFFCE7F3);
  static const highlightTangerine = Color(0xFFFFEDD5);

  // Aliases for existing widgets
  static const accent = sienna;
  static const accentLight = siennaLight;
  static const text = ink;
  static const textMuted = inkMuted;
  static const border = rule;
  static const highlightYellow = highlightAmber;
  static const highlightBlue = highlightSky;
  static const highlightPink = highlightRose;
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

  static TextStyle get bookTitle => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.3,
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
        color: MarginaliaColors.inkFaint,
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
        color: MarginaliaColors.siennaLight,
        fontWeight: FontWeight.w400,
        height: 1,
      );
}

// ─── Decorazioni condivise ────────────────────────────────────────────────────

class MarginaliaDecorations {
  static BoxDecoration card({Color? color, double radius = 16}) => BoxDecoration(
        color: color ?? MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.ruleFaint, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      );

  // Hero card — violet gradient
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Color(0x337C3AED),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );

  // Auth/jam gradient header
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF6D28D9), Color(0xFF7C3AED), Color(0xFF8B5CF6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Cover libro — vivid modern colors
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF7C3AED), // violet
      Color(0xFF0F766E), // teal
      Color(0xFFB45309), // amber dark
      Color(0xFF1D4ED8), // blue
      Color(0xFF9333EA), // purple
      Color(0xFF0E7490), // cyan
      Color(0xFFBE185D), // pink
      Color(0xFF15803D), // green
    ];
    return covers[title.hashCode.abs() % covers.length];
  }
}

// ─── ThemeData ────────────────────────────────────────────────────────────────

ThemeData buildMarginaliaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      surface: MarginaliaColors.background,
      surfaceContainerHighest: MarginaliaColors.surface,
      primary: MarginaliaColors.sienna,
      onPrimary: Colors.white,
      secondary: MarginaliaColors.siennaLight,
      onSurface: MarginaliaColors.ink,
      outline: MarginaliaColors.rule,
    ),
    scaffoldBackgroundColor: MarginaliaColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: const Color(0x10000000),
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarginaliaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: MarginaliaColors.siennaFaint,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: MarginaliaColors.sienna, size: 22);
        }
        return const IconThemeData(color: MarginaliaColors.inkFaint, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: MarginaliaColors.sienna,
            letterSpacing: 0.4,
          );
        }
        return const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: MarginaliaColors.inkFaint,
          letterSpacing: 0.4,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: MarginaliaColors.ruleFaint,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: MarginaliaColors.ruleFaint),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.ruleFaint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.sienna, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
      ),
      hintStyle: const TextStyle(color: MarginaliaColors.inkFaint, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MarginaliaColors.sienna),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColors.sienna,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.sienna,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarginaliaColors.siennaFaint,
      labelStyle: const TextStyle(
        color: MarginaliaColors.sienna,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MarginaliaColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
