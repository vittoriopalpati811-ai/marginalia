import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Jam Ripasso leaderboard ───────────────────────────────────────────────────
//
// The "Ripasso" tab of a Jam. Four segments:
//   • Today / Week / Month — period boards backed by the
//     `jam_ripasso_leaderboard_period` RPC (migration 063): one row per member
//     with total score, total time and (for week/month) session count, ranked
//     server-side. The DAY tab also surfaces up to three title badges
//     (first-to-finish, fastest, sharpest) computed from the same rows.
//   • Streaks — the original streak board backed by [jamReviewLeaderboardProvider]
//     → the `jam_review_leaderboard` RPC (migration 051).
//
// The current user's row is highlighted everywhere; pull-to-refresh re-runs the
// active segment's source.

/// Warm sienna/orange used for flame accents across the Jam screens.
const _kFlameColor = Color(0xFFD9892F);

/// Period leaderboard rows for a jam — keyed by "jamId|period" (day/week/month).
/// Defined locally because the shared provider file is not editable here.
final _jamRipassoPeriodProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, key) {
    final sep = key.indexOf('|');
    final jamId = key.substring(0, sep);
    final period = key.substring(sep + 1);
    return ref
        .read(supabaseServiceProvider)
        .fetchJamRipassoLeaderboardPeriod(jamId, period);
  },
);

class JamReviewLeaderboardScreen extends ConsumerStatefulWidget {
  const JamReviewLeaderboardScreen({super.key, required this.jamId});

  final String jamId;

  @override
  ConsumerState<JamReviewLeaderboardScreen> createState() =>
      _JamReviewLeaderboardScreenState();
}

