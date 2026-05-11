import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Warm parchment base — Chapel White backgrounds, Rich Sabel text,
// violet kept only for interactive CTAs and gradient headers.
//
// Base colors from reference palette:
//   Chapel White    #F1EEE7  (241,238,231)
//   Cream Beige     #EAE3D3  (234,227,211)
//   Antique Veil    #D3CEC2  (211,206,194)
//   Deep Taupe      #7B6F67  (123,111,103)
//   Taupe           #7F785B  (127,120,91)
//   Rich Sabel      #4C3B3A  (76,59,58)
//   Burnt Oak       #261E1D  (38,30,29)

class MarginaliaColors {
  // Backgrounds
  static const background   = Color(0xFFF1EEE7); // Chapel White
  static const surface      = Color(0xFFEAE3D3); // Cream Beige
  static const surfaceElevated = Color(0xFFEAE3D3);

  // Text hierarchy
  static const ink          = Color(0xFF261E1D); // Burnt Oak
  static const inkMuted     = Color(0xFF7B6F67); // Deep Taupe
  static const inkFaint     = Color(0xFFB0A89E); // mid-point, softer

  // Warm accent (sienna / taupe family)
  static const sienna       = Color(0xFF7F785B); // Taupe — labels, active nav
  static const siennaLight  = Color(0xFF9E9578); // lighter taupe
  static const siennaFaint  = Color(0xFFEDE5D5); // very light warm tint

  // Violet — kept only for gradient headers and primary CTA buttons
  static const violet       = Color(0xFF7C3AED);
  static const violetDark   = Color(0xFF4C1D95);
  static const violetFaint  = Color(0xFFEDE9FE);

  // Borders / dividers
  static const rule         = Color(0xFFD3CEC2); // Antique Veil
  static const ruleFaint    = Color(0xFFE8E3D8); // slightly lighter

  // Kindle highlight palette (kept warm)
  static const highlightAmber     = Color(0xFFFEF3C7);
  static const highlightSky       = Color(0xFFDBEAFE);
  static const highlightRose      = Color(0xFFFCE7F3);
  static const highlightTangerine = Color(0xFFFFEDD5);

  // Aliases for existing widgets that reference old names
  static const accent       = violet;
  static const accentLight  = Color(0xFF8B5CF6);
  static const text         = ink;
  static const textMuted    = inkMuted;
  static const border       = rule;
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

  // Hero card — violet gradient on warm base
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

  // Auth/jam/social gradient header — violet
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF6D28D9), Color(0xFF7C3AED), Color(0xFF8B5CF6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Book cover colors — warm literary tones + violet pop
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF7F785B), // Taupe
      Color(0xFF4C3B3A), // Rich Sabel
      Color(0xFF7C3AED), // Violet pop
      Color(0xFF0F766E), // Teal
      Color(0xFFB45309), // Amber dark
      Color(0xFF7B6F67), // Deep Taupe
      Color(0xFF6D28D9), // Violet dark
      Color(0xFF15803D), // Green
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
      primary: MarginaliaColors.violet,
      onPrimary: Colors.white,
      secondary: MarginaliaColors.sienna,
      onSurface: MarginaliaColors.ink,
      outline: MarginaliaColors.rule,
    ),
    scaffoldBackgroundColor: MarginaliaColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: const Color(0x10261E1D),
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
      fillColor: MarginaliaColors.siennaFaint,
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
        borderSide: const BorderSide(color: MarginaliaColors.violet, width: 2),
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
      style: TextButton.styleFrom(foregroundColor: MarginaliaColors.violet),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColors.violet,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.violet,
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
