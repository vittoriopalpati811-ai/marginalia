import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/features/quiz/quiz_generator.dart';

void main() {
  group('generateQuiz', () {
    test('empty input yields no questions', () {
      expect(generateQuiz(const []), isEmpty);
      expect(generateQuiz([const QuizSource('   ', 'B', 'A')]), isEmpty);
    });

    test('cloze blanks a meaningful word that is the answer', () {
      final qs = generateQuiz(
        [const QuizSource('The unexamined life is not worth living', 'Apology', 'Plato')],
        rng: Random(1),
      );
      expect(qs, hasLength(1));
      final q = qs.first;
      // only one book → must be a cloze (no distractors for whichBook)
      expect(q.kind, QuizKind.cloze);
      expect(q.prompt, contains('_____'));
      expect(q.answer.length, greaterThanOrEqualTo(5));
      // the answer word is removed from the prompt
      expect(q.prompt.contains(q.answer), isFalse);
    });

    test('whichBook offers the correct title among the options', () {
      final sources = [
        const QuizSource('Passage from book one here', 'Book One', 'A1'),
        const QuizSource('Passage from book two here', 'Book Two', 'A2'),
        const QuizSource('Passage from book three here', 'Book Three', 'A3'),
        const QuizSource('Passage from book four here', 'Book Four', 'A4'),
      ];
      final qs = generateQuiz(sources, count: 8, rng: Random(7));
      expect(qs, isNotEmpty);
      final wb = qs.where((q) => q.kind == QuizKind.whichBook).toList();
      expect(wb, isNotEmpty);
      for (final q in wb) {
        expect(q.options, contains(q.answer));
        expect(q.options.length, inInclusiveRange(2, 4));
        expect(q.options.toSet().length, q.options.length); // no dup options
      }
    });

    test('respects the count cap', () {
      final sources = List.generate(
        30,
        (i) => QuizSource('Meaningful passage number $i about wisdom', 'Book $i', 'Auth'),
      );
      final qs = generateQuiz(sources, count: 6, rng: Random(3));
      expect(qs.length, lessThanOrEqualTo(6));
    });

    test('seeded output is reproducible', () {
      final sources = List.generate(
        12,
        (i) => QuizSource('Another thoughtful passage $i remember this', 'Title $i', 'Auth'),
      );
      final a = generateQuiz(sources, rng: Random(99)).map((q) => q.prompt).toList();
      final b = generateQuiz(sources, rng: Random(99)).map((q) => q.prompt).toList();
      expect(a, equals(b));
    });
  });
}
