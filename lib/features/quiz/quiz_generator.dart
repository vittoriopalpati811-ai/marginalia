// ─── Quiz generator (pure Dart, offline, deterministic-with-seed) ────────────
//
// Active recall over the user's own highlights — no AI, no network. Every
// question is ANSWERABLE by tapping one of up to four options:
//
//   • cloze       — a passage with one meaningful word blanked; pick the word.
//   • whichBook   — a passage; pick the source book.
//   • whichAuthor — a passage; pick the author.
//
// All generation is local + reproducible when you pass a seeded [Random], so it
// is unit-testable and never "AI slop".

import 'dart:math';

enum QuizKind { cloze, whichBook, whichAuthor }

class QuizSource {
  const QuizSource(this.content, this.bookTitle, this.bookAuthor,
      {this.highlightId});
  final String content;
  final String? bookTitle;
  final String? bookAuthor;

  /// Local Isar id of the source highlight (native). Lets the screen schedule a
  /// missed passage for Ripasso. Null on web / when unknown.
  final int? highlightId;
}

class QuizQuestion {
  const QuizQuestion({
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.options,
    this.clozeWord,
    this.bookTitle,
    this.bookAuthor,
    this.highlightId,
  });

  final QuizKind kind;

  /// Local Isar id of the source highlight (for the Ripasso link). May be null.
  final int? highlightId;

  /// The passage shown (with a blank for cloze).
  final String prompt;

  /// Correct answer: the blanked word (cloze), the book title (whichBook) or
  /// the author (whichAuthor). Always one of [options].
  final String answer;

  /// Multiple-choice options (2–4). Always non-empty now — every kind is tap-to-
  /// answer.
  final List<String> options;

  /// For cloze: the original word, so the UI can fill the blank back in.
  final String? clozeWord;

  final String? bookTitle;
  final String? bookAuthor;
}

// Common words we never blank in a cloze (would be guessable / not meaningful).
const _stopwords = <String>{
  // English
  'the', 'and', 'that', 'this', 'with', 'from', 'have', 'were', 'what', 'when',
  'your', 'their', 'they', 'there', 'which', 'would', 'could', 'should', 'about',
  'because', 'into', 'than', 'them', 'then', 'these', 'those', 'been', 'being',
  'will', 'shall', 'must', 'each', 'every', 'some', 'such', 'only', 'more', 'most',
  // Italian
  'che', 'non', 'per', 'come', 'sono', 'questo', 'questa', 'quello', 'quella',
  'della', 'dello', 'degli', 'delle', 'nella', 'nello', 'negli', 'nelle', 'anche',
  'quando', 'perche', 'perché', 'piu', 'più', 'molto', 'tutto', 'tutti', 'essere',
  'avere', 'sempre', 'ancora', 'senza', 'dove', 'loro', 'noi', 'voi', 'gli',
};

final _wordRe = RegExp(r"[A-Za-zÀ-ÿ']+");

bool _isMeaningfulWord(String w) =>
    w.length >= 5 && !_stopwords.contains(w.toLowerCase());

/// Builds up to [count] quiz questions from [sources]. Sources with empty
/// content are skipped. Pass a seeded [rng] for reproducible output.
List<QuizQuestion> generateQuiz(
  List<QuizSource> sources, {
  int count = 8,
  Random? rng,
}) {
  final r = rng ?? Random();
  final pool = sources.where((s) => s.content.trim().isNotEmpty).toList();
  if (pool.isEmpty) return const [];

  final titles = <String>{
    for (final s in pool)
      if ((s.bookTitle ?? '').trim().isNotEmpty) s.bookTitle!.trim(),
  }.toList();
  final authors = <String>{
    for (final s in pool)
      if ((s.bookAuthor ?? '').trim().isNotEmpty) s.bookAuthor!.trim(),
  }.toList();

  // Distinct meaningful words across the whole corpus — cloze distractors.
  final wordPool = <String>{};
  for (final s in pool) {
    for (final m in _wordRe.allMatches(s.content)) {
      final w = m.group(0)!;
      if (_isMeaningfulWord(w)) wordPool.add(w);
    }
  }
  final words = wordPool.toList();

  final shuffled = [...pool]..shuffle(r);

  final canWhichBook = titles.length >= 3;
  final canWhichAuthor = authors.length >= 3;

  final out = <QuizQuestion>[];
  for (final s in shuffled) {
    if (out.length >= count) break;

    // Rotate kinds for variety, falling back to whatever is available.
    final slot = out.length % 3;
    final attempts = <QuizQuestion? Function()>[];
    if (slot == 0) {
      attempts.add(() => _cloze(s, words, r));
      if (canWhichBook) attempts.add(() => _whichBook(s, titles, r));
      if (canWhichAuthor) attempts.add(() => _whichAuthor(s, authors, r));
    } else if (slot == 1 && canWhichBook) {
      attempts.add(() => _whichBook(s, titles, r));
      attempts.add(() => _cloze(s, words, r));
      if (canWhichAuthor) attempts.add(() => _whichAuthor(s, authors, r));
    } else if (slot == 2 && canWhichAuthor) {
      attempts.add(() => _whichAuthor(s, authors, r));
      attempts.add(() => _cloze(s, words, r));
      if (canWhichBook) attempts.add(() => _whichBook(s, titles, r));
    } else {
      attempts.add(() => _cloze(s, words, r));
      if (canWhichBook) attempts.add(() => _whichBook(s, titles, r));
      if (canWhichAuthor) attempts.add(() => _whichAuthor(s, authors, r));
    }

    for (final make in attempts) {
      final q = make();
      if (q != null) {
        out.add(q);
        break;
      }
    }
  }
  return out;
}

