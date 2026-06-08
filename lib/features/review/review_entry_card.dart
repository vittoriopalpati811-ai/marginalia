import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/providers/review_provider.dart';

// ─── "Ripasso del giorno" — Library entry point ──────────────────────────────
//
// The first interactive element under the Library header: a warm card showing
// the due count + streak flame, tapping it opens /review. When there is nothing
// due AND the user already reviewed today, it collapses to a quiet one-line
// "completed" pill; when nothing is due and they haven't reviewed, it hides
// entirely (no nagging).

class RipassoEntryCard extends ConsumerWidget {
  const RipassoEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueCount = ref.watch(dueCountProvider).asData?.value ?? 0;
    final reviewState = ref.watch(reviewStateProvider).asData?.value;
    final streak = reviewState?.currentStreak ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Compare by LOCAL calendar day, not raw DateTime ==. Isar can return
    // lastReviewedOn as a UTC DateTime, so `== today` (a local-midnight value)
    // is false even right after a review → the card never locked. Normalise to
    // local + compare y/m/d.
    final last = reviewState?.lastReviewedOn?.toLocal();
    final reviewedToday = last != null &&
        last.year == today.year &&
        last.month == today.month &&
        last.day == today.day;

    // Once today's review is done, the card LOCKS to a non-tappable "completato"
    // state until tomorrow's slot — a ripasso is a once-a-day ritual, so even if
    // more cards are technically due it won't reopen today. Otherwise: the
    // tappable due card, or (nothing due, nothing done) hide so it never nags.
    final Widget card;
    if (reviewedToday) {
      card = _CompletedCard(streak: streak);
    } else if (dueCount > 0) {
      card = _DueCard(dueCount: dueCount, streak: streak);
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: card,
    ).animate().fadeIn(duration: 500.ms, curve: Curves.easeOut).slideY(
          begin: 0.05,
          end: 0,
          duration: 500.ms,
        );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.dueCount, required this.streak});

  final int dueCount;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return PressableSpring(
      onPressed: () => context.push('/review'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: MarginaliaDecorations.card(radius: 20),
        child: Row(
          children: [
            // Flame / book glyph tile.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                streak > 0
                    ? PhosphorIconsFill.flame
                    : PhosphorIconsFill.bookOpen,
                size: 22,
                color: MarginaliaColors.primaryDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.ripassoOfTheDay,
                    style: MarginaliaTextStyles.sectionTitleClean,
                  ),
                  const SizedBox(height: 3),
                  _Subtitle(dueCount: dueCount, streak: streak),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
              color: MarginaliaColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// "{N} to review · {streak} day streak", with the count emphasised in sage.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.dueCount, required this.streak});

  final int dueCount;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final base = MarginaliaTextStyles.subtitle;
    final parts = <InlineSpan>[
      TextSpan(
        text: context.l10n.ripassoDueCount(dueCount),
        style: base.copyWith(
          color: MarginaliaColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    ];
    if (streak > 0) {
      parts
        ..add(TextSpan(text: '  ·  ', style: base))
        ..add(TextSpan(
          text: context.l10n.ripassoStreak(streak),
          style: base,
        ));
    }
    return Text.rich(
      TextSpan(children: parts),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The locked "Ripasso di oggi completato!" state — shown after today's review
/// is done and NOT tappable until tomorrow's slot. A calm check-circle pops in
/// (elastic) for a small sense of accomplishment; the streak flame rides along.
class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final subtitle = streak > 0
        ? '${context.l10n.ripassoComeBackTomorrow}  ·  ${context.l10n.ripassoStreak(streak)}'
        : context.l10n.ripassoComeBackTomorrow;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MarginaliaDecorations.card(radius: 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [MarginaliaColors.primary, MarginaliaColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_rounded, size: 24, color: Colors.white),
          )
              .animate()
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1, 1),
                duration: 460.ms,
                curve: Curves.elasticOut,
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.ripassoTodayCompleted,
                  style: MarginaliaTextStyles.sectionTitleClean,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MarginaliaTextStyles.subtitle,
                ),
              ],
            ),
          ),
          if (streak > 0) ...[
            const SizedBox(width: 8),
            const Icon(
              PhosphorIconsFill.flame,
              size: 18,
              color: MarginaliaColors.primaryDark,
            ),
          ],
        ],
      ),
    );
  }
}
