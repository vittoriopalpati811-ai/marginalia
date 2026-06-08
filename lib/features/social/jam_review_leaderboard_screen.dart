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
// The "Ripasso" tab of a Jam: a ranked board of every member's spaced-repetition
// review streak. Backed by [jamReviewLeaderboardProvider] → the
// `jam_review_leaderboard` RPC (migration 051), which returns one row per member
// already ordered by current streak desc with a server-computed `reviewed_today`.
//
// Top three get podium styling (gold / silver / bronze flame accents); the
// current user's row is highlighted; an explanatory empty state appears when no
// one in the jam has started a streak yet. Pull-to-refresh re-runs the RPC.

class JamReviewLeaderboardScreen extends ConsumerWidget {
  const JamReviewLeaderboardScreen({super.key, required this.jamId});

  final String jamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(jamReviewLeaderboardProvider(jamId));
    final myId = ref.watch(currentUserProvider)?.id ?? '';

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.jamRipassoTitle,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: MarginaliaColors.ink,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: MarginaliaColors.primaryDark,
        onRefresh: () async =>
            ref.refresh(jamReviewLeaderboardProvider(jamId).future),
        child: boardAsync.when(
          data: (rows) {
            // Anyone with a current streak counts as "ranked". The RPC already
            // orders by streak desc, so the first entries are the leaders.
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
                if (i == 0) return const _BoardHeader();
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
              color: MarginaliaColors.primaryDark,
              strokeWidth: 1.5,
            ),
          ),
          error: (e, _) => _ErrorBoard(
            message: context.l10n.errorPrefix('$e'),
          ),
        ),
      ),
    );
  }
}

// ─── Header blurb ───────────────────────────────────────────────────────────────

class _BoardHeader extends StatelessWidget {
  const _BoardHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: MarginaliaColors.primaryFaint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.jamRipassoSubtitle,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: MarginaliaColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── A single leaderboard row ────────────────────────────────────────────────────

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

    final medal = _medalColor(rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: isMe
            ? MarginaliaColors.siennaFaint
            : MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? MarginaliaColors.primaryDark.withAlpha(120)
              : (medal ?? MarginaliaColors.rule).withAlpha(
                  _isPodium ? 110 : 90,
                ),
          width: isMe ? 1.4 : (_isPodium ? 1.2 : 0.8),
        ),
        boxShadow: _isPodium
            ? [
                BoxShadow(
                  color: (medal ?? MarginaliaColors.primary).withAlpha(36),
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
                          color: MarginaliaColors.ink,
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
                          color: MarginaliaColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.jamRipassoYouBadge,
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: const Color(0xFFF1EEE7),
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
                        color: MarginaliaColors.inkFaint,
                      ),
                    ),
                    if (reviewedToday) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_circle,
                        size: 13,
                        color: MarginaliaColors.primaryDark,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.l10n.jamRipassoDoneToday,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.primaryDark,
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

  /// Gold / silver / bronze for the top three; null otherwise.
  static Color? _medalColor(int rank) => switch (rank) {
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
            Icons.emoji_events,
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
            color: MarginaliaColors.inkFaint,
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
    final avatarColor = MarginaliaDecorations.bookCoverColor(name);

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
          colors: [avatarColor, MarginaliaColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.manrope(
            color: const Color(0xFFF1EEE7),
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
    final accent = podiumMedal ?? MarginaliaColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 14)),
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
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text('🔥', style: TextStyle(fontSize: 32)),
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
            color: MarginaliaColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.jamRipassoEmptyBody,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: MarginaliaColors.inkMuted,
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
              color: MarginaliaColors.inkMuted,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
