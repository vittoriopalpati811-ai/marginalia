import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Ispirazione: carta da lettera invecchiata, inchiostro di China, riviste
// letterarie anni '60. Non beige-generico: caldo ma sofisticato.

class MarginaliaColors {
  // Backgrounds
  static const background = Color(0xFFF7F4EF);  // pergamena fredda
  static const surface = Color(0xFFEFECE5);      // carta leggermente ombreggiata
  static const surfaceElevated = Color(0xFFFAF8F4); // carta "in luce"

  // Text
  static const ink = Color(0xFF1B1915);          // inchiostro quasi-nero, caldo
  static const inkMuted = Color(0xFF6A6355);     // inchiostro sbiadito
  static const inkFaint = Color(0xFFA39A8B);     // traccia leggera

  // Accents — famiglia terracotta/sienna
  static const sienna = Color(0xFF7A5C3E);       // accent principale
  static const siennaLight = Color(0xFFB08B68);  // accent chiaro
  static const siennaFaint = Color(0xFFE8D8C4);  // tint sottile

  // Rules & borders
  static const rule = Color(0xFFD9D3C8);         // linea tipografica
  static const ruleFaint = Color(0xFFEAE6DF);    // bordo sottilissimo

  // Kindle highlight palette — più raffinata dell'originale
  static const highlightAmber = Color(0xFFFFF0C2);
  static const highlightSky = Color(0xFFD6EAFF);
  static const highlightRose = Color(0xFFFFE0E6);
  static const highlightTangerine = Color(0xFFFFE8CC);

  // Alias per compatibilità con widget già scritti
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
//
// Due famiglie:
//   Lora       — serif, per il corpo degli highlight (lettura lenta)
//   DM Serif Display — serif display, per titoli grandi / capolettera
// UI chrome resta in system font per leggerezza.

class MarginaliaTextStyles {
  // Corpo highlight — lettura principale
  static TextStyle get highlightBody => GoogleFonts.lora(
        fontSize: 17,
        height: 1.82,
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

  // Titoli libro — peso medio, leggero tracking negativo
  static TextStyle get bookTitle => const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.4,
        height: 1.3,
      );

  static TextStyle get bookTitleLarge => GoogleFonts.lora(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.5,
        height: 1.25,
      );

  // Autore — maiuscoletto simulato via letterSpacing alto + small size
  static TextStyle get bookAuthor => const TextStyle(
        fontSize: 12,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w500,
        height: 1.4,
      );

  // Etichette
  static TextStyle get label => const TextStyle(
        fontSize: 11,
        color: MarginaliaColors.inkFaint,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w500,
      );

  // Intestazioni di sezione — small caps stile
  static TextStyle get sectionTitle => const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 2.0,
      );

  // Quote decorativa grande
  static TextStyle get quoteDecor => GoogleFonts.lora(
        fontSize: 96,
        height: 0.7,
        color: MarginaliaColors.siennaFaint,
        fontWeight: FontWeight.w700,
      );

  // Capolettera numerato
  static TextStyle get indexNumber => GoogleFonts.lora(
        fontSize: 13,
        color: MarginaliaColors.siennaLight,
        fontWeight: FontWeight.w400,
        height: 1,
      );
}

// ─── Decorazioni condivise ────────────────────────────────────────────────────

class MarginaliaDecorations {
  // Card standard
  static BoxDecoration card({Color? color, double radius = 14}) => BoxDecoration(
        color: color ?? MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.ruleFaint, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );

  // Card hero (daily highlight)
  static BoxDecoration heroCard = const BoxDecoration(
    color: MarginaliaColors.sienna,
    borderRadius: BorderRadius.all(Radius.circular(18)),
    boxShadow: [
      BoxShadow(
        color: Color(0x22000000),
        blurRadius: 16,
        offset: Offset(0, 6),
      ),
    ],
  );

  // Cover libro — basato su hash del titolo
  static Color bookCoverColor(String title) {
    final covers = [
      const Color(0xFFB5927A),
      const Color(0xFF8C9E8A),
      const Color(0xFF8A90A6),
      const Color(0xFFA68B6A),
      const Color(0xFF9E8AA0),
      const Color(0xFF7A9097),
      const Color(0xFFA69478),
      const Color(0xFF88967C),
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
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.5,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarginaliaColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: MarginaliaColors.siennaFaint,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      color: MarginaliaColors.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: MarginaliaColors.ruleFaint),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.sienna, width: 1.5),
      ),
      hintStyle: const TextStyle(color: MarginaliaColors.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.sienna,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarginaliaColors.surface,
      labelStyle: const TextStyle(
        color: MarginaliaColors.inkMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      side: const BorderSide(color: MarginaliaColors.rule),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MarginaliaColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
