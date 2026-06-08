// ─── Reading Wrapped — story slides ──────────────────────────────────────────
//
// Each [WrappedStorySlide] is one full-screen, gorgeous editorial card. A slide
// owns:
//   • its gradient (drawn from the profile Pantone palette, reused here),
//   • [buildBody]      — the on-screen full-screen layout,
//   • [buildShareBody] — a re-staged, centred variant for the 1080×1920 share
//     render (the share frame adds the brand mark + footer around it),
//   • [shareCaption]   — text included alongside a shared image.
//
// Keeping the content in one place means the viewer and the share card never
// drift apart. Everything is built from a single [WrappedData].

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../library/book_cover.dart';
import 'wrapped_data.dart';

const Color _cream = Color(0xFFF5F2EC);
const Color _creamSoft = Color(0xCCF5F2EC); // ~80%
const Color _creamFaint = Color(0x99F5F2EC); // ~60%

// ─── Gradient palette ─────────────────────────────────────────────────────────
//
// Re-staged from the profile palette (_kGradients in my_profile_screen.dart):
// the same eight Pantone-derived 3-stop gradients, so Wrapped feels like part of
// the same world. Each slide is assigned one, cycling through the set, so a
// session reads as a cohesive but varied sequence.

const List<List<Color>> _kWrappedGradients = [
  [Color(0xFF694852), Color(0xFF3F1521), Color(0xFF2C0F17)], // Vintage Wine
  [Color(0xFF476173), Color(0xFF13344C), Color(0xFF0D2435)], // Navy
  [Color(0xFF686B53), Color(0xFF3E4123), Color(0xFF2B2E18)], // Chive
  [Color(0xFF8C766C), Color(0xFF6C5042), Color(0xFF4C382E)], // Cocoa Brown
  [Color(0xFF3A6624), Color(0xFF254D16), Color(0xFF18330E)], // Matcha (brand)
  [Color(0xFFA5BECD), Color(0xFF6E93A8), Color(0xFF4E6E84)], // Powder Blue (deepened)
  [Color(0xFFB0BAA3), Color(0xFF7E8772), Color(0xFF5E6B4F)], // Reseda (deepened)
];

List<Color> wrappedGradientAt(int index) =>
    _kWrappedGradients[index % _kWrappedGradients.length];

// ─── Slide model ─────────────────────────────────────────────────────────────

class WrappedStorySlide {
  const WrappedStorySlide({
    required this.gradient,
    required this.buildBody,
    required this.buildShareBody,
    required this.shareCaption,
  });

  final List<Color> gradient;

  /// The on-screen, full-screen layout (already inside a SafeArea-aware frame).
  final WidgetBuilder buildBody;

  /// A centred re-stage for the 1080×1920 share render.
  final WidgetBuilder buildShareBody;

  /// Text to include alongside a shared image.
  final String shareCaption;
}

// ─── Slide builder ───────────────────────────────────────────────────────────

