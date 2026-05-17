import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Matcha — verde cerimonia giapponese. Sfondo pergamena con leggero tono verde,
// testo verde-foresta profondo, accent matcha mid-tone.
//
// Matcha Parchment → Pale Matcha → Matcha Cream → Moss → Deep Matcha → Forest Night

class MarginaliaColors {
  // Backgrounds — pergamena tintata matcha
  static const background      = Color(0xFFF2F5EA); // Matcha Parchment
  static const surface         = Color(0xFFE5ECDA); // Pale Matcha
  static const surfaceElevated = Color(0xFFF7F9F2); // quasi bianco, tono verde

  // Text hierarchy — verde scuro foresta
  static const ink      = Color(0xFF1A2614); // Forest Night (quasi nero-verde)
  static const inkMuted = Color(0xFF506040); // Moss Muted
  static const inkFaint = Color(0xFF8FA07A); // Light Moss

  // Accent — matcha family
  static const sienna      = Color(0xFF6B8C4E); // Matcha Mid
  static const siennaLight = Color(0xFF8AAD68);
  static const siennaFaint = Color(0xFFDAEBC5);

  // Primary action — deep matcha (CTA, header gradient, nav bar)
  static const primary      = Color(0xFF3A5C28); // Deep Matcha
  static const primaryDark  = Color(0xFF1E3314); // Forest Night
  static const primaryFaint = Color(0xFFD0E4B8); // very light matcha tint

  // Borders / dividers
  static const rule      = Color(0xFFC5D5AA); // Matcha Border
  static const ruleFaint = Color(0xFFDBE8C8);

  // Kindle highlight tints — versioni matcha delle tinte Kindle
  static const highlightAmber     = Color(0xFFF0E8A0); // giallo-lime
  static const highlightSky       = Color(0xFFC0D8C0); // sage-verde
  static const highlightRose      = Color(0xFFEED4D8); // rosa (invariato per contrasto)
  static const highlightTangerine = Color(0xFFEDD8A8); // ambra calda

  // Legacy aliases — invariati strutturalmente, cambiano solo i valori sopra
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
            color: Color(0x121A2614),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x081A2614),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      );

  // Hero card — Deep Matcha → Forest Night
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF3A5C28), Color(0xFF1A2614)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Color(0x331A2614),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );

  // Auth / header gradient — Forest Night → Deep Matcha → Matcha Mid
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1E3314), Color(0xFF3A5C28), Color(0xFF6B8C4E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // Cover libri — toni matcha variati per varietà
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF4A7035), // matcha medio
      Color(0xFF3A5C28), // deep matcha
      Color(0xFF506040), // moss
      Color(0xFF1E3314), // forest night
      Color(0xFF6B8C4E), // matcha light
      Color(0xFF2D4B1E), // mid-dark
      Color(0xFF5C7840), // olive
      Color(0xFF3D5C2A), // matcha warm
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
      onPrimary: Color(0xFFF2F5EA),
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
      shadowColor: Color(0x101A2614),
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.ink,
        letterSpacing: -0.4,
      ),
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
        borderSide: const BorderSide(color: Color(0xFF8B2E2E), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8B2E2E), width: 2),
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
        foregroundColor: const Color(0xFFF2F5EA),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF2F5EA),
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
      contentTextStyle: const TextStyle(color: Color(0xFFF2F5EA), fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
