// ─── Quiz — active recall over your highlights ───────────────────────────────
//
// A short, gamified recall session: 10 questions generated locally from the
// reader's own highlights (cloze fill-in-the-blank + "which book?" multiple
// choice). No AI, no network. Self-graded for cloze; auto-graded for choice.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/highlights_provider.dart';
import '../../core/theme.dart';
import 'quiz_generator.dart';

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
  bool _revealed = false;       // cloze: answer shown
  String? _picked;              // whichBook: chosen option
  bool _answered = false;       // question resolved (moving on enabled)

  bool get _it => Localizations.localeOf(context).languageCode == 'it';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final highlights = await ref.read(allHighlightsProvider.future);
      final filter = widget.bookTitle?.trim().toLowerCase();
      final sources = highlights
          .where((h) => filter == null
              ? true
              : (h.bookTitle ?? '').trim().toLowerCase() == filter)
          .map((h) => QuizSource(h.content, h.bookTitle, h.bookAuthor))
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
      _revealed = false;
      _picked = null;
      _answered = false;
      _loading = true;
    });
    _load();
  }

  void _next() {
    if (_index >= _questions.length - 1) {
      setState(() => _index = _questions.length); // → results
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _picked = null;
      _answered = false;
    });
  }

  void _answerWhichBook(QuizQuestion q, String option) {
    if (_answered) return;
    HapticFeedback.selectionClick();
    setState(() {
      _picked = option;
      _answered = true;
      if (option == q.answer) _score++;
    });
  }

  void _gradeCloze(bool knew) {
    if (_answered) return;
    HapticFeedback.selectionClick();
    setState(() {
      _answered = true;
      if (knew) _score++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final it = _it;
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: MarginaliaColors.ink,
        title: Text(widget.appBarTitle ?? 'Quiz',
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 18, color: MarginaliaColors.ink)),
        bottom: (!_loading && _questions.isNotEmpty && _index < _questions.length)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: (_index + 1) / _questions.length,
                  minHeight: 4,
                  backgroundColor: MarginaliaColors.surfaceElevated,
                  valueColor: const AlwaysStoppedAnimation(MarginaliaColors.primaryDark),
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
              color: MarginaliaColors.primaryDark, strokeWidth: 1.6));
    }
    if (_questions.length < 3) {
      return _Empty(it: it);
    }
    if (_index >= _questions.length) {
      return _Results(
        it: it,
        score: _score,
        total: _questions.length,
        onRestart: _restart,
        onClose: () => Navigator.of(context).maybePop(),
      );
    }
    final q = _questions[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: q.kind == QuizKind.whichBook ? _whichBook(it, q) : _cloze(it, q),
    );
  }

  // ── which-book multiple choice ─────────────────────────────────────────────
  Widget _whichBook(bool it, QuizQuestion q) {
    return Column(
      key: ValueKey('wb$_index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(it ? 'Da quale libro?' : 'Which book?',
            style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: MarginaliaColors.primaryDark)),
        const SizedBox(height: 14),
        _PassageCard(text: q.prompt),
        const SizedBox(height: 20),
        ...q.options.map((opt) {
          final isCorrect = opt == q.answer;
          final isPicked = opt == _picked;
          Color bg = MarginaliaColors.surface;
          Color border = MarginaliaColors.rule;
          if (_answered) {
            if (isCorrect) {
              bg = const Color(0xFFE7F0E0);
              border = MarginaliaColors.primaryDark;
            } else if (isPicked) {
              bg = const Color(0xFFF6E4E4);
              border = const Color(0xFFB54848);
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _answerWhichBook(q, opt),
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
                              color: MarginaliaColors.ink)),
                    ),
                    if (_answered && isCorrect)
                      const Icon(Icons.check_circle, color: MarginaliaColors.primaryDark, size: 20),
                    if (_answered && isPicked && !isCorrect)
                      const Icon(Icons.cancel, color: Color(0xFFB54848), size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        if (_answered) _nextButton(it),
      ],
    );
  }

  // ── cloze (fill in the blank, self-graded) ─────────────────────────────────
  Widget _cloze(bool it, QuizQuestion q) {
    return Column(
      key: ValueKey('cz$_index'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(it ? 'Completa il passaggio' : 'Complete the passage',
            style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: MarginaliaColors.primaryDark)),
        const SizedBox(height: 14),
        _PassageCard(text: q.prompt),
        const SizedBox(height: 18),
        if (_revealed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(it ? 'La parola era' : 'The word was',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, color: MarginaliaColors.inkMuted)),
                const SizedBox(height: 6),
                Text(q.answer,
                    style: GoogleFonts.ebGaramond(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.primaryDark)),
              ],
            ),
          ).animate().fadeIn(duration: 220.ms).scaleXY(begin: 0.96, end: 1),
        if (q.bookTitle != null && (q.bookTitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            [q.bookTitle, q.bookAuthor].where((s) => (s ?? '').trim().isNotEmpty).join(' · '),
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.inkFaint),
          ),
        ],
        const Spacer(),
        if (!_revealed)
          _bigButton(
            label: it ? 'Rivela risposta' : 'Reveal answer',
            filled: false,
            onTap: () => setState(() => _revealed = true),
          )
        else if (!_answered)
          Row(
            children: [
              Expanded(
                child: _bigButton(
                  label: it ? 'No' : 'Missed',
                  filled: false,
                  danger: true,
                  onTap: () => _gradeCloze(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _bigButton(
                  label: it ? 'La sapevo' : 'I knew it',
                  filled: true,
                  onTap: () => _gradeCloze(true),
                ),
              ),
            ],
          )
        else
          _nextButton(it),
      ],
    );
  }

  Widget _nextButton(bool it) => _bigButton(
        label: _index >= _questions.length - 1
            ? (it ? 'Vedi risultato' : 'See result')
            : (it ? 'Avanti' : 'Next'),
        filled: true,
        onTap: _next,
      );

  Widget _bigButton({
    required String label,
    required bool filled,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final color = danger ? const Color(0xFFB54848) : MarginaliaColors.primaryDark;
    return SizedBox(
      height: 52,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(label,
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(label,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
    );
  }
}

class _PassageCard extends StatelessWidget {
  const _PassageCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 16, offset: const Offset(0, 5)),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.ebGaramond(fontSize: 20, height: 1.5, color: MarginaliaColors.ink),
      ),
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
            const Icon(Icons.quiz_outlined, size: 46, color: MarginaliaColors.primaryDark),
            const SizedBox(height: 18),
            Text(it ? 'Servono più highlight' : 'Need more highlights',
                textAlign: TextAlign.center,
                style: GoogleFonts.ebGaramond(
                    fontSize: 22, fontWeight: FontWeight.w600, color: MarginaliaColors.ink)),
            const SizedBox(height: 10),
            Text(
              it
                  ? 'Importa o evidenzia qualche passaggio in più e torna a metterti alla prova.'
                  : 'Import or highlight a few more passages, then come back to test yourself.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, height: 1.5, color: MarginaliaColors.inkMuted),
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
    required this.onRestart,
    required this.onClose,
  });
  final bool it;
  final int score;
  final int total;
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
                  color: MarginaliaColors.primaryFaint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$score/$total',
                  style: GoogleFonts.ebGaramond(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.primaryDark)),
            ).animate().scaleXY(begin: 0.6, end: 1, duration: 520.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(head,
                style: GoogleFonts.ebGaramond(
                    fontSize: 26, fontWeight: FontWeight.w600, color: MarginaliaColors.ink)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  backgroundColor: MarginaliaColors.primaryDark,
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
                      fontWeight: FontWeight.w600, color: MarginaliaColors.inkMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
