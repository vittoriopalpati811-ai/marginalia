// ─── Quiz — active recall over your highlights ───────────────────────────────
//
// A short, gamified recall session: 10 questions generated locally from the
// reader's own highlights. Every question is ANSWERABLE by tapping one of up to
// four options — cloze (pick the missing word), which-book, which-author. No AI,
// no network.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/review_provider.dart';
import '../../core/theme.dart';
import 'quiz_generator.dart';
import 'quiz_lock.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, this.bookTitle, this.appBarTitle});

  /// When set, the quiz is built ONLY from highlights of this book (used by the
  /// Jam "Libro del mese" → quiz the month's book with your circle).
  final String? bookTitle;

  /// Optional app-bar title override (defaults to "Quiz").
  final String? appBarTitle;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  bool _loading = true;
  List<QuizQuestion> _questions = const [];
  int _index = 0;
  int _score = 0;

  // per-question transient state
  String? _picked;
  bool _answered = false;

  // highlights you missed → scheduled for Ripasso at the end
  final Set<int> _wrongIds = {};
  int _scheduled = 0;

  // Daily-quiz 08:00 lock (general quiz only; a per-book quiz launched from a
  // Jam is not throttled). When locked, the screen shows a "come back at 08:00"
  // state instead of loading questions.
  bool _locked = false;

  bool get _it => Localizations.localeOf(context).languageCode == 'it';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      // Daily-quiz lock: only the general quiz (no specific book) is a once-a-
      // day ritual. While it's locked, show the completed state.
      if (widget.bookTitle == null) {
        final lockedUntil = await quizLockedUntil();
        if (lockedUntil != null) {
          if (!mounted) return;
          setState(() {
            _locked = true;
            _loading = false;
          });
          return;
        }
      }
      final highlights = await ref.read(allHighlightsProvider.future);
      final filter = widget.bookTitle?.trim().toLowerCase();
      final sources = highlights
          .where((h) => filter == null
              ? true
              : (h.bookTitle ?? '').trim().toLowerCase() == filter)
          .map((h) =>
              QuizSource(h.content, h.bookTitle, h.bookAuthor, highlightId: h.id))
          .toList();
      final qs = generateQuiz(sources, count: 10, rng: Random());
      if (!mounted) return;
      setState(() {
        _questions = qs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _picked = null;
      _answered = false;
      _loading = true;
      _wrongIds.clear();
      _scheduled = 0;
    });
    _load();
  }

  void _next() {
    if (_index >= _questions.length - 1) {
      setState(() => _index = _questions.length); // → results
      _feedRipasso();
      _shareQuizToJams();
      _markCompleted();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _answered = false;
    });
  }

  void _answer(QuizQuestion q, String option) {
    if (_answered) return;
    HapticFeedback.selectionClick();
    setState(() {
      _picked = option;
      _answered = true;
      if (option == q.answer) {
        _score++;
      } else if (q.highlightId != null && q.highlightId! > 0) {
        _wrongIds.add(q.highlightId!);
      }
    });
  }

  // At the end, schedule every missed passage for Ripasso (spaced repetition) so
  // the quiz reinforces exactly what you forgot. Native-only; no-op on web.
  Future<void> _feedRipasso() async {
    final n = await markHighlightsDueForReview(ref, _wrongIds);
    if (mounted && n > 0) setState(() => _scheduled = n);
  }

  // Auto-share the finished quiz with the reader's Jams — a best-effort push to
  // jam-mates (mirrors the Ripasso completion share). Never blocks the UI.
  Future<void> _shareQuizToJams() async {
    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.notifyJamMatesQuizDone(_score, _questions.length);
      // Structured result so it surfaces in the Jam results feed (not just a
      // notification) — visible to the user AND every Jam they belong to.
      await svc.logQuizResultsToJams(_score, _questions.length);
    } catch (_) {/* best-effort */}
  }

  // Lock the general daily quiz until 08:00 tomorrow once it's finished.
  Future<void> _markCompleted() async {
    if (widget.bookTitle != null) return; // per-book quizzes aren't throttled
    await markQuizCompletedNow();
    ref.invalidate(quizLockProvider);
  }

  // Shown when the daily quiz has already been done — locked until 08:00 the
  // next morning (mirrors Ripasso's once-a-day rhythm).
  Widget _buildLocked(bool it) {
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ScriptaColors.ink,
        title: Text(widget.appBarTitle ?? 'Quiz',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: ScriptaColors.ink)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: ScriptaColors.primaryFaint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 40, color: ScriptaColors.primaryDark),
              ),
              const SizedBox(height: 22),
              Text(
                it ? 'Quiz completato' : 'Quiz complete',
                style: GoogleFonts.ebGaramond(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                it
                    ? 'Torna domani alle 08:00 per il prossimo quiz.'
                    : 'Come back tomorrow at 08:00 for the next quiz.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14.5,
                  height: 1.5,
                  color: ScriptaColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(bool it, QuizKind kind) {
    switch (kind) {
      case QuizKind.cloze:
        return it ? 'Completa il passaggio' : 'Complete the passage';
      case QuizKind.whichBook:
        return it ? 'Da quale libro?' : 'Which book?';
      case QuizKind.whichAuthor:
        return it ? 'Chi è l’autore?' : 'Who is the author?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = _it;
    if (_locked) return _buildLocked(it);
    final inQuestion =
        !_loading && _questions.isNotEmpty && _index < _questions.length;
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ScriptaColors.ink,
        title: Text(widget.appBarTitle ?? 'Quiz',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 18, color: ScriptaColors.ink)),
        actions: [
          if (inQuestion)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ScriptaColors.primaryFaint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 15, color: ScriptaColors.primaryDark),
                      const SizedBox(width: 5),
                      Text('$_score',
                          style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: ScriptaColors.primaryDark)),
                    ],
                  ),
                ),
              ),
            ),
        ],
        bottom: inQuestion
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _questions.length,
                  minHeight: 4,
                  backgroundColor: ScriptaColors.surfaceElevated,
                  valueColor:
                      const AlwaysStoppedAnimation(ScriptaColors.primaryDark),
                ),
              )
            : null,
      ),
      body: SafeArea(child: _body(it)),
    );
  }

  Widget _body(bool it) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: ScriptaColors.primaryDark, strokeWidth: 1.6));
    }
    if (_questions.length < 3) {
      return _Empty(it: it);
    }
    if (_index >= _questions.length) {
      return _Results(
        it: it,
        score: _score,
        total: _questions.length,
        scheduled: _scheduled,
        onRestart: _restart,
        onClose: () => Navigator.of(context).maybePop(),
      );
    }
    final q = _questions[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: _question(it, q),
    );
  }

  Widget _question(bool it, QuizQuestion q) {
    return Column(
      key: ValueKey('q$_index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_label(it, q.kind),
            style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: ScriptaColors.primaryDark)),
        const SizedBox(height: 14),
        _PassageCard(question: q, answered: _answered),
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
                color: ScriptaColors.inkFaint),
          ),
        ],
        const SizedBox(height: 18),
        ...q.options.map((opt) => _optionTile(q, opt)),
        const Spacer(),
        if (_answered) _nextButton(it),
      ],
    );
  }

  Widget _optionTile(QuizQuestion q, String opt) {
    final isCorrect = opt == q.answer;
    final isPicked = opt == _picked;
    Color bg = ScriptaColors.surface;
    Color border = ScriptaColors.rule;
    if (_answered) {
      if (isCorrect) {
        bg = const Color(0xFFE7F0E0);
        border = ScriptaColors.primaryDark;
      } else if (isPicked) {
        bg = const Color(0xFFF6E4E4);
        border = const Color(0xFFB54848);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _answer(q, opt),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(opt,
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ScriptaColors.ink)),
              ),
              if (_answered && isCorrect)
                const Icon(Icons.check_circle,
                    color: ScriptaColors.primaryDark, size: 20),
              if (_answered && isPicked && !isCorrect)
                const Icon(Icons.cancel, color: Color(0xFFB54848), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nextButton(bool it) {
    final label = _index >= _questions.length - 1
        ? (it ? 'Vedi risultato' : 'See result')
        : (it ? 'Avanti' : 'Next');
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _next,
        style: FilledButton.styleFrom(
          backgroundColor: ScriptaColors.primaryDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label,
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
      ),
    );
  }
}

