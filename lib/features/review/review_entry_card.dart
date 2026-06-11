import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/providers/review_provider.dart';
import '../quiz/quiz_lock.dart'
    show ripassoLockProvider, ripassoResultsProvider, RipassoResults;

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

    // Hard once-a-day lock that resets at 08:00 the next morning (not midnight),
    // matching the Quiz. Set when a review is graded (SharedPreferences), so the
    // card stays "completato" until 08:00 even if more cards are technically due.
    final ripassoLocked =
        ref.watch(ripassoLockProvider).asData?.value != null;

    // Once today's review is done, the card LOCKS to a non-tappable "completato"
    // state until tomorrow's slot — a ripasso is a once-a-day ritual, so even if
    // more cards are technically due it won't reopen today. Otherwise: the
    // tappable due card, or (nothing due, nothing done) hide so it never nags.
    final Widget card;
    if (ripassoLocked || reviewedToday) {
      // Today's persisted recap (cards + grade tallies) rides on the locked
      // card so the results stay visible until the next 08:00 reset.
      final results = ref.watch(ripassoResultsProvider).asData?.value;
      card = _CompletedCard(streak: streak, results: results);
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
        decoration: ScriptaDecorations.card(radius: 20),
        child: Row(
          children: [
            // Flame / book glyph tile.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ScriptaColors.siennaFaint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                streak > 0
                    ? PhosphorIconsFill.flame
                    : PhosphorIconsFill.bookOpen,
                size: 22,
                color: ScriptaColors.primaryDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.ripassoOfTheDay,
                    style: ScriptaTextStyles.sectionTitleClean,
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
              color: ScriptaColors.inkFaint,
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
    final base = ScriptaTextStyles.subtitle;
    final parts = <InlineSpan>[
      TextSpan(
        text: context.l10n.ripassoDueCount(dueCount),
        style: base.copyWith(
          color: ScriptaColors.primaryDark,
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
  const _CompletedCard({required this.streak, this.results});

  final int streak;
  final RipassoResults? results;

  @override
  Widget build(BuildContext context) {
    // With a persisted recap, the second line becomes today's results
    // ("N carte · ricordate/difficili/da rivedere"); otherwise the usual
    // "come back tomorrow". The streak rides along in both cases.
    final base = results != null
        ? context.l10n.ripassoRecapLine(
            results!.cards, results!.good, results!.hard, results!.forgot)
        : context.l10n.ripassoComeBackTomorrow;
    final subtitle = streak > 0
        ? '$base  ·  ${context.l10n.ripassoStreak(streak)}'
        : base;

    // Tappable while locked: re-opens today's polished recap (founder point C).
    return PressableSpring(
      onPressed: () => context.push('/review'),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: ScriptaDecorations.card(radius: 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ScriptaColors.primary, ScriptaColors.primaryDark],
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
                  style: ScriptaTextStyles.sectionTitleClean,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ScriptaTextStyles.subtitle,
                ),
              ],
            ),
          ),
          if (streak > 0) ...[
            const SizedBox(width: 8),
            const Icon(
              PhosphorIconsFill.flame,
              size: 18,
              color: ScriptaColors.primaryDark,
            ),
          ],
        ],
      ),
      ),
    );
  }
}