/// Builds the ordered list of slides for [data]. Returns 5–7 slides depending
/// on what the data supports (e.g. the top-book slide is skipped if there is no
/// book with highlights in the period).
List<WrappedStorySlide> buildWrappedSlides(
  BuildContext context,
  WrappedData data,
) {
  final l10n = context.l10n;
  final slides = <WrappedStorySlide>[];
  var g = 0; // rotating gradient index

  String periodLabel() {
    switch (data.period) {
      case WrappedPeriod.week:
        return l10n.wrappedPeriodWeek;
      case WrappedPeriod.month:
        return l10n.wrappedPeriodMonth;
      case WrappedPeriod.allTime:
        return l10n.wrappedPeriodAllTime;
    }
  }

  // ── 1. Intro ──────────────────────────────────────────────────────────────
  slides.add(WrappedStorySlide(
    gradient: wrappedGradientAt(g++),
    shareCaption: '${l10n.wrappedIntroTitle(periodLabel())} — marginalia.app',
    buildBody: (ctx) => _IntroLayout(
      eyebrow: l10n.wrappedIntroEyebrow,
      title: l10n.wrappedIntroTitle(periodLabel()),
      subtitle: l10n.wrappedIntroSubtitle,
      big: false,
    ),
    buildShareBody: (ctx) => _IntroLayout(
      eyebrow: l10n.wrappedIntroEyebrow,
      title: l10n.wrappedIntroTitle(periodLabel()),
      subtitle: l10n.wrappedIntroSubtitle,
      big: true,
    ),
  ));

  // ── 2. Highlights big-number ───────────────────────────────────────────────
  final highlightsCaption = l10n.wrappedShareHighlightsCaption(
      data.highlightsInPeriod, periodLabel());
  slides.add(WrappedStorySlide(
    gradient: wrappedGradientAt(g++),
    shareCaption: highlightsCaption,
    buildBody: (ctx) => _BigNumberLayout(
      number: '${data.highlightsInPeriod}',
      label: l10n.wrappedHighlightsLabel,
      footnote: data.period == WrappedPeriod.allTime
          ? null
          : l10n.wrappedHighlightsFootnote(data.highlightsTotal),
      big: false,
    ),
    buildShareBody: (ctx) => _BigNumberLayout(
      number: '${data.highlightsInPeriod}',
      label: l10n.wrappedHighlightsLabel,
      footnote: data.period == WrappedPeriod.allTime
          ? null
          : l10n.wrappedHighlightsFootnote(data.highlightsTotal),
      big: true,
    ),
  ));

  // ── 3. Books + days read (a duo of stats) ──────────────────────────────────
  slides.add(WrappedStorySlide(
    gradient: wrappedGradientAt(g++),
    shareCaption: l10n.wrappedShareBooksCaption(data.booksInPeriod),
    buildBody: (ctx) => _DuoStatLayout(
      valueA: '${data.booksInPeriod}',
      labelA: l10n.wrappedBooksLabel,
      valueB: '${data.daysRead}',
      labelB: l10n.wrappedDaysReadLabel,
      caption: data.busiestDay != null
          ? l10n.wrappedBusiestDay(_weekdayName(l10n, data.busiestDay!))
          : null,
      big: false,
    ),
    buildShareBody: (ctx) => _DuoStatLayout(
      valueA: '${data.booksInPeriod}',
      labelA: l10n.wrappedBooksLabel,
      valueB: '${data.daysRead}',
      labelB: l10n.wrappedDaysReadLabel,
      caption: data.busiestDay != null
          ? l10n.wrappedBusiestDay(_weekdayName(l10n, data.busiestDay!))
          : null,
      big: true,
    ),
  ));

  // ── 4. Most-highlighted book (skip if none) ────────────────────────────────
  if (data.topBook != null) {
    final book = data.topBook!;
    slides.add(WrappedStorySlide(
      gradient: wrappedGradientAt(g++),
      shareCaption:
          l10n.wrappedShareTopBookCaption(book.title, book.count),
      buildBody: (ctx) => _TopBookLayout(
        title: book.title,
        author: book.author,
        count: book.count,
        countLabel: l10n.wrappedTopBookCount(book.count),
        eyebrow: l10n.wrappedTopBookEyebrow,
        big: false,
      ),
      buildShareBody: (ctx) => _TopBookLayout(
        title: book.title,
        author: book.author,
        count: book.count,
        countLabel: l10n.wrappedTopBookCount(book.count),
        eyebrow: l10n.wrappedTopBookEyebrow,
        big: true,
      ),
    ));
  }

  // ── 5. Standout highlight (skip if none) ───────────────────────────────────
  if (data.standoutHighlight != null &&
      data.standoutHighlight!.trim().isNotEmpty) {
    final quote = data.standoutHighlight!.trim();
    slides.add(WrappedStorySlide(
      gradient: wrappedGradientAt(g++),
      shareCaption: '“${_truncate(quote, 140)}” — marginalia.app',
      buildBody: (ctx) => _QuoteLayout(
        eyebrow: l10n.wrappedStandoutEyebrow,
        quote: quote,
        title: data.standoutBookTitle,
        author: data.standoutBookAuthor,
        big: false,
      ),
      buildShareBody: (ctx) => _QuoteLayout(
        eyebrow: l10n.wrappedStandoutEyebrow,
        quote: quote,
        title: data.standoutBookTitle,
        author: data.standoutBookAuthor,
        big: true,
      ),
    ));
  }

  // ── 6. Review streak (always — flame, even at 0 it's a gentle nudge) ───────
  slides.add(WrappedStorySlide(
    gradient: wrappedGradientAt(g++),
    shareCaption: l10n.wrappedShareStreakCaption(data.reviewStreak),
    buildBody: (ctx) => _StreakLayout(
      streak: data.reviewStreak,
      label: l10n.wrappedStreakLabel,
      caption: data.reviewStreak > 0
          ? l10n.wrappedStreakCaption(data.reviewStreak)
          : l10n.wrappedStreakZero,
      big: false,
    ),
    buildShareBody: (ctx) => _StreakLayout(
      streak: data.reviewStreak,
      label: l10n.wrappedStreakLabel,
      caption: data.reviewStreak > 0
          ? l10n.wrappedStreakCaption(data.reviewStreak)
          : l10n.wrappedStreakZero,
      big: true,
    ),
  ));

  // ── 7. Personality + summary (final card) ─────────────────────────────────
  final persona = _personalityLabel(l10n, data.personality);
  final personaDesc = _personalityDesc(l10n, data.personality);
  slides.add(WrappedStorySlide(
    gradient: wrappedGradientAt(g++),
    shareCaption: '${l10n.wrappedPersonaShareCaption(persona)} — marginalia.app',
    buildBody: (ctx) => _SummaryLayout(
      eyebrow: l10n.wrappedSummaryEyebrow,
      persona: persona,
      personaDesc: personaDesc,
      highlights: data.highlightsInPeriod,
      books: data.booksInPeriod,
      daysRead: data.daysRead,
      streak: data.reviewStreak,
      l10n: l10n,
      big: false,
    ),
    buildShareBody: (ctx) => _SummaryLayout(
      eyebrow: l10n.wrappedSummaryEyebrow,
      persona: persona,
      personaDesc: personaDesc,
      highlights: data.highlightsInPeriod,
      books: data.booksInPeriod,
      daysRead: data.daysRead,
      streak: data.reviewStreak,
      l10n: l10n,
      big: true,
    ),
  ));

  return slides;
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

String _weekdayName(dynamic l10n, int weekday) {
  switch (weekday) {
    case 1:
      return l10n.wrappedWeekdayMon;
    case 2:
      return l10n.wrappedWeekdayTue;
    case 3:
      return l10n.wrappedWeekdayWed;
    case 4:
      return l10n.wrappedWeekdayThu;
    case 5:
      return l10n.wrappedWeekdayFri;
    case 6:
      return l10n.wrappedWeekdaySat;
    default:
      return l10n.wrappedWeekdaySun;
  }
}

String _personalityLabel(dynamic l10n, ReadingPersonality p) {
  switch (p) {
    case ReadingPersonality.theMarginalia:
      return l10n.wrappedPersonaMarginalia;
    case ReadingPersonality.theDevourer:
      return l10n.wrappedPersonaDevourer;
    case ReadingPersonality.theCollector:
      return l10n.wrappedPersonaCollector;
    case ReadingPersonality.theDeepDiver:
      return l10n.wrappedPersonaDeepDiver;
    case ReadingPersonality.theDabbler:
      return l10n.wrappedPersonaDabbler;
    case ReadingPersonality.theMarathoner:
      return l10n.wrappedPersonaMarathoner;
  }
}

String _personalityDesc(dynamic l10n, ReadingPersonality p) {
  switch (p) {
    case ReadingPersonality.theMarginalia:
      return l10n.wrappedPersonaMarginaliaDesc;
    case ReadingPersonality.theDevourer:
      return l10n.wrappedPersonaDevourerDesc;
    case ReadingPersonality.theCollector:
      return l10n.wrappedPersonaCollectorDesc;
    case ReadingPersonality.theDeepDiver:
      return l10n.wrappedPersonaDeepDiverDesc;
    case ReadingPersonality.theDabbler:
      return l10n.wrappedPersonaDabblerDesc;
    case ReadingPersonality.theMarathoner:
      return l10n.wrappedPersonaMarathonerDesc;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Layout widgets — each beautiful on its own, sized fluidly (`big` doubles the
// type for the 1080×1920 share render).
// ═══════════════════════════════════════════════════════════════════════════

double _s(bool big, double v) => big ? v * 1.9 : v;

class _IntroLayout extends StatelessWidget {
  const _IntroLayout({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.big,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow(eyebrow, big: big),
        SizedBox(height: _s(big, 18)),
        Text(
          title,
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 40),
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: _cream,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: _s(big, 16)),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 15),
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: _creamSoft,
          ),
        ),
      ],
    );
  }
}