class _JamReviewLeaderboardScreenState
    extends ConsumerState<JamReviewLeaderboardScreen> {
  // 0 = Today (day), 1 = Week, 2 = Month, 3 = Streaks.
  int _segment = 0;

  static const _periodKeys = ['day', 'week', 'month'];

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final myId = ref.watch(currentUserProvider)?.id ?? '';
    final labels = it
        ? ['Oggi', 'Settimana', 'Mese', 'Serie']
        : ['Today', 'Week', 'Month', 'Streaks'];

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.jamRipassoTitle,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: ScriptaColors.ink,
          ),
        ),
      ),
      body: Column(
        children: [
          _SegmentBar(
            labels: labels,
            selected: _segment,
            onSelect: (i) => setState(() => _segment = i),
          ),
          Expanded(
            child: _segment == 3
                ? _StreakBoard(jamId: widget.jamId, myId: myId)
                : _PeriodBoard(
                    key: ValueKey(_segment),
                    jamId: widget.jamId,
                    period: _periodKeys[_segment],
                    myId: myId,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Segmented control (Today · Week · Month · Streaks) ───────────────────────────

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ScriptaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: 180.ms,
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? ScriptaColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: selected == i
                          ? const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        fontWeight:
                            selected == i ? FontWeight.w700 : FontWeight.w500,
                        color: selected == i
                            ? ScriptaColors.primaryDark
                            : ScriptaColors.inkMuted,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Period board (Today / Week / Month) ─────────────────────────────────────────

class _PeriodBoard extends ConsumerWidget {
  const _PeriodBoard({
    super.key,
    required this.jamId,
    required this.period,
    required this.myId,
  });

  final String jamId;
  final String period;
  final String myId;

  bool get _isDay => period == 'day';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$jamId|$period';
    final async = ref.watch(_jamRipassoPeriodProvider(key));

    return RefreshIndicator(
      color: ScriptaColors.primaryDark,
      onRefresh: () async => ref.refresh(_jamRipassoPeriodProvider(key).future),
      child: async.when(
        data: (rows) {
          // Keep only rows with at least one answered question this period.
          final ranked = rows
              .where((r) => ((r['total_questions'] as num?)?.toInt() ?? 0) > 0)
              .toList();

          if (ranked.isEmpty) {
            return _EmptyBoard(memberCount: rows.length);
          }

          final badges = _isDay
              ? _computeBadges(context, ranked)
              : const <_TitleBadge>[];

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: ranked.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return _PeriodHeader(
                  period: period,
                  badges: badges,
                );
              }
              final rank = i - 1;
              final row = ranked[rank];
              final isMe = row['user_id'] == myId;
              return _PeriodRow(
                rank: rank,
                row: row,
                isMe: isMe,
                showSessions: !_isDay,
              )
                  .animate(delay: (rank * 45).ms)
                  .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.05, end: 0, duration: 280.ms);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: ScriptaColors.primaryDark,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => _ErrorBoard(
          message: context.l10n.errorPrefix('$e'),
        ),
      ),
    );
  }

  /// Up to three "title" badges for the DAY board:
  ///  1. First to finish — earliest first_completed_at.
  ///  2. Fastest — smallest best_duration_seconds (> 0).
  ///  3. Sharpest — best total_score / total_questions ratio (questions > 0).
  /// Each badge is gendered when the winner's `gender` is 'f' / 'm'.
  List<_TitleBadge> _computeBadges(
      BuildContext context, List<Map<String, dynamic>> rows) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final badges = <_TitleBadge>[];

    String nameOf(Map<String, dynamic> r) =>
        (r['display_name'] as String?)?.trim().isNotEmpty == true
            ? (r['display_name'] as String).trim()
            : context.l10n.jamRipassoAnonymous;
    String? genderOf(Map<String, dynamic> r) => r['gender'] as String?;

    // 1. First to finish.
    Map<String, dynamic>? first;
    DateTime? firstAt;
    for (final r in rows) {
      final raw = r['first_completed_at'] as String?;
      if (raw == null) continue;
      final t = DateTime.tryParse(raw);
      if (t == null) continue;
      if (firstAt == null || t.isBefore(firstAt)) {
        firstAt = t;
        first = r;
      }
    }
    if (first != null && firstAt != null) {
      final g = genderOf(first);
      badges.add(_TitleBadge(
        title: it
            ? (g == 'f' ? 'La prima' : 'Il primo')
            : 'First to finish',
        value: _hhmm(firstAt.toLocal()),
        name: nameOf(first),
        avatarUrl: first['avatar_url'] as String?,
        icon: Icons.flag_rounded,
      ));
    }

    // 2. Fastest (smallest positive best_duration_seconds).
    Map<String, dynamic>? fastest;
    int fastestSec = 0;
    for (final r in rows) {
      final s = (r['best_duration_seconds'] as num?)?.toInt() ?? 0;
      if (s <= 0) continue;
      if (fastest == null || s < fastestSec) {
        fastestSec = s;
        fastest = r;
      }
    }
    if (fastest != null) {
      final g = genderOf(fastest);
      badges.add(_TitleBadge(
        title: it
            ? (g == 'f' ? 'La più veloce' : 'Il più veloce')
            : 'Fastest',
        value: _mmss(fastestSec),
        name: nameOf(fastest),
        avatarUrl: fastest['avatar_url'] as String?,
        icon: Icons.bolt_rounded,
      ));
    }

    // 3. Sharpest (best score/questions ratio, questions > 0).
    Map<String, dynamic>? sharpest;
    double bestRatio = -1;
    for (final r in rows) {
      final q = (r['total_questions'] as num?)?.toInt() ?? 0;
      if (q <= 0) continue;
      final sc = (r['total_score'] as num?)?.toInt() ?? 0;
      final ratio = sc / q;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        sharpest = r;
      }
    }
    if (sharpest != null && bestRatio >= 0) {
      final g = genderOf(sharpest);
      badges.add(_TitleBadge(
        title: it
            ? (g == 'f' ? 'La più precisa' : 'Il più preciso')
            : 'Sharpest',
        value: '${(bestRatio * 100).round()}%',
        name: nameOf(sharpest),
        avatarUrl: sharpest['avatar_url'] as String?,
        icon: Icons.center_focus_strong_rounded,
      ));
    }

    return badges;
  }
}

// ─── Period header: blurb + (day-only) title badges ───────────────────────────────

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period, required this.badges});
  final String period;
  final List<_TitleBadge> badges;

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final blurb = switch (period) {
      'day' => it
          ? 'Classifica di oggi: punteggio e tempo totale del ripasso.'
          : "Today's board: ripasso score and total time.",
      'week' => it
          ? 'Questa settimana: punteggio, tempo e sessioni di ripasso.'
          : 'This week: ripasso score, time and sessions.',
      _ => it
          ? 'Questo mese: punteggio, tempo e sessioni di ripasso.'
          : 'This month: ripasso score, time and sessions.',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: ScriptaColors.primaryFaint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 20, color: _kFlameColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    blurb,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: ScriptaColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final b in badges)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TitleBadgeCard(badge: b),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Title badge model + card (First / Fastest / Sharpest) ────────────────────────

class _TitleBadge {
  const _TitleBadge({
    required this.title,
    required this.value,
    required this.name,
    required this.avatarUrl,
    required this.icon,
  });
  final String title;
  final String value;
  final String name;
  final String? avatarUrl;
  final IconData icon;
}

