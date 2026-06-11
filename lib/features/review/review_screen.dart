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
import '../../core/motion/airbnb_motion.dart';
import '../../core/providers/review_provider.dart';
import '../quiz/quiz_generator.dart';
import '../quiz/quiz_lock.dart'
    show ripassoLockProvider, ripassoResultsProvider;

// ─── Ripasso review screen — Ripasso 2.0 (the daily quiz ritual) ─────────────
//
// Paper background (so the system status-bar icons stay dark). The daily session
// is now a multiple-choice quiz generated from the reader's own due highlights:
// a slim progress header with a streak flame pill, then the passage + options.
// Tapping an option gives immediate feedback (sage = correct, red = wrong with
// the right answer revealed) and auto-advances after ~700ms. A correct tap maps
// to an SM-2 "good" recall, a wrong tap to "forgot" — so spaced repetition keeps
// scheduling and tomorrow's deck stays fresh.
//
// When the deck is exhausted — or the screen is opened while today's session is
// already done (08:00 lock active) — a polished recap is shown: big score X/Y,
// accuracy %, time taken, completion time, and the current streak.

/// How long the correct/wrong feedback lingers before the deck auto-advances.
const Duration _kFeedbackHold = Duration(milliseconds: 700);

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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(reviewSessionControllerProvider);
    final due = ref.watch(dueHighlightsProvider);
    // If today's session is already locked (08:00 ritual), and we are NOT in the
    // middle of a just-finished in-memory session, show the persisted recap
    // instead of loading a deck again.
    final locked = ref.watch(ripassoLockProvider).asData?.value != null;

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
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
              color: ScriptaColors.primaryDark,
              strokeWidth: 1.5,
            ),
          ),
          error: (_, __) => const _EmptyState(),
          data: (deck) {
            // Already done today AND not mid-session → the polished summary.
            if (locked && !(session.isFinished && session.deck.isNotEmpty)) {
              return const _LockedSummary();
            }
            // Empty: nothing was due at all.
            if (deck.isEmpty) {
              return const _EmptyState();
            }
            // Finished: answered through the whole deck → live recap.
            if (session.isFinished && session.deck.isNotEmpty) {
              return _SessionSummary(
                score: session.score,
                total: session.questionsTotal > 0
                    ? session.questionsTotal
                    : session.total,
                durationSeconds: session.startedAt == null
                    ? 0
                    : DateTime.now().difference(session.startedAt!).inSeconds,
                completedAt: DateTime.now(),
                streakIncremented: session.streakIncremented,
              );
            }
            // Still loading the controller's in-memory deck (first frame).
            if (session.deck.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  color: ScriptaColors.primaryDark,
                  strokeWidth: 1.5,
                ),
              );
            }
            return _ActiveSession(
              total: session.total,
              reviewed: session.reviewed,
              index: session.index,
              question: session.currentQuestion,
            );
          },
        ),
      ),
    );
  }
}

// ─── Active session: header + question + options ─────────────────────────────

class _ActiveSession extends ConsumerStatefulWidget {
  const _ActiveSession({
    required this.total,
    required this.reviewed,
    required this.index,
    required this.question,
  });

  final int total;
  final int reviewed;
  final int index;
  final QuizQuestion? question;

  @override
  ConsumerState<_ActiveSession> createState() => _ActiveSessionState();
}

