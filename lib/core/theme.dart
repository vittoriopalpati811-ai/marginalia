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
  static const surface         = Color(0xFFE8EDDD); // Pale Matcha (leggermente più freddo)
  static const surfaceElevated = Color(0xFFF8FAF3); // quasi bianco, tono verde

  // Text hierarchy — verde scuro foresta
  static const ink      = Color(0xFF1A2614); // Forest Night (quasi nero-verde)
  static const inkMuted = Color(0xFF4E5E3A); // Moss Muted (più caldo del precedente)
  static const inkFaint = Color(0xFF8A9E72); // Light Moss

  // Accent — matcha family
  static const sienna      = Color(0xFF5C7A40); // Matcha Mid (leggermente più scuro)
  static const siennaLight = Color(0xFF7DA05A);
  static const siennaFaint = Color(0xFFD6E8BC);

  // Primary action — deep matcha (CTA, header gradient, nav bar)
  static const primary      = Color(0xFF3A5C28); // Deep Matcha
  static const primaryDark  = Color(0xFF1E3314); // Forest Night
  static const primaryFaint = Color(0xFFCDE0AA); // very light matcha tint

  // Borders / dividers
  static const rule      = Color(0xFFBECFA2); // Matcha Border
  static const ruleFaint = Color(0xFFD6E5BF);

  // Kindle highlight tints — versioni matcha delle tinte Kindle
  static const highlightAmber     = Color(0xFFF0E8A0);
  static const highlightSky       = Color(0xFFC0D8C0);
  static const highlightRose      = Color(0xFFEED4D8);
  static const highlightTangerine = Color(0xFFEDD8A8);

  // Legacy aliases
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
        color: MarginaliaColors.inkMuted,
        letterSpacing: 3.0,
      );

  /// Wordmark principale dell'app in intestazioni gradient.
  static TextStyle get wordmark => GoogleFonts.ebGaramond(
        fontSize: 26,
        fontWeight: FontWeight.w500,
        color: const Color(0xFFF1EEE7),
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
  /// Card standard — superficie palegreen, bordo sottile, ombra paper-like.
  static BoxDecoration card({Color? color, double radius = 16}) => BoxDecoration(
        color: color ?? MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.rule, width: 0.8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E1A2614),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
          BoxShadow(
            color: Color(0x061A2614),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      );

  /// Hero card — Deep Matcha → Forest Night
  static const BoxDecoration heroCard = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF3A5C28), Color(0xFF1A2614)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.all(Radius.circular(20)),
    boxShadow: [
      BoxShadow(
        color: Color(0x2C1A2614),
        blurRadius: 20,
        offset: Offset(0, 6),
      ),
    ],
  );

  /// Auth / header gradient — Forest Night → Deep Matcha → Matcha Mid
  static const BoxDecoration gradientHeader = BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF1E3314), Color(0xFF3A5C28), Color(0xFF5C7A40)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Card stile "pagina aperta" — sfondo leggermente più caldo, bordi sottili,
  /// zero ombra. Usato per le quote editoriali.
  static BoxDecoration pageCard({double radius = 12}) => BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: MarginaliaColors.ruleFaint, width: 0.8),
      );

  /// Cover libri — toni matcha variati per varietà
  static Color bookCoverColor(String title) {
    const covers = [
      Color(0xFF4A7035), // matcha medio
      Color(0xFF3A5C28), // deep matcha
      Color(0xFF4E5E3A), // moss
      Color(0xFF1E3314), // forest night
      Color(0xFF5C7A40), // matcha light
      Color(0xFF2D4B1E), // mid-dark
      Color(0xFF506040), // olive
      Color(0xFF3D5C2A), // matcha warm
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
      surfaceContainerHighest: MarginaliaColors.surface,
      primary: MarginaliaColors.primary,
      onPrimary: Color(0xFFF2F5EA),
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
      shadowColor: const Color(0x101A2614),
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
      thickness: 0.8,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: MarginaliaColors.rule, width: 0.8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MarginaliaColors.rule, width: 0.8),
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
        foregroundColor: const Color(0xFFF2F5EA),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        foregroundColor: const Color(0xFFF2F5EA),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        color: const Color(0xFFF2F5EA),
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
