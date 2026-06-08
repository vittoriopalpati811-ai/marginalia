import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/review/sm2.dart';
import '../../core/providers/review_provider.dart';
import 'review_deck.dart';

// ─── Ripasso review screen — the daily recall ritual ─────────────────────────
//
// Paper background (so the system status-bar icons stay dark). A slim progress
// header with a streak flame pill; the swipe deck in the centre; three grading
// buttons at the bottom, each captioned with the next SM-2 interval as a legible
// promise ("tomorrow" / "in 3d" / "in 2 weeks"). When the deck is empty or the
// session finishes, a calm "all caught up" state with the streak.

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  @override
  void initState() {
    super.initState();
    // Load today's deck once after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reviewSessionControllerProvider.notifier).load();
    });
  }

  void _grade(ReviewGrade grade) {
    HapticFeedback.lightImpact();
    ref.read(reviewSessionControllerProvider.notifier).grade(grade);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(reviewSessionControllerProvider);
    final due = ref.watch(dueHighlightsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(context.l10n.ripassoTitle),
      ),
      body: SafeArea(
        top: false,
        child: due.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              color: MarginaliaColors.primaryDark,
              strokeWidth: 1.5,
            ),
          ),
          error: (_, __) => _FinishedState(
            streak: 0,
            isEmpty: true,
            streakIncremented: false,
          ),
          data: (deck) {
            // Empty: nothing was due at all.
            if (deck.isEmpty) {
              return _StreakFinished(isEmpty: true);
            }
            // Finished: graded through the whole deck.
            if (session.isFinished && session.deck.isNotEmpty) {
              return _StreakFinished(
                isEmpty: false,
                streakIncremented: session.streakIncremented,
              );
            }
            // Still loading the controller's in-memory deck (first frame).
            if (session.deck.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.primaryDark,
                  strokeWidth: 1.5,
                ),
              );
            }
            return _ActiveSession(
              total: session.total,
              reviewed: session.reviewed,
              deck: session.deck,
              index: session.index,
              onGrade: _grade,
            );
          },
        ),
      ),
    );
  }
}

// ─── Active session: header + deck + grading bar ─────────────────────────────

class _ActiveSession extends ConsumerWidget {
  const _ActiveSession({
    required this.total,
    required this.reviewed,
    required this.deck,
    required this.index,
    required this.onGrade,
  });

  final int total;
  final int reviewed;
  final List deck;
  final int index;
  final void Function(ReviewGrade) onGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = total == 0 ? 0.0 : reviewed / total;
    final current = deck[index];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: _ProgressHeader(
            done: reviewed,
            total: total,
            progress: progress,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: ReviewDeck(
              deck: List.castFrom(deck),
              index: index,
              onGrade: onGrade,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: _GradingBar(
            highlight: current,
            onGrade: onGrade,
          ),
        ),
      ],
    );
  }
}

// ─── Progress header with streak pill ────────────────────────────────────────

class _ProgressHeader extends ConsumerWidget {
  const _ProgressHeader({
    required this.done,
    required this.total,
    required this.progress,
  });

  final int done;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak =
        ref.watch(reviewStateProvider).asData?.value.currentStreak ?? 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.ripassoProgress(done, total),
                style: MarginaliaTextStyles.label,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 3,
                    backgroundColor: MarginaliaColors.ruleFaint,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      MarginaliaColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        StreakPill(streak: streak),
      ],
    );
  }
}

