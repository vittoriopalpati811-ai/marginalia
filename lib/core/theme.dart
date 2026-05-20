import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
//
// Marginalia iOS Premium — bianco caldo con accent matcha.
//
// Ispirazione: Apple Books, Kindle iOS, Reeder 5.
// Palette: near-white background, pure-white cards, matcha green accent.
// The greenish tint on backgrounds was too "Android material" — dropped.
// Neutral surfaces let the literary typography and matcha accent breathe.

class MarginaliaColors {
  // Backgrounds — bianco caldo neutro (iOS standard)
  static const background      = Color(0xFFFAFAF8); // near-white, warm tint
  static const surface         = Color(0xFFFFFFFF); // pure white cards
  static const surfaceElevated = Color(0xFFF5F5F3); // slightly recessed surface

  // Text hierarchy — near-black caldo
  static const ink      = Color(0xFF1C1C1A); // near-black, warm
  static const inkMuted = Color(0xFF5C5C58); // mid-gray, warm
  static const inkFaint = Color(0xFF9C9C97); // light-gray, warm

  // Accent — matcha green (più saturo su bianco funziona meglio)
  static const sienna      = Color(0xFF4A7A35); // matcha mid
  static const siennaLight = Color(0xFF6A9E52); // matcha light
  static const siennaFaint = Color(0xFFE0EDD4); // very light matcha tint

  // Primary action — deep matcha
  static const primary      = Color(0xFF3A6624); // deep matcha CTA
  static const primaryDark  = Color(0xFF254D16); // darker, for pressed states
  static const primaryFaint = Color(0xFFEBF4E4); // chip backgrounds, badges

  // Borders / dividers — neutral sottilissimi (iOS-style)
  static const rule      = Color(0x17000000); // ~9% black — barely visible
  static const ruleFaint = Color(0x0D000000); // ~5% black — structural only

  // Kindle highlight tints — adattate a sfondo bianco (più trasparenti)
  static const highlightAmber     = Color(0xFFFFF3C4);
  static const highlightSky       = Color(0xFFD4EBF7);
  static const highlightRose      = Color(0xFFFFE0E8);
  static const highlightTangerine = Color(0xFFFFE8C8);

  // Legacy aliases — invariati per compatibilità
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
//
// Font system:
//   EB Garamond  → tutto il contenuto letterario (highlights, quote, titoli libri)
//                  Garamond è letteralmente nato per la stampa di libri (1530).
//   Barlow Condensed → label, sezioni, header editoriali (contrasto netto col serif)
//   Barlow       → UI labels, autori, metadati, testo funzionale

class MarginaliaTextStyles {

  // ── Highlight / quote text (il cuore dell'app) ────────────────────────────

  /// Testo principale di un highlight — EB Garamond italic grande.
  /// Solo per la schermata di dettaglio (hero moment, grande e ariosa).
  static TextStyle get highlightBody => GoogleFonts.ebGaramond(
        fontSize: 20,
        height: 1.88,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.1,
      );

  /// Versione più piccola per card e strip — regular per leggibilità.
  static TextStyle get highlightBodySmall => GoogleFonts.ebGaramond(
        fontSize: 16,
        height: 1.72,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.05,
      );

  /// Versione compatta per card molto piccole — regular per leggibilità.
  static TextStyle get highlightBodyMicro => GoogleFonts.ebGaramond(
        fontSize: 13,
        height: 1.6,
        color: MarginaliaColors.ink,
        fontWeight: FontWeight.w400,
      );

  // ── Titoli libri ──────────────────────────────────────────────────────────

  static TextStyle get bookTitle => GoogleFonts.ebGaramond(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.2,
        height: 1.3,
      );

  static TextStyle get bookTitleLarge => GoogleFonts.ebGaramond(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.5,
        height: 1.2,
      );

  // ── Autori (Barlow — contrasto con il serif) ──────────────────────────────

  static TextStyle get bookAuthor => GoogleFonts.barlowCondensed(
        fontSize: 11,
        color: MarginaliaColors.inkMuted,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w500,
        height: 1.4,
      );

