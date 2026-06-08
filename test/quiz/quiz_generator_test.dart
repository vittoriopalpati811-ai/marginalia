import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginalia/features/quiz/quiz_generator.dart';

void main() {
  group('generateQuiz', () {
    test('empty input yields no questions', () {
      expect(generateQuiz(const []), isEmpty);
      expect(generateQuiz([const QuizSource('   ', 'B', 'A')]), isEmpty);
    });

    test('cloze is multiple-choice: blank + options that include the answer', () {
      final qs = generateQuiz(
        [
          const QuizSource(
              'The unexamined life is not worth living', 'Apology', 'Plato'),
          const QuizSource(
              'Knowledge begins through wonder and patient questioning',
              'Apology',
              'Plato'),
        ],
        rng: Random(1),
      );
      expect(qs, isNotEmpty);
      final q = qs.firstWhere((x) => x.kind == QuizKind.cloze);
      expect(q.prompt, contains('_____'));
      expect(q.answer.length, greaterThanOrEqualTo(5));
      expect(q.prompt.contains(q.answer), isFalse);
      // now answerable: options include the right word + at least one distractor
      expect(q.options, contains(q.answer));
      expect(q.options.length, inInclusiveRange(2, 4));
      expect(q.options.toSet().length, q.options.length);
      expect(q.clozeWord, q.answer);
    });

    test('whichAuthor offers the correct author among the options', () {
      final sources = [
        const QuizSource('Passage one about the sea', 'Book One', 'Author Alpha'),
        const QuizSource('Passage two about the sky', 'Book Two', 'Author Beta'),
        const QuizSource('Passage three about the sun', 'Book Three', 'Author Gamma'),
        const QuizSource('Passage four about the moon', 'Book Four', 'Author Delta'),
      ];
      final qs = generateQuiz(sources, count: 9, rng: Random(5));
      final wa = qs.where((q) => q.kind == QuizKind.whichAuthor).toList();
      expect(wa, isNotEmpty);
      for (final q in wa) {
        expect(q.options, contains(q.answer));
        expect(q.options.length, inInclusiveRange(2, 4));
        expect(q.options.toSet().length, q.options.length);
      }
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
