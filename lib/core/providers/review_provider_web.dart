import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/highlight_web.dart';
import '../models/review_state_web.dart';
import '../review/sm2.dart';

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

final reviewStateProvider =
    FutureProvider<ReviewState>((ref) async => ReviewState());

final reviewedDaysProvider =
    FutureProvider<Set<DateTime>>((ref) async => <DateTime>{});

class ReviewSessionState {
  const ReviewSessionState({
    required this.deck,
    required this.index,
    required this.streakIncremented,
  });

  final List<Highlight> deck;
  final int index;
  final bool streakIncremented;

  bool get isFinished => index >= deck.length;
  int get total => deck.length;
  int get reviewed => index;
  Highlight? get current => isFinished ? null : deck[index];

  ReviewSessionState copyWith({
    List<Highlight>? deck,
    int? index,
    bool? streakIncremented,
  }) =>
      ReviewSessionState(
        deck: deck ?? this.deck,
        index: index ?? this.index,
        streakIncremented: streakIncremented ?? this.streakIncremented,
      );
}

class ReviewSessionController
    extends AutoDisposeNotifier<ReviewSessionState> {
  @override
  ReviewSessionState build() => const ReviewSessionState(
        deck: [],
        index: 0,
        streakIncremented: false,
      );

  Future<void> load() async {}

  Future<void> grade(ReviewGrade grade) async {
    state = state.copyWith(index: state.index + 1);
  }
}

final reviewSessionControllerProvider = AutoDisposeNotifierProvider<
    ReviewSessionController, ReviewSessionState>(ReviewSessionController.new);