class _TitleBadgeCard extends StatelessWidget {
  const _TitleBadgeCard({required this.badge});
  final _TitleBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kFlameColor.withAlpha(60), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kFlameColor.withAlpha(28),
              shape: BoxShape.circle,
            ),
            child: Icon(badge.icon, size: 18, color: _kFlameColor),
          ),
          const SizedBox(width: 12),
          _Avatar(name: badge.name, avatarUrl: badge.avatarUrl, isPodium: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: _kFlameColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  badge.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ScriptaColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            badge.value,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ScriptaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── A single period leaderboard row ──────────────────────────────────────────────

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.rank,
    required this.row,
    required this.isMe,
    required this.showSessions,
  });

  final int rank; // zero-based
  final Map<String, dynamic> row;
  final bool isMe;
  final bool showSessions;

  bool get _isPodium => rank < 3;

  @override
  Widget build(BuildContext context) {
    final name = (row['display_name'] as String?)?.trim().isNotEmpty == true
        ? (row['display_name'] as String).trim()
        : context.l10n.jamRipassoAnonymous;
    final avatarUrl = row['avatar_url'] as String?;
    final score = (row['total_score'] as num?)?.toInt() ?? 0;
    final questions = (row['total_questions'] as num?)?.toInt() ?? 0;
    final totalSec = (row['total_duration_seconds'] as num?)?.toInt() ?? 0;
    final sessions = (row['sessions'] as num?)?.toInt() ?? 0;

    final medal = _JamPalette.medalColor(rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: isMe ? ScriptaColors.siennaFaint : ScriptaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? ScriptaColors.primaryDark.withAlpha(120)
              : (medal ?? ScriptaColors.rule).withAlpha(
                  _isPodium ? 110 : 90,
                ),
          width: isMe ? 1.4 : (_isPodium ? 1.2 : 0.8),
        ),
        boxShadow: _isPodium
            ? [
                BoxShadow(
                  color: (medal ?? ScriptaColors.primary).withAlpha(36),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          _RankBadge(rank: rank, medal: medal),
          const SizedBox(width: 12),
          _Avatar(name: name, avatarUrl: avatarUrl, isPodium: _isPodium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ScriptaColors.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: ScriptaColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.jamRipassoYouBadge,
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: ScriptaColors.background,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 12, color: ScriptaColors.inkFaint),
                    const SizedBox(width: 3),
                    Text(
                      _mmss(totalSec),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ScriptaColors.inkMuted,
                      ),
                    ),
                    if (showSessions) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.replay_rounded,
                          size: 12, color: ScriptaColors.inkFaint),
                      const SizedBox(width: 3),
                      Text(
                        '$sessions sess.',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ScriptaColors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ScorePill(
            score: score,
            questions: questions,
            podiumMedal: _isPodium ? medal : null,
          ),
        ],
      ),
    );
  }
}

// ─── Score pill (score / questions) ───────────────────────────────────────────────

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.score,
    required this.questions,
    this.podiumMedal,
  });
  final int score;
  final int questions;
  final Color? podiumMedal;

  @override
  Widget build(BuildContext context) {
    final accent = podiumMedal ?? ScriptaColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$score/$questions',
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: accent,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

// ─── Streak board (original behaviour, now the 4th segment) ───────────────────────

class _StreakBoard extends ConsumerWidget {
  const _StreakBoard({required this.jamId, required this.myId});
  final String jamId;
  final String myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(jamReviewLeaderboardProvider(jamId));

    return RefreshIndicator(
      color: ScriptaColors.primaryDark,
      onRefresh: () async =>
          ref.refresh(jamReviewLeaderboardProvider(jamId).future),
      child: boardAsync.when(
        data: (rows) {
          final ranked = rows
              .where((r) => ((r['review_streak'] as int?) ?? 0) > 0)
              .toList();

          if (ranked.isEmpty) {
            return _EmptyBoard(memberCount: rows.length);
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: ranked.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) return const _StreakHeader();
              final rank = i - 1;
              final row = ranked[rank];
              final isMe = row['id'] == myId;
              return _LeaderRow(
                rank: rank,
                row: row,
                isMe: isMe,
              )
                  .animate(delay: (rank * 45).ms)
                  .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.05, end: 0, duration: 280.ms);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: ScriptaColors.primaryDark,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => _ErrorBoard(
          message: context.l10n.errorPrefix('$e'),
        ),
      ),
    );
  }
}

// ─── Streak header blurb ──────────────────────────────────────────────────────────