/// A flame + streak count pill, reused by the review header and the finished
/// state.
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: MarginaliaColors.siennaFaint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            streak > 0
                ? PhosphorIconsFill.flame
                : PhosphorIconsRegular.flame,
            size: 15,
            color: MarginaliaColors.primaryDark,
          ),
          const SizedBox(width: 5),
          Text(
            '$streak',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: MarginaliaColors.primaryDark,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grading bar ─────────────────────────────────────────────────────────────

class _GradingBar extends StatelessWidget {
  const _GradingBar({required this.highlight, required this.onGrade});

  final dynamic highlight; // Highlight (native or web stub) — only reads SM-2.
  final void Function(ReviewGrade) onGrade;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _GradeButton(
            label: context.l10n.ripassoForgot,
            caption: _intervalLabel(context, ReviewGrade.forgot),
            kind: _GradeKind.neutral,
            onTap: () => onGrade(ReviewGrade.forgot),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GradeButton(
            label: context.l10n.ripassoHard,
            caption: _intervalLabel(context, ReviewGrade.hard),
            kind: _GradeKind.hard,
            onTap: () => onGrade(ReviewGrade.hard),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GradeButton(
            label: context.l10n.ripassoGood,
            caption: _intervalLabel(context, ReviewGrade.good),
            kind: _GradeKind.good,
            onTap: () => onGrade(ReviewGrade.good),
          ),
        ),
      ],
    );
  }

  /// Computes the human next-interval label for [grade] given the card's current
  /// SM-2 state, turning the algorithm into a legible promise under each button.
  String _intervalLabel(BuildContext context, ReviewGrade grade) {
    final result = scheduleSm2(
      easeFactor: (highlight.reviewEase as double?) ?? kDefaultEaseFactor,
      intervalDays: (highlight.reviewIntervalDays as int?) ?? 0,
      repetitions: (highlight.reviewReps as int?) ?? 0,
      grade: grade,
      now: DateTime.now(),
    );
    final days = result.intervalDays;
    if (days <= 1) return context.l10n.ripassoNextTomorrow;
    if (days < 14) return context.l10n.ripassoNextDays(days);
    final weeks = (days / 7).round();
    return context.l10n.ripassoNextWeeks(weeks);
  }
}

enum _GradeKind { neutral, hard, good }

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.caption,
    required this.kind,
    required this.onTap,
  });

  final String label;
  final String caption;
  final _GradeKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      _GradeKind.neutral => (
          Colors.transparent,
          MarginaliaColors.ink,
          MarginaliaColors.rule,
        ),
      _GradeKind.hard => (
          MarginaliaColors.siennaLight,
          MarginaliaColors.ink,
          MarginaliaColors.siennaLight,
        ),
      _GradeKind.good => (
          MarginaliaColors.primary,
          MarginaliaColors.ink,
          MarginaliaColors.primary,
        ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MarginaliaTextStyles.label.copyWith(
            fontSize: 10,
            color: MarginaliaColors.inkFaint,
          ),
        ),
      ],
    );
  }
}

// ─── Finished / empty state ──────────────────────────────────────────────────
//
// Reads the live streak so the "all caught up" copy can celebrate it.

class _StreakFinished extends ConsumerWidget {
  const _StreakFinished({
    required this.isEmpty,
    this.streakIncremented = false,
  });

  final bool isEmpty;
  final bool streakIncremented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak =
        ref.watch(reviewStateProvider).asData?.value.currentStreak ?? 0;
    return _FinishedState(
      streak: streak,
      isEmpty: isEmpty,
      streakIncremented: streakIncremented,
    );
  }
}

class _FinishedState extends StatelessWidget {
  const _FinishedState({
    required this.streak,
    required this.isEmpty,
    required this.streakIncremented,
  });

