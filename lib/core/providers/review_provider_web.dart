import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight_web.dart';
import '../models/review_state_web.dart';
import '../review/sm2.dart';
import '../../features/quiz/quiz_generator.dart';

// ─── Ripasso providers — web stub ────────────────────────────────────────────
//
// The spaced-repetition loop is offline-first and backed by Isar, which doesn't
// run on web (the founder's Chrome dev target). These stubs keep the shared UI
// (Library entry card, Profile streak, review screen) compiling on web by
// exposing the same provider surface with empty/no-op behaviour.

const int kDailyNewCardCap = 20;

final dueHighlightsProvider =
    FutureProvider.autoDispose<List<Highlight>>((ref) async => []);

final dueCountProvider = FutureProvider.autoDispose<int>((ref) async => 0);

/// Web no-op: the Ripasso 2.0 quiz corpus is native-only (Isar). Empty here.
final reviewQuizCorpusProvider =
    FutureProvider.autoDispose<List<QuizSource>>((ref) async => const []);

final reviewStateProvider =
    FutureProvider<ReviewState>((ref) async => ReviewState());

/// Web no-op: Ripasso (Isar) doesn't run on web, so the Quiz → review link does
/// nothing here. Keeps the shared Quiz screen compiling on the Chrome target.
Future<int> markHighlightsDueForReview(WidgetRef ref, Set<int> ids) async => 0;

final reviewedDaysProvider =
    FutureProvider<Set<DateTime>>((ref) async => <DateTime>{});

class ReviewSessionState {
  const ReviewSessionState({
    required this.deck,
    required this.questions,
    required this.index,
    required this.streakIncremented,
    this.score = 0,
    this.startedAt,
    this.forgotCount = 0,
    this.hardCount = 0,
    this.goodCount = 0,
  });

  final List<Highlight> deck;

  /// One question per deck card — mirrors the native Ripasso 2.0 state so the
  /// shared review UI compiles on web (always empty here: the loop is a no-op).
  final List<QuizQuestion?> questions;
  final int index;
  final bool streakIncremented;

  /// Quiz score / session start — mirror the native state (no-op values on web).
  final int score;
  final DateTime? startedAt;

  /// Per-grade tallies — mirror the native state so the shared recap UI
  /// compiles on web (always 0 here: the loop is a no-op without Isar).
  final int forgotCount;
  final int hardCount;
  final int goodCount;

  bool get isFinished => index >= deck.length;
  int get total => deck.length;
  int get reviewed => index;
  int get questionsTotal => questions.where((q) => q != null).length;
  Highlight? get current => isFinished ? null : deck[index];

  QuizQuestion? get currentQuestion =>
      (isFinished || index >= questions.length) ? null : questions[index];

  ReviewSessionState copyWith({
    List<Highlight>? deck,
    List<QuizQuestion?>? questions,
    int? index,
    bool? streakIncremented,
    int? score,
    DateTime? startedAt,
    int? forgotCount,
    int? hardCount,
    int? goodCount,
  }) =>
      ReviewSessionState(
        deck: deck ?? this.deck,
        questions: questions ?? this.questions,
        index: index ?? this.index,
        streakIncremented: streakIncremented ?? this.streakIncremented,
        score: score ?? this.score,
        startedAt: startedAt ?? this.startedAt,
        forgotCount: forgotCount ?? this.forgotCount,
        hardCount: hardCount ?? this.hardCount,
        goodCount: goodCount ?? this.goodCount,
      );
}

class ReviewSessionController
    extends AutoDisposeNotifier<ReviewSessionState> {
  @override
  ReviewSessionState build() => const ReviewSessionState(
        deck: [],
        questions: [],
        index: 0,
        streakIncremented: false,
      );

  Future<void> load() async {}

  /// Web no-op mirror of the native quiz-answer entry point.
  Future<void> answer({required bool correct, bool counts = true}) async {
    state = state.copyWith(
      index: state.index + 1,
      score: state.score + (counts && correct ? 1 : 0),
    );
  }

  Future<void> grade(ReviewGrade grade) async {
    state = state.copyWith(index: state.index + 1);
  }
}

final reviewSessionControllerProvider = AutoDisposeNotifierProvider<
    ReviewSessionController, ReviewSessionState>(ReviewSessionController.new);