class _StreakHeader extends StatelessWidget {
  const _StreakHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: ScriptaColors.primaryFaint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department_rounded,
                size: 20, color: _kFlameColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.jamRipassoSubtitle,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: ScriptaColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── A single streak leaderboard row ──────────────────────────────────────────────

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.row,
    required this.isMe,
  });

  final int rank; // zero-based
  final Map<String, dynamic> row;
  final bool isMe;

  bool get _isPodium => rank < 3;

  @override
  Widget build(BuildContext context) {
    final name = (row['display_name'] as String?)?.trim().isNotEmpty == true
        ? (row['display_name'] as String).trim()
        : context.l10n.jamRipassoAnonymous;
    final avatarUrl = row['avatar_url'] as String?;
    final streak = (row['review_streak'] as int?) ?? 0;
    final bestStreak = (row['review_best_streak'] as int?) ?? 0;
    final reviewedToday = row['reviewed_today'] == true;

    final medal = _JamPalette.medalColor(rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: isMe ? ScriptaColors.siennaFaint : ScriptaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? ScriptaColors.primaryDark.withAlpha(120)
              : (medal ?? ScriptaColors.rule).withAlpha(
                  _isPodium ? 110 : 90,
                ),
          width: isMe ? 1.4 : (_isPodium ? 1.2 : 0.8),
        ),
        boxShadow: _isPodium
            ? [
                BoxShadow(
                  color: (medal ?? ScriptaColors.primary).withAlpha(36),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          // Rank / medal badge
          _RankBadge(rank: rank, medal: medal),
          const SizedBox(width: 12),

          // Avatar
          _Avatar(name: name, avatarUrl: avatarUrl, isPodium: _isPodium),
          const SizedBox(width: 12),

          // Name + best streak
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ScriptaColors.ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: ScriptaColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.jamRipassoYouBadge,
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: ScriptaColors.background,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      context.l10n.jamRipassoBest(bestStreak),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ScriptaColors.inkFaint,
                      ),
                    ),
                    if (reviewedToday) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: ScriptaColors.primaryDark,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.l10n.jamRipassoDoneToday,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ScriptaColors.primaryDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Streak flame + number
          _StreakPill(streak: streak, podiumMedal: _isPodium ? medal : null),
        ],
      ),
    );
  }
}

// ─── Shared palette helpers ───────────────────────────────────────────────────────

class _JamPalette {
  /// Gold / silver / bronze for the top three; null otherwise.
  static Color? medalColor(int rank) => switch (rank) {
        0 => const Color(0xFFD9A93B), // gold
        1 => const Color(0xFFA9AEB2), // silver
        2 => const Color(0xFFC08A4E), // bronze
        _ => null,
      };
}

// ─── Rank badge (medal for top 3, plain number otherwise) ─────────────────────────

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.medal});
  final int rank;
  final Color? medal;

  @override
  Widget build(BuildContext context) {
    if (medal != null) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: medal!.withAlpha(36),
          shape: BoxShape.circle,
          border: Border.all(color: medal!.withAlpha(150), width: 1.4),
        ),
        child: Center(
          child: Icon(
            Icons.emoji_events_rounded,
            size: 16,
            color: medal,
          ),
        ),
      );
    }
    return SizedBox(
      width: 30,
      child: Center(
        child: Text(
          '${rank + 1}',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ScriptaColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

// ─── Avatar (network image or coloured initial) ───────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.isPodium,
  });

  final String name;
  final String? avatarUrl;
  final bool isPodium;

  @override
  Widget build(BuildContext context) {
    final size = isPodium ? 44.0 : 40.0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = ScriptaDecorations.bookCoverColor(name);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _initialAvatar(size, initial, avatarColor),
        ),
      );
    }
    return _initialAvatar(size, initial, avatarColor);
  }

  Widget _initialAvatar(double size, String initial, Color avatarColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [avatarColor, ScriptaColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.manrope(
            color: ScriptaColors.background,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Streak pill (flame + number) ─────────────────────────────────────────────────

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.streak, this.podiumMedal});
  final int streak;
  final Color? podiumMedal;

  @override
  Widget build(BuildContext context) {
    final accent = podiumMedal ?? ScriptaColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 15, color: _kFlameColor),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty / explanatory state ────────────────────────────────────────────────────

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.memberCount});
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: ScriptaColors.primaryFaint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Icon(Icons.local_fire_department_rounded,
                  size: 32, color: _kFlameColor),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          context.l10n.jamRipassoEmptyTitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: ScriptaColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.jamRipassoEmptyBody,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: ScriptaColors.inkMuted,
            fontSize: 14,
            height: 1.65,
          ),
        ),
      ],
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────────

class _ErrorBoard extends StatelessWidget {
  const _ErrorBoard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 100, 24, 32),
      children: [
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: ScriptaColors.inkMuted,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Time formatting helpers ──────────────────────────────────────────────────────

/// Local time-of-day as HH:mm.
String _hhmm(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

/// Duration in seconds as m:ss.
String _mmss(int seconds) {
  if (seconds <= 0) return '0:00';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