  final int streak;
  final bool isEmpty;
  final bool streakIncremented;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Completed a session → a "Great Success" burst (check pops in with
            // an elastic spring, a ring expands, sparkles radiate). The empty
            // state keeps a calm flame so it never over-celebrates "nothing due".
            if (isEmpty)
              Icon(
                PhosphorIconsFill.flame,
                size: 64,
                color: streak > 0
                    ? MarginaliaColors.primaryDark.withOpacity(0.85)
                    : MarginaliaColors.siennaLight,
              )
            else
              const _SuccessBurst(),
            const SizedBox(height: 24),
            Text(
              isEmpty
                  ? context.l10n.ripassoEmptyTitle
                  : context.l10n.ripassoAllDone,
              textAlign: TextAlign.center,
              style: MarginaliaTextStyles.heroTitle,
            ),
            const SizedBox(height: 12),
            Text(
              isEmpty
                  ? context.l10n.ripassoEmpty
                  : context.l10n.ripassoStreakDays(streak),
              textAlign: TextAlign.center,
              style: MarginaliaTextStyles.subtitle,
            ),
            const SizedBox(height: 28),
            const _NextReviewCountdown(),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(context.l10n.ripassoBackToLibrary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── "Great Success" completion burst ────────────────────────────────────────
//
// A satisfying, on-brand success moment (a calm adaptation of the classic
// "Great Success" micro-interaction): a sage check-circle springs in
// (elasticOut), a ring expands and fades behind it, and six sparkles radiate
// outward. No neon, no confetti — it stays in the paper/sienna world.

class _SuccessBurst extends StatelessWidget {
  const _SuccessBurst({this.diameter = 96});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final field = diameter * 1.9;
    return SizedBox(
      width: field,
      height: field,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ring.
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MarginaliaColors.primary, width: 3),
            ),
          )
              .animate()
              .scaleXY(
                  begin: 0.55,
                  end: 1.8,
                  duration: 760.ms,
                  curve: Curves.easeOutCubic)
              .fadeOut(duration: 760.ms),
          // Radiating sparkles.
          for (var i = 0; i < 6; i++)
            Builder(builder: (_) {
              final angle = (math.pi * 2 / 6) * i;
              final dir = Offset(math.cos(angle), math.sin(angle));
              return Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: MarginaliaColors.siennaLight,
                ),
              )
                  .animate()
                  .move(
                    begin: Offset.zero,
                    end: dir * (diameter * 0.92),
                    duration: 640.ms,
                    delay: 140.ms,
                    curve: Curves.easeOutCubic,
                  )
                  .fadeOut(begin: 1.0, duration: 460.ms, delay: 300.ms);
            }),
          // Check circle — pops in with an elastic spring.
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [MarginaliaColors.primary, MarginaliaColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: MarginaliaColors.primary.withOpacity(0.40),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, size: 52, color: Colors.white),
          )
              .animate()
              .scale(
                begin: const Offset(0, 0),
                end: const Offset(1, 1),
                duration: 560.ms,
                curve: Curves.elasticOut,
              ),
        ],
      ),
    );
  }
}

// ─── Live "next review in HH:MM:SS" countdown ────────────────────────────────
//
// A quiet, app-style countdown to tomorrow morning's 08:00 review (the hour the
// morning reminder fires). A single 1-second Timer drives it, disposed with the
// widget so it never leaks. Tabular figures keep the clock from jittering as the
// digits change.

/// The hour the daily review window reopens — kept in sync with the 08:00
/// morning reminder scheduled in app.dart.
const int _kReviewHour = 8;

class _NextReviewCountdown extends StatefulWidget {
  const _NextReviewCountdown();

  @override
  State<_NextReviewCountdown> createState() => _NextReviewCountdownState();
}

class _NextReviewCountdownState extends State<_NextReviewCountdown> {
  Timer? _ticker;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _untilNextReview();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _untilNextReview());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Time from now until the next occurrence of [_kReviewHour]:00 local. If it
  /// is already past 08:00 today, counts to 08:00 tomorrow.
  Duration _untilNextReview() {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, _kReviewHour);
    // Use isBefore (not !isAfter): at exactly 08:00:00 `next` equals `now`, so
    // the countdown reads 00:00:00 instead of rolling a full 24h to "24:00:00".
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));
    return next.difference(now);
  }

  String _format(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(total.inHours)}:${two(total.inMinutes % 60)}:${two(total.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsRegular.clock,
          size: 14,
          color: MarginaliaColors.inkFaint,
        ),
        const SizedBox(width: 7),
        Text(
          context.l10n.ripassoNextReview(_format(_remaining)),
          style: MarginaliaTextStyles.label.copyWith(
            fontSize: 12,
            color: MarginaliaColors.inkMuted,
            // Tabular figures so the seconds tick without the row reflowing.
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
