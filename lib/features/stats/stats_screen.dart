// ─── Reading stats screen ───────────────────────────────────────────────────
//
// Personal reading statistics page powered by `reading_sessions` +
// `reading_goals` tables (migration 027).
//
// Sections:
//   1. Annual goal progress card (books finished vs. target)
//   2. Overview (streak · this month · this year)
//   3. Last 12 months chart (custom-painted hand-drawn bars)
//   4. Recent sessions list
//
// Add a session via the FAB. No external charting deps — bars are CustomPaint.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/providers/auth_provider.dart';

// ─── Providers ─────────────────────────────────────────────────────────────
//
// Watch `currentUserProvider` (StreamProvider tied to onAuthStateChange)
// so the providers re-run when auth restoration finishes — NOT the static
// `supabaseServiceProvider` reference, which never re-emits.
//
// Defense in depth: hard 8-second timeout on every fetch + try/catch that
// downgrades to an empty result. Without this, the user reported the
// screen "loading forever or never" — typical of an iOS Safari WebSocket
// stall that never returns. Timing out means "skeleton appears, then
// fades to data within 8s no matter what" — never indefinite.

const _kStatsFetchTimeout = Duration(seconds: 8);

/// Annual reading goal for the current year (null if not set).
final readingGoalProvider = FutureProvider<int?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final svc = ref.read(supabaseServiceProvider);
  try {
    return await svc
        .fetchReadingGoal(year: DateTime.now().year)
        .timeout(_kStatsFetchTimeout, onTimeout: () => null);
  } catch (e) {
    // ignore: avoid_print
    print('[readingGoalProvider] $e');
    return null;
  }
});

/// All reading sessions for the current user, newest first.
final readingSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final svc = ref.read(supabaseServiceProvider);
  try {
    return await svc
        .fetchReadingSessions(limit: 500)
        .timeout(_kStatsFetchTimeout, onTimeout: () => const []);
  } catch (e) {
    // ignore: avoid_print
    print('[readingSessionsProvider] $e');
    return const [];
  }
});

