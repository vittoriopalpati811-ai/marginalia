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
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
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
            color: MarginaliaColors.ink,
            letterSpacing: -0.4,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: MarginaliaColors.ink,
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
        color: MarginaliaColors.sienna,
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
      backgroundColor: MarginaliaColors.background,
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
      backgroundColor: MarginaliaColors.background,
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

/// Counts distinct books with at least one session in `year` AND pages_read
/// either filled (we treat "any session with pages > 0" as progress toward
/// completion). This is a soft heuristic — the user can later mark books as
/// finished explicitly.
int _countBooksFinishedThisYear(
    List<Map<String, dynamic>> sessions, int year) {
  final keys = <String>{};
  for (final s in sessions) {
    final dateStr = s['session_date'] as String?;
    if (dateStr == null) continue;
    final d = DateTime.tryParse(dateStr);
    if (d == null || d.year != year) continue;
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

/// Returns a list of 12 entries (oldest → newest), each `(label, minutes)`.
/// Labels are locale-aware first letters of the month name (intl).
List<({String label, int minutes})> _monthlyMinutes(
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

  // Build labels in the user's locale. We use first 3 chars of MMM, which
  // is unambiguous across IT/EN/etc and stays readable even on narrow bars.
  String labelFor(int monthIndex) {
    // monthIndex is 0-based; DateTime month is 1-based.
    final d = DateTime(now.year, monthIndex + 1, 1);
    final mmm = DateFormat.MMM(locale).format(d);
    // Take first 3 letters, capitalize first only — looks cleaner under bars
    final s = mmm.length >= 3 ? mmm.substring(0, 3) : mmm;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  return List.generate(12, (i) {
    // Position i = 11 is the current month; i = 0 is 11 months ago.
    final monthIdx = (now.month - 11 + i - 1 + 12) % 12;
    return (label: labelFor(monthIdx), minutes: buckets[i]);
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
            color: MarginaliaColors.inkMuted,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Divider(color: MarginaliaColors.ruleFaint, height: 1),
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
        color: MarginaliaColors.surfaceElevated,
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
      decoration: MarginaliaDecorations.card(),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 13,
          color: MarginaliaColors.inkMuted,
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
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasGoal) ...[
            Text(
              context.l10n.statsGoalProgress(done, target!),
              style: GoogleFonts.ebGaramond(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
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
                backgroundColor: MarginaliaColors.surfaceElevated,
                color: MarginaliaColors.primary,
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
                color: MarginaliaColors.inkFaint,
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
              accent: MarginaliaColors.sienna,
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
              accent: MarginaliaColors.primary,
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
              accent: MarginaliaColors.siennaLight,
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
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: MarginaliaColors.inkFaint,
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
              color: MarginaliaColors.inkMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.buckets});
  final List<({String label, int minutes})> buckets;

  @override
  Widget build(BuildContext context) {
    final maxValue = buckets
        .map((b) => b.minutes)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: MarginaliaDecorations.card(),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Bar
                      AnimatedContainer(
                        duration: Duration(milliseconds: 320 + i * 22),
                        curve: Curves.easeOutCubic,
                        height: maxValue == 0
                            ? 4.0
                            : 4.0 + (buckets[i].minutes / maxValue) * 92.0,
                        decoration: BoxDecoration(
                          color: buckets[i].minutes == 0
                              ? MarginaliaColors.ruleFaint
                              : MarginaliaColors.primary,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Month label
                      Text(
                        buckets[i].label,
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          color: MarginaliaColors.inkFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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
      decoration: MarginaliaDecorations.card(),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: MarginaliaColors.siennaFaint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.sienna,
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
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      pages != null ? '$minutes min · $pages pg' : '$minutes min',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: MarginaliaColors.inkMuted,
                      ),
                    ),
                    if (inferred) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: MarginaliaColors.siennaFaint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          context.l10n.statsInferredBadge.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.sienna,
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
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MarginaliaColors.ruleFaint,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: MarginaliaColors.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.statsMethodologyNote,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: MarginaliaColors.inkMuted,
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
                color: MarginaliaColors.rule,
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
              color: MarginaliaColors.ink,
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
              color: MarginaliaColors.inkMuted,
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
                color: MarginaliaColors.rule,
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
              color: MarginaliaColors.ink,
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
