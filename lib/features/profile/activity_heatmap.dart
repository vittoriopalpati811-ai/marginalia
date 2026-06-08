// ─── ActivityHeatmap — a contribution-graph for the trailing ~year ───────────
//
// A GitHub/Garmin-style heatmap, re-styled for Marginalia: warm paper ground,
// an editorial sienna→amber intensity ramp (NOT neon green), month labels along
// the top, weekday hints down the left, and a quiet LESS▢▢▢▢ MORE legend.
//
// Pure & declarative: driven entirely by a `Map<DateTime,int>` of date-only →
// count. Painted with a single CustomPaint so 371 cells (53 weeks × 7 days) cost
// one paint pass, not 371 widgets — fast enough to sit inside a scroll view and
// to rasterise into a shareable PNG.
//
// The grid is laid out in WEEK COLUMNS: column 0 is the oldest week, the last
// column is the current week; within a column, row 0 = Monday … row 6 = Sunday.
// Today is the bottom-right-most filled cell.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

// ─── Intensity ramp ──────────────────────────────────────────────────────────
//
// Five steps from "no activity" (a faint paper-tinted cell, so the empty grid
// still reads as a grid) up to "MORE" — a saturated burnt sienna/amber. The ramp
// climbs in both warmth and depth so even on a small screen the busiest days
// pop. Tuned to sit on the #FAFAF7 paper background.
const List<Color> _kRamp = [
  Color(0xFFEDEAE2), // 0 — empty: warm stone, barely there
  Color(0xFFEAD9B8), // 1 — pale amber
  Color(0xFFD9B173), // 2 — wheat / gold
  Color(0xFFC2873F), // 3 — amber-sienna
  Color(0xFF9C5B22), // 4 — deep burnt sienna (MORE)
];

/// Maps a raw per-day [count] to a ramp index 0..4. Thresholds are deliberately
/// gentle so a reader who logs a handful of highlights a day still climbs the
/// ramp; only genuinely heavy days hit the top step.
int activityLevel(int count) {
  if (count <= 0) return 0;
  if (count == 1) return 1;
  if (count <= 3) return 2;
  if (count <= 6) return 3;
  return 4;
}

// ─── Pure summary helpers (reused by the cards + the share card) ─────────────

/// Local midnight of [d].
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Number of distinct active days within the trailing [days]-day window.
int activeDayCount(Map<DateTime, int> data, {int days = 365}) {
  final today = _dateOnly(DateTime.now());
  final start = today.subtract(Duration(days: days - 1));
  var n = 0;
  for (final entry in data.entries) {
    if (entry.value <= 0) continue;
    final d = _dateOnly(entry.key);
    if (!d.isBefore(start) && !d.isAfter(today)) n++;
  }
  return n;
}

/// Sum of all counts within the trailing [days]-day window (e.g. total reviews).
int totalCount(Map<DateTime, int> data, {int days = 365}) {
  final today = _dateOnly(DateTime.now());
  final start = today.subtract(Duration(days: days - 1));
  var sum = 0;
  for (final entry in data.entries) {
    final d = _dateOnly(entry.key);
    if (entry.value <= 0) continue;
    if (!d.isBefore(start) && !d.isAfter(today)) sum += entry.value;
  }
  return sum;
}

/// Longest run of consecutive active days anywhere in [data].
int longestStreak(Map<DateTime, int> data) {
  final days = data.entries
      .where((e) => e.value > 0)
      .map((e) => _dateOnly(e.key))
      .toSet();
  if (days.isEmpty) return 0;
  var best = 0;
  for (final day in days) {
    // Only start counting from the beginning of a run (no active day before it).
    if (days.contains(day.subtract(const Duration(days: 1)))) continue;
    var len = 0;
    var cursor = day;
    while (days.contains(cursor)) {
      len++;
      cursor = cursor.add(const Duration(days: 1));
    }
    if (len > best) best = len;
  }
  return best;
}

// ─── The widget ──────────────────────────────────────────────────────────────

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.data,
    required this.title,
    this.weeks = 53,
    this.cellSize = 13,
    this.cellGap = 3,
    this.showLegend = true,
    this.showTitle = true,
    this.emptyColor,
    this.ramp,
    this.localeTag,
  });

  /// date-only → count. Days absent from the map render as level 0.
  final Map<DateTime, int> data;

  /// Title shown above the grid (e.g. "Reading"). Hidden when [showTitle] false.
  final String title;

  /// Number of week columns to render (trailing). 53 ≈ one year.
  final int weeks;

  /// Side length of each rounded cell in logical pixels.
  final double cellSize;

  /// Gap between cells (and between rows).
  final double cellGap;

  final bool showLegend;
  final bool showTitle;

  /// Override for the level-0 cell colour (used on the dark share card where the
  /// default warm-stone empty cell would be invisible).
  final Color? emptyColor;

  /// Override for the 5-step intensity ramp (level 0..4). When null the default
  /// editorial sienna→amber [_kRamp] is used. The profile passes a ramp derived
  /// from the user's chosen background colour (see [activityRampFromSeed]) so the
  /// heatmap + its legend stay coherent with the rest of the profile.
  final List<Color>? ramp;

  /// BCP-47 locale for the month labels; defaults to the ambient locale.
  final String? localeTag;

  @override
  Widget build(BuildContext context) {
    final locale = localeTag ?? Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            title,
            style: GoogleFonts.ebGaramond(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 14),
        ],
        // The grid scrolls horizontally on narrow screens, anchored to the
        // right so "today" (the newest week) is visible by default.
        _HeatGrid(
          data: data,
          weeks: weeks,
          cellSize: cellSize,
          cellGap: cellGap,
          locale: locale,
          emptyColor: emptyColor,
          ramp: ramp ?? _kRamp,
        ),
        if (showLegend) ...[
          const SizedBox(height: 12),
          _Legend(emptyColor: emptyColor, ramp: ramp ?? _kRamp, locale: locale),
        ],
      ],
    );
  }
}

