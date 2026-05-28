// Compact reading-stats card meant to live INSIDE the profile screen.
//
// Hero-level visibility for the data that previously sat behind a Settings
// link: annual goal progress + 3 quick metrics (streak / month minutes /
// books this year). Taps the "Vedi tutto" affordance to push /stats for
// the full chart + sessions list.
//
// Watches the same providers as stats_screen.dart so the numbers stay in
// sync whether the user opens the detail screen or just glances at the
// profile.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/share_card_service.dart';
import 'stats_screen.dart' show readingGoalProvider, readingSessionsProvider;

class ReadingStatsCard extends ConsumerWidget {
  const ReadingStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsync     = ref.watch(readingGoalProvider);
    final sessionsAsync = ref.watch(readingSessionsProvider);

    final goal     = goalAsync.asData?.value;
    final sessions = sessionsAsync.asData?.value ?? const [];

    final streak       = _streakDays(sessions);
    final monthMinutes = _totalMinutesThisMonth(sessions);
    final yearBooks    = _countBooksFinishedThisYear(
      sessions,
      DateTime.now().year,
    );

    final hasAnyData = streak > 0 || monthMinutes > 0 || yearBooks > 0 || goal != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/stats'),
          child: Container(
            decoration: BoxDecoration(
              color: MarginaliaColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: MarginaliaColors.ruleFaint,
                width: 0.8,
              ),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ────────────────────────────────────────────
                Row(
                  children: [
                    Text(
                      context.l10n.profileReadingSection,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    // Share-to-Instagram entry point. Tap stops the
                    // outer InkWell from navigating to /stats so the
                    // gesture lands on the share sheet instead.
                    if (hasAnyData)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final name = ref
                                  .read(myDisplayNameProvider)
                                  .asData
                                  ?.value ??
                              'me';
                          await ShareCardService.showStats(
                            context,
                            userName: name,
                            booksThisYear: yearBooks,
                            streakDays: streak,
                            monthMinutes: monthMinutes,
                            yearGoal: goal,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Icon(
                            Icons.ios_share,
                            size: 16,
                            color: MarginaliaColors.sienna,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.profileSeeAll,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.sienna,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios,
                        size: 11, color: MarginaliaColors.sienna),
                  ],
                ),

                // ── Empty state ──────────────────────────────────────────
                if (!hasAnyData) ...[
                  const SizedBox(height: 14),
                  Text(
                    context.l10n.profileReadingEmpty,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: MarginaliaColors.inkMuted,
                      height: 1.45,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),

                  // ── 3 stat tiles ───────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          value: yearBooks.toString(),
                          label: context.l10n.profileStatsBooks,
                          suffix: goal != null ? '/$goal' : null,
                        ),
                      ),
                      _MiniDivider(),
                      Expanded(
                        child: _StatTile(
                          value: streak.toString(),
                          label: context.l10n.profileStatsStreak,
                        ),
                      ),
                      _MiniDivider(),
                      Expanded(
                        child: _StatTile(
                          value: _formatMinutes(monthMinutes),
                          label: context.l10n.profileStatsThisMonth,
                        ),
                      ),
                    ],
                  ),

                  // ── Goal progress bar (only if a goal is set) ──────────
                  if (goal != null && goal > 0) ...[
                    const SizedBox(height: 16),
                    _GoalProgressBar(done: yearBooks, target: goal),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Small building blocks ────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.suffix});
  final String  value;
  final String  label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: GoogleFonts.ebGaramond(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.ink,
                  letterSpacing: -0.6,
                  height: 1.0,
                ),
              ),
              if (suffix != null)
                TextSpan(
                  text: suffix!,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: MarginaliaColors.inkFaint,
                    height: 1.0,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.inkFaint,
            letterSpacing: 0.6,
            height: 1.2,
          ),
          maxLines: 2,
        ),
      ],
    );
  }
}

class _MiniDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: MarginaliaColors.ruleFaint,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({required this.done, required this.target});
  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    final pct = (done / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct == 0 ? null : pct, // null = indeterminate, avoid 0-width
            minHeight: 6,
            backgroundColor: MarginaliaColors.primaryFaint,
            valueColor:
                const AlwaysStoppedAnimation<Color>(MarginaliaColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(pct * 100).round()}%',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.primary,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              done >= target
                  ? context.l10n.profileStatsGoalReached
                  : context.l10n.profileStatsGoalRemaining(target - done),
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Derived metrics (mirror stats_screen.dart's helpers) ─────────────────

int _streakDays(List<Map<String, dynamic>> sessions) {
  if (sessions.isEmpty) return 0;
  final dates = <DateTime>{};
  for (final s in sessions) {
    final iso = s['session_date'] as String?;
    if (iso == null) continue;
    final d = DateTime.tryParse(iso);
    if (d == null) continue;
    dates.add(DateTime(d.year, d.month, d.day));
  }
  if (dates.isEmpty) return 0;
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final y     = today.subtract(const Duration(days: 1));
  if (!dates.contains(today) && !dates.contains(y)) return 0;
  var streak = 0;
  var cur    = dates.contains(today) ? today : y;
  while (dates.contains(cur)) {
    streak++;
    cur = cur.subtract(const Duration(days: 1));
  }
  return streak;
}

int _totalMinutesThisMonth(List<Map<String, dynamic>> sessions) {
  final now = DateTime.now();
  var total = 0;
  for (final s in sessions) {
    final iso = s['session_date'] as String?;
    if (iso == null) continue;
    final d = DateTime.tryParse(iso);
    if (d == null) continue;
    if (d.year != now.year || d.month != now.month) continue;
    final m = s['minutes'] as int?;
    if (m != null) total += m;
  }
  return total;
}

// Counts distinct books across ALL sessions, ignoring `year`. We used to
// filter `d.year == year`, but inferred sessions inherit the Kindle
// highlight's original timestamp, which is often months or years stale.
// A user who imported their library yesterday would otherwise see "0/15"
// for the goal even though they clearly *have* books, because every
// highlight predates the current year. Counting all-time is the
// pragmatic move — the goal stays a yearly target, but the progress
// number reflects everything they've actually finished.
// `year` param kept in the signature so old call sites compile.
int _countBooksFinishedThisYear(
    List<Map<String, dynamic>> sessions, int year) {
  final keys = <String>{};
  for (final s in sessions) {
    final id    = s['book_id'] as String?;
    final title = (s['book_title'] as String?)?.toLowerCase().trim();
    final key   = id ?? title ?? '';
    if (key.isEmpty) continue;
    keys.add(key);
  }
  return keys.length;
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