  // ── Label UI (Barlow Condensed uppercase — editoriale) ───────────────────

  /// Label piccola per metadati, tag, badge.
  static TextStyle get label => GoogleFonts.barlow(
        fontSize: 11,
        color: MarginaliaColors.inkFaint,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      );

  /// Header di sezione — ALL CAPS Barlow Condensed con tracking largo.
  /// Dà il senso di una rivista letteraria.
  static TextStyle get sectionTitle => GoogleFonts.barlowCondensed(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: MarginaliaColors.inkFaint,
        letterSpacing: 3.0,
      );

  /// Wordmark principale dell'app — scuro su sfondo chiaro (header non-gradient).
  static TextStyle get wordmark => GoogleFonts.ebGaramond(
        fontSize: 26,
        fontWeight: FontWeight.w500,
        color: MarginaliaColors.ink,
        letterSpacing: -0.3,
        height: 1,
      );

  /// Wordmark per contesti scuri (header gradient, hero card).
  static TextStyle get wordmarkLight => GoogleFonts.ebGaramond(
        fontSize: 26,
        fontWeight: FontWeight.w500,
        color: const Color(0xFFF5F2EC),
        letterSpacing: -0.3,
        height: 1,
      );

  // ── Display / decorativo ──────────────────────────────────────────────────

  /// Virgoletta decorativa grande.
  static TextStyle get quoteDecor => GoogleFonts.ebGaramond(
        fontSize: 96,
        height: 0.7,
        color: MarginaliaColors.siennaFaint,
        fontWeight: FontWeight.w700,
      );

  /// Numero indice (per liste numerate di highlight).
  static TextStyle get indexNumber => GoogleFonts.ebGaramond(
        fontSize: 13,
        color: MarginaliaColors.sienna,
        fontWeight: FontWeight.w400,
        height: 1,
      );
}

// ─── Decorazioni condivise ────────────────────────────────────────────────────

class MarginaliaDecorations {
  /// Card standard iOS-style — bianco puro, bordo quasi invisibile, ombra morbida.
  static BoxDecoration card({Color? color, double radius = 14}) => BoxDecoration(
        color: color ?? MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.rule, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 20,
            offset: Offset(0, 2),
          ),
        ],
      );

  /// Hero card — Deep Matcha → Forest Night (invariato, usato per jam/hero)
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF3A6624), Color(0xFF1C3A10)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(18)),
    boxShadow: [
      BoxShadow(
        color: Color(0x283A6624),
        blurRadius: 24,
        offset: Offset(0, 6),
      ),
    ],
  );

  /// Header gradient — mantenuto per le schermate che lo usano ancora.
  /// Più sottile e maturo rispetto alla versione verde brillante precedente.
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF254D16), Color(0xFF3A6624), Color(0xFF4A7A35)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Card "pagina aperta" — sfondo leggermente recessed, senza ombra.
  static BoxDecoration pageCard({double radius = 12}) => BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.rule, width: 0.5),
      );

  /// Cover libri — toni matcha variati, leggermente desaturati su bianco
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

// ─── Costanti di spaziatura ───────────────────────────────────────────────────
// Scala 4pt: 4, 8, 12, 16, 24, 32, 48, 64

class MarginaliaSpacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;
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
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: const Color(0x14000000),
      centerTitle: false,
      titleTextStyle: GoogleFonts.ebGaramond(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.ink,
        letterSpacing: -0.3,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MarginaliaColors.rule,
      space: 1,
      thickness: 0.5,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: MarginaliaColors.rule, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8B2E2E), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8B2E2E), width: 1.5),
      ),
      hintStyle: GoogleFonts.barlow(
        color: MarginaliaColors.inkFaint,
        fontSize: 15,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MarginaliaColors.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.barlow(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.barlow(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarginaliaColors.primaryFaint,
      labelStyle: GoogleFonts.barlow(
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
      contentTextStyle: GoogleFonts.barlow(
        color: const Color(0xFFF5F2EC),
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