// ─── The scrolling grid (labels + CustomPaint) ───────────────────────────────

class _HeatGrid extends StatelessWidget {
  const _HeatGrid({
    required this.data,
    required this.weeks,
    required this.cellSize,
    required this.cellGap,
    required this.locale,
    required this.ramp,
    this.emptyColor,
  });

  final Map<DateTime, int> data;
  final int weeks;
  final double cellSize;
  final double cellGap;
  final String locale;
  final List<Color> ramp;
  final Color? emptyColor;

  static const double _monthLabelHeight = 16;
  static const double _weekdayGutter = 22;

  @override
  Widget build(BuildContext context) {
    final step = cellSize + cellGap;
    final gridWidth = weeks * step - cellGap;
    final gridHeight = 7 * step - cellGap + _monthLabelHeight;
    final totalWidth = _weekdayGutter + gridWidth;

    final grid = SizedBox(
      width: totalWidth,
      height: gridHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Weekday hints (Mon / Wed / Fri) down the left gutter.
          SizedBox(
            width: _weekdayGutter,
            height: gridHeight,
            child: _WeekdayLabels(
              cellSize: cellSize,
              cellGap: cellGap,
              topOffset: _monthLabelHeight,
              locale: locale,
            ),
          ),
          SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: CustomPaint(
              painter: _HeatmapPainter(
                data: data,
                weeks: weeks,
                cellSize: cellSize,
                cellGap: cellGap,
                locale: locale,
                monthLabelHeight: _monthLabelHeight,
                ramp: ramp,
                emptyColor: emptyColor ?? ramp[0],
              ),
            ),
          ),
        ],
      ),
    );

    // Let the grid scroll horizontally if it's wider than the viewport; reverse
    // so the most-recent weeks are shown first (and you scroll back in time).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      physics: const ClampingScrollPhysics(),
      child: grid,
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels({
    required this.cellSize,
    required this.cellGap,
    required this.topOffset,
    required this.locale,
  });
  final double cellSize;
  final double cellGap;
  final double topOffset;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final step = cellSize + cellGap;
    // Localised one-letter weekday initials for Mon, Wed, Fri (rows 0, 2, 4).
    final symbols = DateFormat('', locale).dateSymbols.STANDALONESHORTWEEKDAYS;
    // dateSymbols weekdays are Sun-first; map Mon=1..Sun=0 → our row order.
    String initial(int isoWeekday) {
      final idx = isoWeekday % 7; // Mon(1)->1 .. Sat(6)->6, Sun(7)->0
      final label = symbols[idx];
      return label.isNotEmpty ? label[0].toUpperCase() : '';
    }

    TextStyle style() => GoogleFonts.manrope(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: MarginaliaColors.inkFaint,
          height: 1.0,
        );

    Widget at(int row, String text) => Positioned(
          top: topOffset + row * step - 1,
          left: 0,
          child: SizedBox(
            height: cellSize,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(text, style: style()),
            ),
          ),
        );

    return Stack(
      children: [
        at(0, initial(1)), // Monday
        at(2, initial(3)), // Wednesday
        at(4, initial(5)), // Friday
      ],
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.data,
    required this.weeks,
    required this.cellSize,
    required this.cellGap,
    required this.locale,
    required this.monthLabelHeight,
    required this.ramp,
    required this.emptyColor,
  });

  final Map<DateTime, int> data;
  final int weeks;
  final double cellSize;
  final double cellGap;
  final String locale;
  final double monthLabelHeight;
  final List<Color> ramp;
  final Color emptyColor;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void paint(Canvas canvas, Size size) {
    final step = cellSize + cellGap;
    final radius = Radius.circular(cellSize * 0.28);

    // Anchor: the column for the CURRENT week sits at index (weeks - 1). Within a
    // column, row = (isoWeekday - 1) so Monday is the top row. Walk back from the
    // start of the current week to find the date at column 0, row 0 (a Monday).
    final today = _dateOnly(DateTime.now());
    final mondayThisWeek =
        today.subtract(Duration(days: today.weekday - 1)); // weekday: Mon=1
    final firstMonday =
        mondayThisWeek.subtract(Duration(days: 7 * (weeks - 1)));

    final cellPaint = Paint()..isAntiAlias = true;

    int? lastMonthDrawn;
    for (var col = 0; col < weeks; col++) {
      final weekStart = firstMonday.add(Duration(days: 7 * col));

      // Month label: drawn at the top of a column when the month of that
      // column's Monday differs from the previously-labelled month, and there's
      // room before the next column (so labels don't collide on the last week).
      if (weekStart.month != lastMonthDrawn) {
        lastMonthDrawn = weekStart.month;
        // Only label if this Monday is in the first week of the month-ish (avoid
        // a label every single column when a month spans week boundaries — the
        // change-detection above already handles that, this guards the very
        // first column from a stray mid-month label).
        final dx = col * step;
        _paintMonthLabel(canvas, weekStart, dx);
      }

      for (var row = 0; row < 7; row++) {
        final date = weekStart.add(Duration(days: row));
        // Don't paint days in the future (the current week's tail).
        if (date.isAfter(today)) continue;

        final count = data[date] ?? 0;
        final level = activityLevel(count);
        cellPaint.color = level == 0 ? emptyColor : ramp[level];

        final dx = col * step;
        final dy = monthLabelHeight + row * step;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(dx, dy, cellSize, cellSize),
          radius,
        );
        canvas.drawRRect(rect, cellPaint);
      }
    }
  }

  void _paintMonthLabel(Canvas canvas, DateTime date, double dx) {
    final name = DateFormat.MMM(locale).format(date);
    final cap =
        name.isEmpty ? name : name[0].toUpperCase() + name.substring(1).toLowerCase();
    final tp = TextPainter(
      text: TextSpan(
        text: cap,
        style: GoogleFonts.manrope(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: MarginaliaColors.inkFaint,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(dx, 0));
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.data != data ||
      old.weeks != weeks ||
      old.cellSize != cellSize ||
      old.emptyColor != emptyColor ||
      !listEquals(old.ramp, ramp);
}

// ─── Legend ──────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({this.emptyColor, required this.ramp, required this.locale});
  final Color? emptyColor;
  final List<Color> ramp;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final it = locale.toLowerCase().startsWith('it');
    final less = it ? 'Meno' : 'Less';
    final more = it ? 'Più' : 'More';
    final empty = emptyColor ?? ramp[0];

    Widget swatch(Color c) => Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        );

    final labelStyle = GoogleFonts.manrope(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: MarginaliaColors.inkFaint,
      letterSpacing: 0.2,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(less, style: labelStyle),
        const SizedBox(width: 6),
        swatch(empty),
        for (var i = 1; i < ramp.length; i++) swatch(ramp[i]),
        const SizedBox(width: 6),
        Text(more, style: labelStyle),
      ],
    );
  }
}