class _PassageCard extends StatelessWidget {
  const _PassageCard({required this.question, required this.answered});
  final QuizQuestion question;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.ebGaramond(
        fontSize: 20, height: 1.5, color: ScriptaColors.ink);

    Widget child;
    // After answering a cloze, fill the blank with the correct word in green.
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
                  fontWeight: FontWeight.w700),
            ),
            if (parts.length > 1) TextSpan(text: parts.sublist(1).join('_____')),
          ],
        ),
      );
    } else {
      child = Text(question.prompt, style: style);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 16,
              offset: const Offset(0, 5)),
        ],
      ),
      child: child,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.it});
  final bool it;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.quiz_outlined, size: 46, color: ScriptaColors.primaryDark),
            const SizedBox(height: 18),
            Text(it ? 'Servono più highlight' : 'Need more highlights',
                textAlign: TextAlign.center,
                style: GoogleFonts.ebGaramond(
                    fontSize: 22, fontWeight: FontWeight.w600, color: ScriptaColors.ink)),
            const SizedBox(height: 10),
            Text(
              it
                  ? 'Importa o evidenzia qualche passaggio in più e torna a metterti alla prova.'
                  : 'Import or highlight a few more passages, then come back to test yourself.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: ScriptaColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.it,
    required this.score,
    required this.total,
    required this.scheduled,
    required this.onRestart,
    required this.onClose,
  });
  final bool it;
  final int score;
  final int total;
  final int scheduled;
  final VoidCallback onRestart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (score * 100 / total).round();
    final String head;
    if (pct >= 80) {
      head = it ? 'Memoria di ferro!' : 'Razor-sharp memory!';
    } else if (pct >= 50) {
      head = it ? 'Niente male!' : 'Not bad!';
    } else {
      head = it ? 'Ottimo allenamento' : 'Good practice';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: const BoxDecoration(
                  color: ScriptaColors.primaryFaint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$score/$total',
                  style: GoogleFonts.ebGaramond(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.primaryDark)),
            ).animate().scaleXY(begin: 0.6, end: 1, duration: 520.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(head,
                style: GoogleFonts.ebGaramond(
                    fontSize: 26, fontWeight: FontWeight.w600, color: ScriptaColors.ink)),
            if (scheduled > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: ScriptaColors.primaryFaint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        size: 16, color: ScriptaColors.primaryDark),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        it
                            ? '$scheduled da ripassare aggiunti al Ripasso'
                            : '$scheduled added to your Ripasso',
                        style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ScriptaColors.primaryDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  backgroundColor: ScriptaColors.primaryDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(it ? 'Nuovo quiz' : 'New quiz',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onClose,
              child: Text(it ? 'Chiudi' : 'Close',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600, color: ScriptaColors.inkMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