class _BigNumberLayout extends StatelessWidget {
  const _BigNumberLayout({
    required this.number,
    required this.label,
    required this.footnote,
    required this.big,
  });
  final String number;
  final String label;
  final String? footnote;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            number,
            style: GoogleFonts.ebGaramond(
              fontSize: _s(big, 120),
              height: 0.9,
              fontWeight: FontWeight.w700,
              color: _cream,
              letterSpacing: -2,
            ),
          ),
        ),
        SizedBox(height: _s(big, 8)),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 14),
            fontWeight: FontWeight.w800,
            color: _cream,
            letterSpacing: 3.0,
          ),
        ),
        if (footnote != null) ...[
          SizedBox(height: _s(big, 14)),
          Text(
            footnote!,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: _s(big, 13),
              fontWeight: FontWeight.w500,
              color: _creamFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _DuoStatLayout extends StatelessWidget {
  const _DuoStatLayout({
    required this.valueA,
    required this.labelA,
    required this.valueB,
    required this.labelB,
    required this.caption,
    required this.big,
  });
  final String valueA;
  final String labelA;
  final String valueB;
  final String labelB;
  final String? caption;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatLine(value: valueA, label: labelA, big: big),
        SizedBox(height: _s(big, 28)),
        _StatLine(value: valueB, label: labelB, big: big),
        if (caption != null) ...[
          SizedBox(height: _s(big, 26)),
          Container(
            width: _s(big, 28),
            height: 2,
            color: _creamFaint,
          ),
          SizedBox(height: _s(big, 14)),
          Text(
            caption!,
            style: GoogleFonts.manrope(
              fontSize: _s(big, 14),
              fontWeight: FontWeight.w600,
              color: _creamSoft,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine(
      {required this.value, required this.label, required this.big});
  final String value;
  final String label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 66),
            height: 0.9,
            fontWeight: FontWeight.w700,
            color: _cream,
            letterSpacing: -1,
          ),
        ),
        SizedBox(width: _s(big, 14)),
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: _s(big, 13),
              fontWeight: FontWeight.w800,
              color: _creamSoft,
              letterSpacing: 2.0,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBookLayout extends StatelessWidget {
  const _TopBookLayout({
    required this.title,
    required this.author,
    required this.count,
    required this.countLabel,
    required this.eyebrow,
    required this.big,
  });
  final String title;
  final String author;
  final int count;
  final String countLabel;
  final String eyebrow;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final coverSize = _s(big, 130);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Eyebrow(eyebrow, big: big, centered: true),
        SizedBox(height: _s(big, 24)),
        // The procedural cover, in the app's house style.
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_s(big, 12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(90),
                blurRadius: _s(big, 24),
                offset: Offset(0, _s(big, 8)),
              ),
            ],
          ),
          child: SizedBox(
            width: coverSize,
            height: coverSize * 1.5,
            child: BookEditorialCover(
              title: title,
              author: author,
              borderRadius: BorderRadius.all(Radius.circular(_s(big, 12))),
            ),
          ),
        ),
        SizedBox(height: _s(big, 22)),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 24),
            height: 1.15,
            fontWeight: FontWeight.w600,
            color: _cream,
          ),
        ),
        if (author.isNotEmpty) ...[
          SizedBox(height: _s(big, 6)),
          Text(
            author.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: _s(big, 11),
              fontWeight: FontWeight.w600,
              color: _creamFaint,
              letterSpacing: 1.6,
            ),
          ),
        ],
        SizedBox(height: _s(big, 16)),
        Text(
          countLabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 14),
            fontWeight: FontWeight.w700,
            color: _creamSoft,
          ),
        ),
      ],
    );
  }
}