/// Builds ONE question from a single [target] highlight, drawing distractors
/// from [corpus] (the user's other highlights/books). Used by Ripasso 2.0, where
/// every due card becomes a tap-to-answer question instead of a self-graded card.
///
/// Tries the three kinds in a rotation seeded by the target's id (so the same
/// card tends to ask the same kind of question across sessions, but the corpus
/// still varies the distractors), falling back to whatever the content + corpus
/// can actually support. Returns null only when the target has no answerable
/// question at all (e.g. a one-word highlight with an empty corpus) — the caller
/// then skips straight to grading that card.
QuizQuestion? generateQuestionForHighlight(
  QuizSource target,
  List<QuizSource> corpus, {
  Random? rng,
}) {
  final r = rng ?? Random();
  if (target.content.trim().isEmpty) return null;

  // The corpus always includes the target, so its words/titles/authors are part
  // of the pools. Sources with empty content are skipped.
  final pool = corpus.where((s) => s.content.trim().isNotEmpty).toList();
  if (pool.every((s) => s.highlightId != target.highlightId &&
      s.content != target.content)) {
    pool.add(target);
  }

  final titles = <String>{
    for (final s in pool)
      if ((s.bookTitle ?? '').trim().isNotEmpty) s.bookTitle!.trim(),
  }.toList();
  final authors = <String>{
    for (final s in pool)
      if ((s.bookAuthor ?? '').trim().isNotEmpty) s.bookAuthor!.trim(),
  }.toList();

  final wordPool = <String>{};
  for (final s in pool) {
    for (final m in _wordRe.allMatches(s.content)) {
      final w = m.group(0)!;
      if (_isMeaningfulWord(w)) wordPool.add(w);
    }
  }
  final words = wordPool.toList();

  final canWhichBook = titles.length >= 3;
  final canWhichAuthor = authors.length >= 3;

  // Stable per-card rotation: cloze → which-book → which-author, then fall back
  // to any other kind that can be built from this card + corpus.
  final slot = (target.highlightId ?? target.content.hashCode).abs() % 3;
  final attempts = <QuizQuestion? Function()>[];
  void addCloze() => attempts.add(() => _cloze(target, words, r));
  void addBook() {
    if (canWhichBook) attempts.add(() => _whichBook(target, titles, r));
  }
  void addAuthor() {
    if (canWhichAuthor) attempts.add(() => _whichAuthor(target, authors, r));
  }

  if (slot == 0) {
    addCloze();
    addBook();
    addAuthor();
  } else if (slot == 1) {
    addBook();
    addCloze();
    addAuthor();
  } else {
    addAuthor();
    addCloze();
    addBook();
  }

  for (final make in attempts) {
    final q = make();
    if (q != null) return q;
  }
  return null;
}

QuizQuestion? _cloze(QuizSource s, List<String> wordPool, Random r) {
  final content = s.content.trim();
  final matches = _wordRe.allMatches(content).toList();
  final candidates = matches.where((m) => _isMeaningfulWord(m.group(0)!)).toList();
  if (candidates.isEmpty) return null;

  final pick = candidates[r.nextInt(candidates.length)];
  final word = pick.group(0)!;
  final lowerAns = word.toLowerCase();
  final blanked =
      content.substring(0, pick.start) + ' _____ ' + content.substring(pick.end);

  // Distractor words: prefer ones close in length, drawn from the corpus.
  final others = wordPool.where((w) => w.toLowerCase() != lowerAns).toList()
    ..sort((a, b) =>
        (a.length - word.length).abs().compareTo((b.length - word.length).abs()));
  final near = others.take(14).toList()..shuffle(r);
  final distractors = <String>[];
  final usedLower = <String>{lowerAns};
  for (final w in near) {
    if (usedLower.add(w.toLowerCase())) distractors.add(w);
    if (distractors.length >= 3) break;
  }
  if (distractors.isEmpty) return null; // need at least one alternative

  final options = [word, ...distractors]..shuffle(r);
  return QuizQuestion(
    kind: QuizKind.cloze,
    prompt: blanked,
    answer: word,
    options: options,
    clozeWord: word,
    bookTitle: s.bookTitle,
    bookAuthor: s.bookAuthor,
    highlightId: s.highlightId,
  );
}

QuizQuestion? _whichBook(QuizSource s, List<String> allTitles, Random r) {
  final correct = (s.bookTitle ?? '').trim();
  if (correct.isEmpty) return null;
  final others = allTitles.where((t) => t != correct).toList()..shuffle(r);
  final distractors = others.take(3).toList();
  if (distractors.isEmpty) return null;

  final options = [correct, ...distractors]..shuffle(r);
  return QuizQuestion(
    kind: QuizKind.whichBook,
    prompt: s.content.trim(),
    answer: correct,
    options: options,
    bookTitle: s.bookTitle,
    bookAuthor: s.bookAuthor,
    highlightId: s.highlightId,
  );
}

QuizQuestion? _whichAuthor(QuizSource s, List<String> allAuthors, Random r) {
  final correct = (s.bookAuthor ?? '').trim();
  if (correct.isEmpty) return null;
  final others = allAuthors.where((a) => a != correct).toList()..shuffle(r);
  final distractors = others.take(3).toList();
  if (distractors.isEmpty) return null;

  final options = [correct, ...distractors]..shuffle(r);
  return QuizQuestion(
    kind: QuizKind.whichAuthor,
    prompt: s.content.trim(),
    answer: correct,
    options: options,
    bookTitle: s.bookTitle,
    bookAuthor: s.bookAuthor,
    highlightId: s.highlightId,
  );
}