class _ActiveSessionState extends ConsumerState<_ActiveSession> {
  // Per-question transient state. Reset whenever the card index changes.
  String? _picked;
  bool _answered = false;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _autoAdvanceIfUnquizzable();
  }

  @override
  void didUpdateWidget(_ActiveSession old) {
    super.didUpdateWidget(old);
    // A new card reached the top → clear the feedback state.
    if (old.index != widget.index) {
      _advanceTimer?.cancel();
      _picked = null;
      _answered = false;
      _autoAdvanceIfUnquizzable();
    }
  }

  /// A card with no answerable question is auto-graded as a recall so the deck
  /// never stalls on an un-quizzable highlight (e.g. a one-word passage with no
  /// distractors). Runs after the frame so it never mutates state mid-build.
  void _autoAdvanceIfUnquizzable() {
    if (widget.question != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.question == null) {
        // counts:false → graded as a recall (deck advances, SM-2 schedules)
        // but NOT counted toward the quiz score/total.
        ref
            .read(reviewSessionControllerProvider.notifier)
            .answer(correct: true, counts: false);
      }
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _onPick(QuizQuestion q, String option) {
    if (_answered) return;
    final correct = option == q.answer;
    HapticFeedback.lightImpact();
    setState(() {
      _picked = option;
      _answered = true;
    });
    // Hold the feedback, then advance through the SM-2 pipeline.
    _advanceTimer = Timer(_kFeedbackHold, () {
      if (!mounted) return;
      ref
          .read(reviewSessionControllerProvider.notifier)
          .answer(correct: correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    // Null question is auto-advanced in initState — show a brief spinner.
    if (q == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: ScriptaColors.primaryDark,
          strokeWidth: 1.5,
        ),
      );
    }

    final it = Localizations.localeOf(context).languageCode == 'it';
    final progress = widget.total == 0 ? 0.0 : widget.reviewed / widget.total;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: _ProgressHeader(
            done: widget.reviewed,
            total: widget.total,
            progress: progress,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              key: ValueKey('q${widget.index}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _kindLabel(it, q.kind),
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: ScriptaColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 14),
                _PassageCard(question: q, answered: _answered),
                // After answering a which-book / which-author, reveal the source.
                if (q.kind != QuizKind.cloze &&
                    (q.bookTitle ?? '').trim().isNotEmpty &&
                    _answered) ...[
                  const SizedBox(height: 10),
                  Text(
                    [q.bookTitle, q.bookAuthor]
                        .where((s) => (s ?? '').trim().isNotEmpty)
                        .join(' · '),
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.inkFaint,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ...q.options.map((opt) => _OptionTile(
                      label: opt,
                      isCorrect: opt == q.answer,
                      isPicked: opt == _picked,
                      answered: _answered,
                      onTap: () => _onPick(q, opt),
                    )),
              ],
            ),
          )
              .animate(key: ValueKey('anim${widget.index}'))
              .fadeIn(duration: AirbnbMotion.standard, curve: AirbnbMotion.enter)
              .slideY(begin: 0.04, end: 0, duration: AirbnbMotion.standard),
        ),
      ],
    );
  }
}

String _kindLabel(bool it, QuizKind kind) {
  switch (kind) {
    case QuizKind.cloze:
      return it ? 'Completa il passaggio' : 'Complete the passage';
    case QuizKind.whichBook:
      return it ? 'Da quale libro?' : 'Which book?';
    case QuizKind.whichAuthor:
      return it ? 'Chi è l’autore?' : 'Who is the author?';
  }
}

// ─── Passage card (the question stem) ────────────────────────────────────────

class _PassageCard extends StatelessWidget {
  const _PassageCard({required this.question, required this.answered});

  final QuizQuestion question;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.ebGaramond(
      fontSize: 20,
      height: 1.55,
      color: ScriptaColors.ink,
    );

    Widget child;
    // After answering a cloze, fill the blank back in with the correct word.
    if (question.kind == QuizKind.cloze &&
        answered &&
        (question.clozeWord ?? '').isNotEmpty) {
      final parts = question.prompt.split('_____');
      child = Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: parts.first),
            TextSpan(
              text: question.clozeWord,
              style: style.copyWith(
                color: ScriptaColors.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (parts.length > 1)
              TextSpan(text: parts.sublist(1).join('_____')),
          ],
        ),
      );
    } else {
      child = Text(question.prompt, style: style);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ScriptaDecorations.card(radius: 18),
      child: child,
    );
  }
}

// ─── Option tile with immediate feedback ─────────────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.isCorrect,
    required this.isPicked,
    required this.answered,
    required this.onTap,
  });

  final String label;
  final bool isCorrect;
  final bool isPicked;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Brand red (0xFFB94A41) for a wrong pick — used only inline here.
    const red = Color(0xFFB94A41);
    var bg = ScriptaColors.surface;
    var border = ScriptaColors.rule;
    if (answered) {
      // Correct option always highlighted sage; the wrong pick goes red.
      if (isCorrect) {
        bg = ScriptaColors.siennaFaint;
        border = ScriptaColors.primaryDark;
      } else if (isPicked) {
        bg = const Color(0xFFF6E4E4);
        border = red;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AirbnbMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ScriptaColors.ink,
                  ),
                ),
              ),
              if (answered && isCorrect)
                const Icon(Icons.check_circle,
                    color: ScriptaColors.primaryDark, size: 20),
              if (answered && isPicked && !isCorrect)
                const Icon(Icons.cancel, color: red, size: 20),
            ],
          ),
        ),
      ),
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
    final it = Localizations.localeOf(context).languageCode == 'it';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it ? '$done di $total' : '$done of $total',
                style: ScriptaTextStyles.label,
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
                    backgroundColor: ScriptaColors.ruleFaint,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ScriptaColors.primary,
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