class _QuoteLayout extends StatelessWidget {
  const _QuoteLayout({
    required this.eyebrow,
    required this.quote,
    required this.title,
    required this.author,
    required this.big,
  });
  final String eyebrow;
  final String quote;
  final String? title;
  final String? author;
  final bool big;

  double get _quoteFontSize {
    final len = quote.length;
    if (len <= 90) return 26;
    if (len <= 160) return 23;
    if (len <= 240) return 20;
    return 17;
  }

  @override
  Widget build(BuildContext context) {
    final safeTitle = (title ?? '').trim();
    final safeAuthor = (author ?? '').trim();
    final excerpt =
        quote.length > 320 ? '${quote.substring(0, 320).trimRight()}…' : quote;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Eyebrow(eyebrow, big: big, centered: true),
        SizedBox(height: _s(big, 16)),
        Text(
          '“',
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 80),
            height: 0.7,
            fontWeight: FontWeight.w600,
            color: _creamFaint,
          ),
        ),
        SizedBox(height: _s(big, 6)),
        Flexible(
          child: Text(
            excerpt,
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: _s(big, _quoteFontSize),
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: _cream,
              letterSpacing: 0.15,
            ),
          ),
        ),
        if (safeTitle.isNotEmpty) ...[
          SizedBox(height: _s(big, 24)),
          Container(width: _s(big, 30), height: 1.4, color: _creamFaint),
          SizedBox(height: _s(big, 16)),
          Text(
            safeTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ebGaramond(
              fontSize: _s(big, 16),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              color: _creamSoft,
              height: 1.3,
            ),
          ),
          if (safeAuthor.isNotEmpty) ...[
            SizedBox(height: _s(big, 6)),
            Text(
              safeAuthor.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: _s(big, 10),
                fontWeight: FontWeight.w600,
                color: _creamFaint,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _StreakLayout extends StatelessWidget {
  const _StreakLayout({
    required this.streak,
    required this.label,
    required this.caption,
    required this.big,
  });
  final int streak;
  final String label;
  final String caption;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final lit = streak > 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.local_fire_department_rounded,
          size: _s(big, 84),
          color: lit ? const Color(0xFFFFB24A) : _creamFaint,
        ),
        SizedBox(height: _s(big, 8)),
        Text(
          '$streak',
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 96),
            height: 0.9,
            fontWeight: FontWeight.w700,
            color: _cream,
            letterSpacing: -2,
          ),
        ),
        SizedBox(height: _s(big, 6)),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 14),
            fontWeight: FontWeight.w800,
            color: _cream,
            letterSpacing: 3.0,
          ),
        ),
        SizedBox(height: _s(big, 16)),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 14),
            fontWeight: FontWeight.w500,
            color: _creamSoft,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({
    required this.eyebrow,
    required this.persona,
    required this.personaDesc,
    required this.highlights,
    required this.books,
    required this.daysRead,
    required this.streak,
    required this.l10n,
    required this.big,
  });
  final String eyebrow;
  final String persona;
  final String personaDesc;
  final int highlights;
  final int books;
  final int daysRead;
  final int streak;
  final dynamic l10n;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow(eyebrow, big: big),
        SizedBox(height: _s(big, 14)),
        Text(
          persona,
          style: GoogleFonts.ebGaramond(
            fontSize: _s(big, 36),
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: _cream,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: _s(big, 12)),
        Text(
          personaDesc,
          style: GoogleFonts.manrope(
            fontSize: _s(big, 14),
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: _creamSoft,
          ),
        ),
        SizedBox(height: _s(big, 28)),
        // Compact recap chips.
        Wrap(
          spacing: _s(big, 10),
          runSpacing: _s(big, 10),
          children: [
            _RecapChip(
                value: '$highlights', label: l10n.wrappedHighlightsLabel, big: big),
            _RecapChip(value: '$books', label: l10n.wrappedBooksLabel, big: big),
            _RecapChip(
                value: '$daysRead', label: l10n.wrappedDaysReadLabel, big: big),
            if (streak > 0)
              _RecapChip(
                  value: '$streak', label: l10n.wrappedStreakLabel, big: big),
          ],
        ),
      ],
    );
  }
}

class _RecapChip extends StatelessWidget {
  const _RecapChip(
      {required this.value, required this.label, required this.big});
  final String value;
  final String label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(big, 14),
        vertical: _s(big, 9),
      ),
      decoration: BoxDecoration(
        color: _cream.withAlpha(28),
        borderRadius: BorderRadius.circular(_s(big, 12)),
        border: Border.all(color: _cream.withAlpha(40), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: GoogleFonts.ebGaramond(
              fontSize: _s(big, 22),
              fontWeight: FontWeight.w700,
              color: _cream,
              height: 1,
            ),
          ),
          SizedBox(width: _s(big, 6)),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: _s(big, 9),
              fontWeight: FontWeight.w700,
              color: _creamSoft,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {required this.big, this.centered = false});
  final String text;
  final bool big;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: GoogleFonts.manrope(
        fontSize: _s(big, 12),
        fontWeight: FontWeight.w800,
        color: _creamSoft,
        letterSpacing: 2.6,
      ),
    );
  }
}