// ─── Screen ────────────────────────────────────────────────────────────────

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsync     = ref.watch(readingGoalProvider);
    final sessionsAsync = ref.watch(readingSessionsProvider);
    final year          = DateTime.now().year;

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(
          context.l10n.statsTitle,
          style: GoogleFonts.ebGaramond(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: ScriptaColors.ink,
            letterSpacing: -0.4,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ScriptaColors.ink,
        foregroundColor: Colors.white,
        onPressed: () => _showAddSessionSheet(context, ref),
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          context.l10n.statsAddSession,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: ScriptaColors.primaryDark,
        onRefresh: () async {
          ref.invalidate(readingGoalProvider);
          ref.invalidate(readingSessionsProvider);
          await ref.read(readingSessionsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            // ── Goal card ────────────────────────────────────────────
            _SectionHeader(context.l10n.statsGoalSection(year)),
            const SizedBox(height: 12),
            goalAsync.when(
              loading: () => const _SkeletonCard(height: 110),
              error:   (_, __) => const SizedBox.shrink(),
              data: (target) {
                final sessions = sessionsAsync.value ?? const [];
                final booksFinished = _countBooksFinishedThisYear(sessions, year);
                return _GoalCard(
                  target: target,
                  done:   booksFinished,
                  onEdit: () => _showGoalEditSheet(context, ref, target),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── Overview ─────────────────────────────────────────────
            _SectionHeader(context.l10n.statsOverviewSection),
            const SizedBox(height: 12),
            sessionsAsync.when(
              loading: () => const _SkeletonCard(height: 132),
              error:   (_, __) => const SizedBox.shrink(),
              data: (sessions) => _OverviewGrid(
                streak:       _streakDays(sessions),
                monthMinutes: _totalMinutesThisMonth(sessions),
                yearBooks:    _countBooksFinishedThisYear(sessions, year),
              ),
            ),

            const SizedBox(height: 28),

            // ── Monthly chart ────────────────────────────────────────
            _SectionHeader(context.l10n.statsMonthlySection),
            const SizedBox(height: 12),
            sessionsAsync.when(
              loading: () => const _SkeletonCard(height: 160),
              error:   (_, __) => const SizedBox.shrink(),
              data: (sessions) => _MonthlyBarChart(
                buckets: _monthlyMinutes(
                  sessions,
                  Localizations.localeOf(context).toLanguageTag(),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Recent sessions ──────────────────────────────────────
            _SectionHeader(context.l10n.statsRecentSection),
            const SizedBox(height: 12),
            sessionsAsync.when(
              loading: () => const _SkeletonCard(height: 80),
              error:   (_, __) => const SizedBox.shrink(),
              data: (sessions) {
                if (sessions.isEmpty) return _EmptyStateCard(text: context.l10n.statsEmpty);
                return Column(
                  children: sessions.take(10).map(_SessionTile.from).toList(),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── Methodology footnote ─────────────────────────────────
            // Reading time isn't exposed by Kindle, so any session we
            // didn't create manually is estimated from highlight density.
            // Showing the methodology builds trust + sets expectations.
            const _MethodologyFooter(),
          ],
        ),
      ),
    );
  }

  // ─── Sheets ─────────────────────────────────────────────────────────────

  void _showAddSessionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ScriptaColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddSessionSheet(
        onSaved: () {
          ref.invalidate(readingSessionsProvider);
          ref.invalidate(readingGoalProvider);
        },
      ),
    );
  }

  void _showGoalEditSheet(BuildContext context, WidgetRef ref, int? current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ScriptaColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GoalEditSheet(
        current: current,
        onSaved: () => ref.invalidate(readingGoalProvider),
      ),
    );
  }
}

// ─── Derived metrics (pure functions) ──────────────────────────────────────

/// Counts distinct books with at least one session — ALL TIME, no year
/// filter. Inferred sessions inherit the Kindle highlight timestamp,
/// which is often months or years stale; filtering by current calendar
/// year was making freshly-imported libraries read as "0 books read"
/// even when the user clearly had finished books from prior years.
/// The annual goal stays a yearly target; the progress count is just
/// more forgiving so the user sees their effort. `year` kept in the
/// signature for call-site compatibility (it's ignored).
int _countBooksFinishedThisYear(
    List<Map<String, dynamic>> sessions, int year) {
  final keys = <String>{};
  for (final s in sessions) {
    final id    = s['book_id']    as String?;
    final title = (s['book_title'] as String?)?.toLowerCase().trim();
    final key   = id ?? title ?? '';
    if (key.isEmpty) continue;
    keys.add(key);
  }
  return keys.length;
}

/// Computes the current reading streak: consecutive days, ending today or
/// yesterday, with at least one session.
int _streakDays(List<Map<String, dynamic>> sessions) {
  if (sessions.isEmpty) return 0;
  final daysWithSessions = <DateTime>{};
  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    daysWithSessions.add(DateTime(d.year, d.month, d.day));
  }
  if (daysWithSessions.isEmpty) return 0;

  var cursor = DateTime.now();
  final today = DateTime(cursor.year, cursor.month, cursor.day);
  // Streak counts from today; if last session was yesterday and not today,
  // still start counting from yesterday so the user doesn't lose it until
  // the end of the day.
  if (!daysWithSessions.contains(today)) {
    cursor = today.subtract(const Duration(days: 1));
    if (!daysWithSessions.contains(cursor)) return 0;
  } else {
    cursor = today;
  }

  var streak = 0;
  while (daysWithSessions.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

int _totalMinutesThisMonth(List<Map<String, dynamic>> sessions) {
  final now = DateTime.now();
  var total = 0;
  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    if (d.year != now.year || d.month != now.month) continue;
    total += ((s['minutes_read'] as num?) ?? 0).toInt();
  }
  return total;
}

/// Returns a list of 12 entries (oldest → newest). `label` is the short
/// 3-letter abbreviation shown under each bar; `fullLabel` is the full
/// month name shown in the tap-tooltip ("Dicembre", "December"…).
/// Both are locale-aware via intl.
List<({String label, String fullLabel, int minutes})> _monthlyMinutes(
  List<Map<String, dynamic>> sessions,
  String locale,
) {
  final now = DateTime.now();
  final buckets = List<int>.filled(12, 0);
  // index = (year*12+month) - (now.year*12+now.month - 11)
  final nowIdx = now.year * 12 + (now.month - 1);

  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null) continue;
    final idx = (d.year * 12 + (d.month - 1)) - (nowIdx - 11);
    if (idx < 0 || idx > 11) continue;
    buckets[idx] += ((s['minutes_read'] as num?) ?? 0).toInt();
  }

  // Short label — first 3 chars of locale's MMM, capitalised. Unambiguous
  // across IT/EN/etc and stays readable on narrow bars.
  String shortLabelFor(int monthIndex) {
    final d = DateTime(now.year, monthIndex + 1, 1);
    final mmm = DateFormat.MMM(locale).format(d);
    final s = mmm.length >= 3 ? mmm.substring(0, 3) : mmm;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  // Full label — used in the tap tooltip. We want "Dicembre" not "DICEMBRE",
  // so we lowercase then re-capitalise the first letter, regardless of
  // what intl returns for the locale.
  String fullLabelFor(int monthIndex) {
    final d = DateTime(now.year, monthIndex + 1, 1);
    final mmmm = DateFormat.MMMM(locale).format(d);
    if (mmmm.isEmpty) return mmmm;
    return mmmm[0].toUpperCase() + mmmm.substring(1).toLowerCase();
  }

  return List.generate(12, (i) {
    // Position i = 11 is the current month; i = 0 is 11 months ago.
    final monthIdx = (now.month - 11 + i - 1 + 12) % 12;
    return (
      label: shortLabelFor(monthIdx),
      fullLabel: fullLabelFor(monthIdx),
      minutes: buckets[i],
    );
  });
}

// ─── Building blocks ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ScriptaColors.inkMuted,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Divider(color: ScriptaColors.ruleFaint, height: 1),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ScriptaDecorations.card(),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 13,
          color: ScriptaColors.inkMuted,
          height: 1.5,
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.target, required this.done, required this.onEdit});
  final int? target;
  final int  done;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasGoal = target != null && target! > 0;
    final progress = hasGoal ? (done / target!).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: ScriptaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasGoal) ...[
            Text(
              context.l10n.statsGoalProgress(done, target!),
              style: GoogleFonts.ebGaramond(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.ink,
                letterSpacing: -0.6,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: ScriptaColors.surfaceElevated,
                color: ScriptaColors.primaryDark,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onEdit,
                child: Text(context.l10n.statsGoalEditCta),
              ),
            ),
          ] else ...[
            Text(
              '—',
              style: GoogleFonts.ebGaramond(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.inkFaint,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onEdit,
                child: Text(context.l10n.statsGoalSetCta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({
    required this.streak,
    required this.monthMinutes,
    required this.yearBooks,
  });
  final int streak;
  final int monthMinutes;
  final int yearBooks;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StaggeredListItem(
            index: 0,
            child: _OverviewTile(
              label: context.l10n.statsStreak,
              value: context.l10n.statsStreakDays(streak),
              big:   streak.toString(),
              accent: ScriptaColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StaggeredListItem(
            index: 1,
            child: _OverviewTile(
              label: context.l10n.statsThisMonth,
              value: context.l10n.statsThisMonthMinutes(monthMinutes),
              big:   monthMinutes.toString(),
              accent: ScriptaColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StaggeredListItem(
            index: 2,
            child: _OverviewTile(
              label: context.l10n.statsThisYear,
              value: context.l10n.statsThisYearBooks(yearBooks),
              big:   yearBooks.toString(),
              accent: ScriptaColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.label,
    required this.value,
    required this.big,
    required this.accent,
  });
  final String label;
  final String value;
  final String big;
  final Color  accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: ScriptaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: ScriptaColors.inkFaint,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          airbnbCrossFade(
            child: Text(
              big,
              key: ValueKey(big),
              style: GoogleFonts.ebGaramond(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: accent,
                height: 1,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: ScriptaColors.inkMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly bar chart ──────────────────────────────────────────────────────
//
// Three jobs:
//   1. Explain the chart. The first version showed bars and nothing else —
//      no axis, no total, no peak — so screenshots looked like generic
//      dashboard chart-#3. Now the header tells you the headline numbers
//      directly: total hours in the last 12 months on the left, peak month
//      on the right, both set in italic Garamond like a book frontispiece.
//   2. Tap-to-reveal value. Each bar is a GestureDetector; the parent card
//      is also a GestureDetector that resets selection. Tapping a bar
//      shows a small pill above it with the full month name + minutes.
//      Tap the same bar again or anywhere else and it dismisses.
//   3. Designed for sharing. The whole card is meant to look like a page
//      from a personal reading ledger — cream paper, EB Garamond italics
//      for the meaningful words (hours, peak month), Manrope small-caps
//      only for the quiet captions. The kind of thing someone screenshots
//      and posts on Instagram because it looks like a printed object,
//      not a screen.

class _MonthlyBarChart extends StatefulWidget {
  const _MonthlyBarChart({required this.buckets});
  final List<({String label, String fullLabel, int minutes})> buckets;

  @override
  State<_MonthlyBarChart> createState() => _MonthlyBarChartState();
}

class _MonthlyBarChartState extends State<_MonthlyBarChart> {
  int? _selected;

  // 312 → "5h 12m"; 47 → "47 min"; 0 → "0 min". Universal "h"/"m" suffixes
  // work in both IT and EN, so no l10n round-trip needed.
  static String _humanize(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  void _toggle(int i) {
    setState(() => _selected = _selected == i ? null : i);
  }

  void _dismiss() {
    if (_selected != null) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final b        = widget.buckets;
    final maxValue = b.map((x) => x.minutes).fold<int>(0, (a, x) => a > x ? a : x);
    final total    = b.fold<int>(0, (a, x) => a + x.minutes);
    final peakIdx  = maxValue == 0 ? -1 : b.indexWhere((x) => x.minutes == maxValue);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        decoration: ScriptaDecorations.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Headline: total time + peak month ─────────────────────
            _ChartHeadline(
              total:     _humanize(total),
              peakName:  peakIdx >= 0 ? b[peakIdx].fullLabel : null,
              peakValue: peakIdx >= 0 ? _humanize(b[peakIdx].minutes) : null,
            ),

            const SizedBox(height: 22),

            // ── Bars + floating tooltip ───────────────────────────────
            LayoutBuilder(builder: (ctx, c) {
              final chartWidth   = c.maxWidth;
              // tooltipZone reserves room for the pill+arrow (56 px) plus a
              // 6 px cushion so the arrow doesn't kiss the tallest bar.
              const tooltipZone  = 62.0;
              const labelZone    = 22.0; // bar label (italic month abbr)
              const totalHeight  = 184.0;
              final  maxBarH     = totalHeight - tooltipZone - labelZone;

              double barHeight(int minutes) {
                if (maxValue == 0) return 3;
                return 3 + (minutes / maxValue) * maxBarH;
              }

              final selBarHeight = _selected == null
                  ? 0.0
                  : barHeight(b[_selected!].minutes);

              return SizedBox(
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Bars row, anchored to bottom (above the label zone).
                    Positioned(
                      top: tooltipZone,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < b.length; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _toggle(i),
                                child: _BarColumn(
                                  bucket:    b[i],
                                  height:    barHeight(b[i].minutes),
                                  selected:  _selected == i,
                                  dimmed:    _selected != null && _selected != i,
                                  index:     i,
                                  labelZone: labelZone,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Floating tooltip — fades/slides in when a bar is tapped.
                    if (_selected != null)
                      _MonthTooltip(
                        chartWidth:    chartWidth,
                        barIndex:      _selected!,
                        barCount:      b.length,
                        tooltipZone:   tooltipZone,
                        barHeight:     selBarHeight,
                        labelZone:     labelZone,
                        monthName:     b[_selected!].fullLabel,
                        humanized:     _humanize(b[_selected!].minutes),
                        rawMinutes:    b[_selected!].minutes,
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),

            // ── Hairline + caption ────────────────────────────────────
            const Divider(
              height: 1,
              thickness: 0.6,
              color: ScriptaColors.ruleFaint,
            ),
            const SizedBox(height: 10),
            _ChartCaption(text: context.l10n.statsMonthlyTapHint),
          ],
        ),
      ),
    );
  }
}

// ─── Headline row ───────────────────────────────────────────────────────────
class _ChartHeadline extends StatelessWidget {
  const _ChartHeadline({
    required this.total,
    required this.peakName,
    required this.peakValue,
  });
  final String total;
  final String? peakName;
  final String? peakValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left — total time (the "headline" stat).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                total,
                style: GoogleFonts.ebGaramond(
                  fontSize: 34,
                  // Roman, not italic — user feedback: italic numbers on the
                  // stats card felt "decorative" rather than authoritative,
                  // and the screenshot they shared felt the progress should
                  // read like a tally, not a frontispiece.
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.ink,
                  letterSpacing: -0.8,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.statsMonthlyTotalCaption,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.inkMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        // Right — peak month (only when there's data).
        if (peakName != null && peakValue != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                peakName!,
                style: GoogleFonts.ebGaramond(
                  fontSize: 22,
                  // Roman, matching the headline total above.
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.primaryDark,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${context.l10n.statsMonthlyPeakCaption.toLowerCase()} · $peakValue',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.inkMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── Single bar column ──────────────────────────────────────────────────────
class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.bucket,
    required this.height,
    required this.selected,
    required this.dimmed,
    required this.index,
    required this.labelZone,
  });

  final ({String label, String fullLabel, int minutes}) bucket;
  final double height;
  final bool   selected;
  final bool   dimmed;
  final int    index;
  final double labelZone;

  @override
  Widget build(BuildContext context) {
    // Subtle dual-tone fill — matcha lightens slightly at the top so each
    // bar reads as a brush-stroke rather than a flat block. Dimmed bars
    // (when another bar is selected) drop to a low-opacity tint so the
    // selection clearly leads the eye.
    final hasData = bucket.minutes > 0;
    final fillTop = selected
        ? ScriptaColors.primaryDark
        : (dimmed ? const Color(0x66B0B5AE) : ScriptaColors.sienna);
    final fillBottom = selected
        ? ScriptaColors.primary
        : (dimmed ? const Color(0x66B0B5AE) : ScriptaColors.primary);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // The bar itself.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 320 + index * 18),
            curve: Curves.easeOutQuart,
            height: height,
            decoration: BoxDecoration(
              gradient: hasData
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [fillTop, fillBottom],
                    )
                  : null,
              color: hasData ? null : ScriptaColors.ruleFaint,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Month label — italic lowercase, matches the editorial register
        // of the headline. Selected month rises to the brand color.
        SizedBox(
          height: labelZone - 8,
          child: Text(
            bucket.label.toLowerCase(),
            style: GoogleFonts.ebGaramond(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? ScriptaColors.primaryDark
                  : (dimmed
                      ? ScriptaColors.inkFaint
                      : ScriptaColors.inkMuted),
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Floating tooltip pill ──────────────────────────────────────────────────
//
// Sits at the top of the chart Stack inside the reserved tooltipZone.
// Horizontally centred on the selected bar, but clamped so it never spills
// past the card's edges. A small triangle below the pill points down at
// the bar's X — the bar itself gets a darker treatment + shadow so the
// connection is visually obvious even though the arrow doesn't stretch
// all the way down (which would be visually busy on short bars).
class _MonthTooltip extends StatelessWidget {
  const _MonthTooltip({
    required this.chartWidth,
    required this.barIndex,
    required this.barCount,
    required this.tooltipZone,
    required this.barHeight,
    required this.labelZone,
    required this.monthName,
    required this.humanized,
    required this.rawMinutes,
  });

  final double chartWidth;
  final int    barIndex;
  final int    barCount;
  final double tooltipZone;
  final double barHeight;
  final double labelZone;
  final String monthName;
  final String humanized;
  final int    rawMinutes;

  // Hardcoded sizes — the pill needs to fit in `tooltipZone` (60 px), so
  // the title/value/padding stack adds up to ≤ tooltipZone - arrowSize.
  static const _kPillWidth   = 132.0;
  static const _kPillHeight  = 50.0;
  static const _kArrowWidth  = 10.0;
  static const _kArrowHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final colWidth  = chartWidth / barCount;
    final barCentre = (barIndex + 0.5) * colWidth;
    final leftClamp = (barCentre - _kPillWidth / 2)
        .clamp(0.0, chartWidth - _kPillWidth);
    final arrowDx   = (barCentre - leftClamp - _kArrowWidth / 2)
        .clamp(8.0, _kPillWidth - _kArrowWidth - 8.0);

    return Positioned(
      left:  leftClamp,
      width: _kPillWidth,
      top:   0,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutQuart,
        tween: Tween(begin: 0, end: 1),
        builder: (ctx, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: child,
          ),
        ),
        child: SizedBox(
          height: _kPillHeight + _kArrowHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Pill body — sits at the top, fills the width.
              Positioned(
                top:    0,
                left:   0,
                right:  0,
                height: _kPillHeight,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                  decoration: BoxDecoration(
                    color: ScriptaColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0x231B1F1B),
                      width: 0.8,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        monthName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                          color: ScriptaColors.ink,
                          height: 1.05,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rawMinutes == 0
                            ? context.l10n.statsMonthlyNoReading
                            : humanized,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: rawMinutes == 0
                              ? ScriptaColors.inkFaint
                              : ScriptaColors.primaryDark,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Downward arrow — sits flush against the pill's bottom edge,
              // X aligned with the selected bar (clamped so it stays under
              // the pill body even when the pill itself is clamped to an
              // edge).
              Positioned(
                left:   arrowDx,
                top:    _kPillHeight - 0.6, // overlap pill border by 0.6
                width:  _kArrowWidth,
                height: _kArrowHeight,
                child: CustomPaint(
                  size: const Size(_kArrowWidth, _kArrowHeight),
                  painter: _TooltipArrowPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TooltipArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = ScriptaColors.surface
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0x231B1F1B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, fill);

    // Draw only the two slanted edges so the top edge blends into the pill.
    final edge = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(edge, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Caption under the chart ────────────────────────────────────────────────
class _ChartCaption extends StatelessWidget {
  const _ChartCaption({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.touch_app_outlined,
          size: 13,
          color: ScriptaColors.inkFaint,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.ebGaramond(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: ScriptaColors.inkFaint,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.dateLabel,
    required this.bookLabel,
    required this.minutes,
    this.pages,
    this.inferred = false,
  });
  final String dateLabel;
  final String bookLabel;
  final int    minutes;
  final int?   pages;
  final bool   inferred;

  factory _SessionTile.from(Map<String, dynamic> s) {
    final dateStr = s['session_date'] as String? ?? '';
    final d = DateTime.tryParse(dateStr) ?? DateTime.now();
    final dateLabel = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final title  = (s['book_title']  as String?)?.trim();
    final author = (s['book_author'] as String?)?.trim();
    final bookLabel = title?.isNotEmpty == true
        ? (author?.isNotEmpty == true ? '$title · $author' : title!)
        : '—';
    return _SessionTile(
      dateLabel: dateLabel,
      bookLabel: bookLabel,
      minutes:   ((s['minutes_read'] as num?) ?? 0).toInt(),
      pages:     (s['pages_read']    as num?)?.toInt(),
      inferred:  (s['source'] as String?) == 'inferred',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: ScriptaDecorations.card(),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: ScriptaColors.siennaFaint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ScriptaColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      pages != null ? '$minutes min · $pages pg' : '$minutes min',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: ScriptaColors.inkMuted,
                      ),
                    ),
                    if (inferred) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: ScriptaColors.siennaFaint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          context.l10n.statsInferredBadge.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: ScriptaColors.primaryDark,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Methodology footer ─────────────────────────────────────────────────────

class _MethodologyFooter extends StatelessWidget {
  const _MethodologyFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ScriptaColors.ruleFaint,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: ScriptaColors.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.statsMethodologyNote,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: ScriptaColors.inkMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sheets ─────────────────────────────────────────────────────────────────

class _AddSessionSheet extends ConsumerStatefulWidget {
  const _AddSessionSheet({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends ConsumerState<_AddSessionSheet> {
  final _titleCtrl   = TextEditingController();
  final _authorCtrl  = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _pagesCtrl   = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _minutesCtrl.dispose();
    _pagesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    if (minutes <= 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(supabaseServiceProvider).addReadingSession(
            title:  _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
            author: _authorCtrl.text.trim().isEmpty ? null : _authorCtrl.text.trim(),
            minutes: minutes,
            pages:   int.tryParse(_pagesCtrl.text.trim()),
            sessionDate: _date,
            source: 'manual',
          );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.statsErrorSaving)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.statsAddTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          // Hint: discourage logging sessions for books that are already
          // tracked automatically via highlight inference (migration 031).
          Text(
            context.l10n.statsAddHint,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: ScriptaColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.l10n.statsAddBookTitle,
              prefixIcon: const Icon(Icons.menu_book_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _authorCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.l10n.statsAddBookAuthor,
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minutesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.statsAddMinutes,
                    prefixIcon: const Icon(Icons.timer_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pagesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.statsAddPages,
                    prefixIcon: const Icon(Icons.format_list_numbered),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              '${context.l10n.statsAddDate}: ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate:  DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.statsAddSaveCta),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalEditSheet extends ConsumerStatefulWidget {
  const _GoalEditSheet({required this.current, required this.onSaved});
  final int? current;
  final VoidCallback onSaved;

  @override
  ConsumerState<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends ConsumerState<_GoalEditSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: (widget.current ?? 15).toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0 || v > 9999) return;
    setState(() => _saving = true);
    try {
      await ref.read(supabaseServiceProvider).saveReadingGoal(
            year: DateTime.now().year,
            targetBooks: v,
          );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.statsGoalEditTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.onboardingGoalFieldLabel,
              prefixIcon: const Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.statsGoalEditSaveCta),
            ),
          ),
        ],
      ),
    );
  }
}