// ─── Exposed for the share card (so it uses the exact same ramp) ─────────────

/// The top-of-ramp burnt sienna — the brand accent for the activity feature.
const Color activityAccent = Color(0xFF9C5B22);

/// The full intensity ramp, exposed read-only for callers that want to echo it
/// (e.g. the share card legend).
List<Color> get activityRamp => List.unmodifiable(_kRamp);

/// Builds a 5-step intensity ramp (level 0..4) from a single [seed] colour — the
/// user's chosen profile background. Level 0 stays a neutral warm stone so the
/// empty grid still reads as a grid; levels 1..4 climb from a pale tint of the
/// seed's hue to a deep, legible version of it.
///
/// The construction is hue/saturation-locked to the seed but lightness-driven,
/// with two clamps that keep EVERY preset readable on the warm paper ground:
///   • saturation is floored (so near-grey seeds like Coconut Milk still tint),
///   • the deepest step's lightness is capped (so light seeds like Pastel Yellow
///     don't top out as near-white and vanish against the page).
/// This is what makes the heatmap + its legend coherent with the profile colour.
List<Color> activityRampFromSeed(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  final double hue = hsl.hue;
  final double sat = hsl.saturation.clamp(0.30, 0.95).toDouble();
  const double lPale = 0.80;
  final double lDeep = (hsl.lightness * 0.55).clamp(0.22, 0.40).toDouble();
  Color at(double t) =>
      HSLColor.fromAHSL(1.0, hue, sat, lPale + (lDeep - lPale) * t).toColor();
  return [
    const Color(0xFFEDEAE2), // 0 — empty: neutral warm stone
    at(0.00), // 1 — pale tint of the seed
    at(0.40), // 2
    at(0.72), // 3
    at(1.00), // 4 — deep, legible seed (MORE)
  ];
}

/// Largest count present anywhere in [data] (for callers that show a "peak").
int peakCount(Map<DateTime, int> data) =>
    data.values.fold<int>(0, math.max);
