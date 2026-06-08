// ─── Quiz generator (pure Dart, offline, deterministic-with-seed) ────────────
//
// Active recall over the user's own highlights — no AI, no network. Two kinds:
//
//   • cloze     — a passage with one meaningful word blanked out; the reader
//                 recalls it, then self-grades (knew it / missed).
//   • whichBook — a passage shown with 4 book choices; pick the source book.
//
// All generation is local + reproducible when you pass a seeded [Random], so it
// is unit-testable and never "AI slop".

import 'dart:math';

enum QuizKind { cloze, whichBook }

class QuizSource {
  const QuizSource(this.content, this.bookTitle, this.bookAuthor);
  final String content;
  final String? bookTitle;
  final String? bookAuthor;
}

class QuizQuestion {
  const QuizQuestion({
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.options,
    this.bookTitle,
    this.bookAuthor,
  });

  final QuizKind kind;
  /// The passage shown (with a blank for cloze).
  final String prompt;
  /// Correct answer: the blanked word (cloze) or the book title (whichBook).
  final String answer;
  /// Multiple-choice options (whichBook). Empty for cloze.
  final List<String> options;
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
  'avere', 'sempre', 'ancora', 'senza', 'dove', 'loro', 'noi', 'voi',
};

final _wordRe = RegExp(r"[A-Za-zÀ-ÿ']+");

/// Builds up to [count] quiz questions from [sources]. Sources with empty
/// content are skipped. Pass a seeded [rng] for reproducible output.
List<QuizQuestion> generateQuiz(
  List<QuizSource> sources, {
  int count = 8,
  Random? rng,
}) {
  final r = rng ?? Random();
  final pool = sources
      .where((s) => s.content.trim().isNotEmpty)
      .toList();
  if (pool.isEmpty) return const [];

  // Distinct, non-empty book titles for multiple-choice distractors.
  final titles = <String>{
    for (final s in pool)
      if ((s.bookTitle ?? '').trim().isNotEmpty) s.bookTitle!.trim(),
  }.toList();

  final shuffled = [...pool]..shuffle(r);

  final out = <QuizQuestion>[];
  for (final s in shuffled) {
    if (out.length >= count) break;

    // Prefer whichBook when we have enough distinct books AND this source has a
    // title; otherwise fall back to a cloze. Alternate to keep variety.
    final canWhichBook =
        titles.length >= 3 && (s.bookTitle ?? '').trim().isNotEmpty;
    final preferWhichBook = canWhichBook && out.length.isEven;

    QuizQuestion? q;
    if (preferWhichBook) {
      q = _whichBook(s, titles, r) ?? _cloze(s, r);
    } else {
      q = _cloze(s, r) ?? (canWhichBook ? _whichBook(s, titles, r) : null);
    }
    if (q != null) out.add(q);
  }
  return out;
}

QuizQuestion? _cloze(QuizSource s, Random r) {
  final content = s.content.trim();
  final matches = _wordRe.allMatches(content).toList();
  // candidate words: length >= 5, not a stopword
  final candidates = matches.where((m) {
    final w = m.group(0)!;
    return w.length >= 5 && !_stopwords.contains(w.toLowerCase());
  }).toList();
  if (candidates.isEmpty) return null;

  final pick = candidates[r.nextInt(candidates.length)];
  final word = pick.group(0)!;
  final blanked =
      content.substring(0, pick.start) + ' _____ ' + content.substring(pick.end);

  return QuizQuestion(
    kind: QuizKind.cloze,
    prompt: blanked,
    answer: word,
    options: const [],
    bookTitle: s.bookTitle,
    bookAuthor: s.bookAuthor,
  );
}

QuizQuestion? _whichBook(QuizSource s, List<String> allTitles, Random r) {
  final correct = (s.bookTitle ?? '').trim();
  if (correct.isEmpty) return null;
  final others = allTitles.where((t) => t != correct).toList()..shuffle(r);
  final distractors = others.take(3).toList();
  if (distractors.isEmpty) return null; // need at least one alternative

  final options = [correct, ...distractors]..shuffle(r);
  return QuizQuestion(
    kind: QuizKind.whichBook,
    prompt: s.content.trim(),
    answer: correct,
    options: options,
    bookTitle: s.bookTitle,
    bookAuthor: s.bookAuthor,
  );
}