/// A flame + streak count pill, reused by the review header and the summary.
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: ScriptaColors.siennaFaint,
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
            color: ScriptaColors.primaryDark,
          ),
          const SizedBox(width: 5),
          Text(
            '$streak',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ScriptaColors.primaryDark,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state — nothing was due ───────────────────────────────────────────

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak =
        ref.watch(reviewStateProvider).asData?.value.currentStreak ?? 0;
    final it = Localizations.localeOf(context).languageCode == 'it';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsFill.flame,
              size: 64,
              color: streak > 0
                  ? ScriptaColors.primaryDark.withOpacity(0.85)
                  : ScriptaColors.siennaLight,
            ),
            const SizedBox(height: 24),
            Text(
              it ? 'Tutto ripassato' : 'All caught up',
              textAlign: TextAlign.center,
              style: ScriptaTextStyles.heroTitle,
            ),
            const SizedBox(height: 12),
            Text(
              it
                  ? 'Niente da ripassare adesso. Torna più tardi.'
                  : 'Nothing to review right now. Come back later.',
              textAlign: TextAlign.center,
              style: ScriptaTextStyles.subtitle,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(it ? 'Torna alla libreria' : 'Back to library'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Locked summary — opened while today's session is already done ───────────
//
// Reads the persisted recap (score/total/duration/completedAt) and renders the
// same polished summary as the in-session finish, with the live streak.

class _LockedSummary extends ConsumerWidget {
  const _LockedSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(ripassoResultsProvider).asData?.value;
    if (results == null) {
      // Lock set but no recap stored (e.g. a legacy completion) → calm fallback.
      return const _EmptyState();
    }
    return _SessionSummary(
      score: results.score,
      total: results.total > 0 ? results.total : results.cards,
      durationSeconds: results.durationSeconds,
      completedAt: results.completedAt,
      streakIncremented: false,
    );
  }
}

// ─── Session summary (founder point 1) ───────────────────────────────────────
//
// The polished recap: a success burst, big score X/Y, accuracy %, time taken
// (m:ss), completion time (HH:mm), the current streak with a flame, and the
// "come back tomorrow" line. Subtle staggered entrance (airbnb_motion).

class _SessionSummary extends ConsumerWidget {
  const _SessionSummary({
    required this.score,
    required this.total,
    required this.durationSeconds,
    required this.completedAt,
    required this.streakIncremented,
  });

  final int score;
  final int total;
  final int durationSeconds;
  final DateTime completedAt;
  final bool streakIncremented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final streak =
        ref.watch(reviewStateProvider).asData?.value.currentStreak ?? 0;
    final accuracy = total == 0 ? 0 : (score * 100 / total).round();

    String head;
    if (accuracy >= 80) {
      head = it ? 'Memoria di ferro!' : 'Razor-sharp memory!';
    } else if (accuracy >= 50) {
      head = it ? 'Niente male!' : 'Not bad!';
    } else {
      head = it ? 'Ottimo allenamento' : 'Good practice';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SuccessBurst()
                .animate()
                .scale(
                  begin: const Offset(0.6, 0.6),
                  end: const Offset(1, 1),
                  duration: AirbnbMotion.emphasis,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 22),
            Text(
              head,
              textAlign: TextAlign.center,
              style: ScriptaTextStyles.heroTitle,
            )
                .animate()
                .fadeIn(
                    duration: AirbnbMotion.standard,
                    delay: 80.ms,
                    curve: AirbnbMotion.enter)
                .slideY(begin: 0.08, end: 0, duration: AirbnbMotion.standard),
            const SizedBox(height: 24),
            // Big score circle.
            Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                color: ScriptaColors.primaryFaint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$score/$total',
                style: GoogleFonts.ebGaramond(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.primaryDark,
                ),
              ),
            )
                .animate()
                .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  delay: 140.ms,
                  duration: AirbnbMotion.emphasis,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 24),
            // Stat row: accuracy · time · completion time.
            _StatRow(
              accuracy: accuracy,
              durationSeconds: durationSeconds,
              completedAt: completedAt,
              it: it,
            )
                .animate()
                .fadeIn(
                    duration: AirbnbMotion.standard,
                    delay: 220.ms,
                    curve: AirbnbMotion.enter)
                .slideY(begin: 0.08, end: 0, duration: AirbnbMotion.standard),
            const SizedBox(height: 22),
            // Streak pill with flame. When this session pushed the streak to a
            // new day, the pill gives a one-time celebratory pop.
            Animate(
              effects: [
                FadeEffect(duration: AirbnbMotion.standard, delay: 300.ms),
                if (streakIncremented)
                  ScaleEffect(
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                    delay: 300.ms,
                    duration: AirbnbMotion.emphasis,
                    curve: Curves.elasticOut,
                  ),
              ],
              child: StreakPill(streak: streak),
            ),
            const SizedBox(height: 20),
            Text(
              it
                  ? 'Torna domani: nuove domande dai tuoi highlight'
                  : 'Come back tomorrow: fresh questions from your highlights',
              textAlign: TextAlign.center,
              style: ScriptaTextStyles.subtitle,
            )
                .animate()
                .fadeIn(
                    duration: AirbnbMotion.standard,
                    delay: 360.ms,
                    curve: AirbnbMotion.enter),
            const SizedBox(height: 28),
            const _NextReviewCountdown(),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => context.pop(),
              child: Text(it ? 'Torna alla libreria' : 'Back to library'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accuracy %, time taken (m:ss), completion time (HH:mm) — three quiet stats.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.accuracy,
    required this.durationSeconds,
    required this.completedAt,
    required this.it,
  });

  final int accuracy;
  final int durationSeconds;
  final DateTime completedAt;
  final bool it;

  String _duration(int s) {
    final d = s < 0 ? 0 : s;
    final m = d ~/ 60;
    final sec = d % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: ScriptaDecorations.card(radius: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Stat(
            value: '$accuracy%',
            label: it ? 'Precisione' : 'Accuracy',
            icon: PhosphorIconsFill.target,
          ),
          const SizedBox(width: 26),
          _Stat(
            value: _duration(durationSeconds),
            label: it ? 'Tempo' : 'Time',
            icon: PhosphorIconsFill.timer,
          ),
          const SizedBox(width: 26),
          _Stat(
            value: _time(completedAt),
            label: it ? 'Completato' : 'Finished',
            icon: PhosphorIconsFill.checkCircle,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: ScriptaColors.primaryDark),
        const SizedBox(height: 7),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ScriptaColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: ScriptaColors.inkMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── "Great Success" completion burst ────────────────────────────────────────
//
// A sage check-circle springs in, a ring expands and fades behind it, and six
// sparkles radiate outward. No neon, no confetti — it stays in the paper/sienna
// world.

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
              border: Border.all(color: ScriptaColors.primary, width: 3),
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
                  color: ScriptaColors.siennaLight,
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
                colors: [ScriptaColors.primary, ScriptaColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: ScriptaColors.primary.withOpacity(0.40),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child:
                const Icon(Icons.check_rounded, size: 52, color: Colors.white),
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
// A quiet countdown to tomorrow morning's 08:00 review (the hour the morning
// reminder fires). A single 1-second Timer drives it, disposed with the widget
// so it never leaks. Tabular figures keep the clock from jittering.

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
    // the countdown reads 00:00:00 instead of rolling a full 24h.
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
    final it = Localizations.localeOf(context).languageCode == 'it';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          PhosphorIconsRegular.clock,
          size: 14,
          color: ScriptaColors.inkFaint,
        ),
        const SizedBox(width: 7),
        Text(
          it
              ? 'Prossimo ripasso tra ${_format(_remaining)}'
              : 'Next review in ${_format(_remaining)}',
          style: ScriptaTextStyles.label.copyWith(
            fontSize: 12,
            color: ScriptaColors.inkMuted,
            // Tabular figures so the seconds tick without the row reflowing.
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
