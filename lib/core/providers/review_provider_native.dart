import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../models/highlight_native.dart';
import '../models/review_state_native.dart';
import '../models/daily_activity_native.dart';
import '../review/sm2.dart';
import '../services/local_notif_service.dart';
import 'isar_provider_native.dart';
import 'auth_provider.dart';
import '../../features/quiz/quiz_generator.dart';
import '../../features/quiz/quiz_lock.dart'
    show
        markRipassoCompletedNow,
        ripassoLockProvider,
        saveRipassoResults,
        ripassoResultsProvider;

// ─── Ripasso (spaced-repetition) providers — native / offline-first ──────────
//
// The whole recall loop runs against Isar with zero network: due highlights are
// found with an indexed query on `reviewDueAt`, grading writes the new SM-2
// schedule back in a writeTxn, and the streak lives in a tiny ReviewState
// singleton. Supabase is touched only as a best-effort mirror after a finished
// session (see ReviewSessionController._applyStreak).

/// How many never-scheduled ("new") highlights we are willing to introduce in a
/// single day, so a freshly-imported 1000-highlight library doesn't dump 1000
/// cards on the user. Genuinely-due (already-scheduled) cards are never capped.
const int kDailyNewCardCap = 20;

/// Hard cap on cards shown in ONE review session — the founder's "max 10 slide
/// nei ripassi". Even if more are genuinely due, a session never exceeds this,
/// keeping the daily ritual short and finishable; the rest roll to tomorrow.
const int kMaxSessionCards = 10;

/// Local midnight of the day [now] falls in (date-only).
DateTime _dateOnly(DateTime now) => DateTime(now.year, now.month, now.day);

/// The exclusive upper bound for "due today": the start of tomorrow. Anything
/// with `reviewDueAt < endOfToday` (or null) is due.
DateTime _endOfToday(DateTime now) => _dateOnly(now).add(const Duration(days: 1));

/// The deck for today's session: already-due cards first, then up to
/// [kDailyNewCardCap] never-scheduled cards. Books are eagerly loaded so the
/// cards can show title/author. autoDispose — it is only alive while the user is
/// on the Library entry card or the review screen.
final dueHighlightsProvider =
    FutureProvider.autoDispose<List<Highlight>>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return [];

  final endOfToday = _endOfToday(DateTime.now());

  // Already-scheduled cards whose due date has arrived (oldest-due first).
  final due = await isar.highlights
      .filter()
      .userIdEqualTo(userId)
      .reviewDueAtIsNotNull()
      .reviewDueAtLessThan(endOfToday)
      .sortByReviewDueAt()
      .findAll();

  // Brand-new cards (never scheduled). Capped so a large import is paced.
  final fresh = await isar.highlights
      .filter()
      .userIdEqualTo(userId)
      .reviewDueAtIsNull()
      .limit(kDailyNewCardCap)
      .findAll();

  // Cap the whole session at [kMaxSessionCards] — due cards first, then new
  // ones fill any remaining slots. Anything beyond rolls to a future session.
  final deck = [...due, ...fresh].take(kMaxSessionCards).toList();
  await Future.wait(deck.map((h) => h.book.load()));
  return deck;
});

/// Cheap count of cards due today — drives the Library hero card subtitle and
/// the dynamic notification body. Counts genuinely-due cards plus up to
/// [kDailyNewCardCap] new ones, matching the deck the user will actually see.
final dueCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return 0;

  final endOfToday = _endOfToday(DateTime.now());

  final due = await isar.highlights
      .filter()
      .userIdEqualTo(userId)
      .reviewDueAtIsNotNull()
      .reviewDueAtLessThan(endOfToday)
      .count();

  final freshTotal = await isar.highlights
      .filter()
      .userIdEqualTo(userId)
      .reviewDueAtIsNull()
      .count();

  final total =
      due + (freshTotal > kDailyNewCardCap ? kDailyNewCardCap : freshTotal);
  // Mirror the session cap so the entry card never promises more than a session
  // will actually show.
  return total > kMaxSessionCards ? kMaxSessionCards : total;
});

/// The distractor corpus for Ripasso 2.0 questions: ALL of the user's highlights
/// (with their book title/author eagerly loaded), turned into [QuizSource]s. The
/// session generates one multiple-choice question per due card, drawing wrong
/// options (cloze words, other book titles/authors) from this pool — so the quiz
/// is built entirely from the reader's own library, offline. autoDispose: it is
/// only needed while a session is being built.
final reviewQuizCorpusProvider =
    FutureProvider.autoDispose<List<QuizSource>>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return const [];

  final all =
      await isar.highlights.filter().userIdEqualTo(userId).findAll();
  await Future.wait(all.map((h) => h.book.load()));
  return [
    for (final h in all)
      if (h.content.trim().isNotEmpty)
        QuizSource(h.content, h.bookTitle, h.bookAuthor, highlightId: h.id),
  ];
});

/// Pulls the given highlights FORWARD into the Ripasso queue (sets reviewDueAt to
/// now) — used by the Quiz to schedule the passages you got WRONG for spaced
/// review, so the quiz strengthens exactly what you forgot. Only ever moves a
/// card earlier, never later. Best-effort: never throws into the UI. Returns the
/// number of highlights actually pulled forward.
Future<int> markHighlightsDueForReview(WidgetRef ref, Set<int> ids) async {
  if (ids.isEmpty) return 0;
  var moved = 0;
  try {
    final isar = ref.read(isarProvider);
    final now = DateTime.now();
    await isar.writeTxn(() async {
      for (final id in ids) {
        final h = await isar.highlights.get(id);
        if (h == null) continue;
        if (h.reviewDueAt == null || h.reviewDueAt!.isAfter(now)) {
          h.reviewDueAt = now;
          await isar.highlights.put(h);
          moved++;
        }
      }
    });
    ref.invalidate(dueCountProvider);
    ref.invalidate(dueHighlightsProvider);
  } catch (e) {
    debugPrint('[quiz] markHighlightsDueForReview failed: $e');
  }
  return moved;
}

/// Reads (creating if absent) the per-user [ReviewState] singleton. Not
/// autoDispose: the streak should stay stable across navigation within a
/// session. Invalidated by the session controller after a streak update.
final reviewStateProvider = FutureProvider<ReviewState>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id ?? 'local';

  final existing =
      await isar.reviewStates.filter().userIdEqualTo(userId).findFirst();
  // Return the persisted row, or a transient default. We deliberately DO NOT
  // create/persist the singleton here: the ONLY Isar writer for ReviewState is
  // the review session's grade() write transaction. Keeping this provider
  // strictly read-only means it can be recomputed at any time (including while
  // a grade transaction is committing) without ever opening a nested
  // transaction — Isar forbids transaction nesting.
  return existing ?? (ReviewState()..userId = userId);
});

/// The set of local days (date-only midnight) on which the user reviewed at
/// least one card, read from the [DailyActivity] log. Drives the upcoming
/// profile review-heatmap. Invalidated by the session controller after a
/// completed session writes its activity row.
final reviewedDaysProvider = FutureProvider<Set<DateTime>>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id ?? 'local';

  final rows = await isar.dailyActivitys
      .filter()
      .userIdEqualTo(userId)
      .reviewedCountGreaterThan(0)
      .findAll();

  return rows.map((r) => _dateOnly(r.day)).toSet();
});

// ─── Session controller ──────────────────────────────────────────────────────

/// Immutable snapshot of an in-progress review session.
///
/// Ripasso 2.0: the daily session is a multiple-choice quiz built from the due
/// cards. [questions] holds ONE [QuizQuestion] per deck card (same order). A
/// correct tap grades the card [ReviewGrade.good], a wrong tap grades it
/// [ReviewGrade.forgot] — so SM-2 keeps scheduling and tomorrow's deck stays
/// fresh. [score] counts correct answers; [startedAt] is set on the first
/// answer so the recap can show elapsed time.
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

  /// The cards for this session, in order. Stable for the session's lifetime.
  final List<Highlight> deck;

  /// One generated question per deck card (same index). A null entry means no
  /// answerable question could be built for that card — it is graded as a
  /// "good" recall automatically so the deck never stalls.
  final List<QuizQuestion?> questions;

  /// Index of the current card. When `index >= deck.length` the session is
  /// finished and the review screen shows the recap.
  final int index;

  /// True once the just-finished session pushed the streak to a new day — lets
  /// the finished state play the one-time flame bounce / "+1".
  final bool streakIncremented;

  /// Correct answers so far (Ripasso 2.0 quiz score).
  final int score;

  /// When the first question was answered — anchors the session duration.
  final DateTime? startedAt;

  /// Per-grade tallies for this session — feed the end-of-session recap and the
  /// backward-compatible entry-card line. With the quiz, wrong → forgot,
  /// correct → good (hard is unused but kept for the persisted shape).
  final int forgotCount;
  final int hardCount;
  final int goodCount;

  bool get isFinished => index >= deck.length;
  int get total => deck.length;
  int get reviewed => index;

  /// The quiz denominator: how many cards actually produced an answerable
  /// question. Cards with no question are recalls, not scored questions, so
  /// counting them would inflate the score/accuracy.
  int get questionsTotal => questions.where((q) => q != null).length;

  Highlight? get current => isFinished ? null : deck[index];

  /// The question for the current card, or null if none could be built.
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

/// Drives the deck on the review screen. Holds the in-memory queue + index,
/// applies SM-2 on each grade (offline, in a writeTxn), and updates the streak
/// once the session has at least one graded card.
class ReviewSessionController
    extends AutoDisposeNotifier<ReviewSessionState> {
  @override
  ReviewSessionState build() => const ReviewSessionState(
        deck: [],
        questions: [],
        index: 0,
        streakIncremented: false,
      );

  /// Loads the deck for today AND generates one multiple-choice question per due
  /// card from the user's own library (Ripasso 2.0). Called once when the review
  /// screen mounts. Questions are built up-front so the swipe between cards is
  /// instant; a card with no answerable question gets a null slot and is graded
  /// automatically as a recall when reached.
  Future<void> load() async {
    final deck = await ref.read(dueHighlightsProvider.future);
    final corpus = await ref.read(reviewQuizCorpusProvider.future);
    final rng = Random();
    final questions = <QuizQuestion?>[
      for (final h in deck)
        generateQuestionForHighlight(
          QuizSource(h.content, h.bookTitle, h.bookAuthor, highlightId: h.id),
          corpus,
          rng: rng,
        ),
    ];
    state = ReviewSessionState(
      deck: deck,
      questions: questions,
      index: 0,
      streakIncremented: false,
    );
  }

  /// Answers the current card's question. [correct] maps onto the SM-2 grading
  /// pipeline: a correct answer is a [ReviewGrade.good] recall, a wrong one is a
  /// [ReviewGrade.forgot] lapse (which reschedules the card for tomorrow, keeping
  /// spaced repetition fresh). Tracks the running quiz score and stamps the
  /// session start on the first answer. Cards with no question (null slot) are
  /// graded as a recall so the deck still advances.
  Future<void> answer({required bool correct, bool counts = true}) async {
    if (state.startedAt == null) {
      state = state.copyWith(startedAt: DateTime.now());
    }
    // [counts] is false for an un-quizzable card (no question): it still grades
    // as a recall so the deck advances and SM-2 keeps scheduling, but it does
    // NOT count toward the quiz score/total.
    if (counts && correct) {
      state = state.copyWith(score: state.score + 1);
    }
    await grade(correct ? ReviewGrade.good : ReviewGrade.forgot);
  }

  /// Grades the current card. EVERY Isar mutation for this grade — the SM-2
  /// schedule on the highlight, today's [DailyActivity] row, and the streak in
  /// [ReviewState] — happens inside ONE write transaction, so there is never a
  /// second transaction in flight (Isar forbids nesting). Reads issued inside a
  /// write transaction reuse the ambient transaction; they do NOT open a new
  /// one. Every non-Isar side effect (notifications, the Supabase mirror, the
  /// streak-bounce flag, provider invalidation) runs strictly AFTER the
  /// transaction has committed.
  Future<void> grade(ReviewGrade grade) async {
    final card = state.current;
    if (card == null) return;

    final isFirstGradeOfSession = state.index == 0;
    final now = DateTime.now();
    final today = _dateOnly(now);
    final userId = ref.read(currentUserProvider)?.id ?? 'local';

    final next = scheduleSm2(
      easeFactor: card.reviewEase ?? kDefaultEaseFactor,
      intervalDays: card.reviewIntervalDays ?? 0,
      repetitions: card.reviewReps ?? 0,
      grade: grade,
      now: now,
    );

    final isar = ref.read(isarProvider);

    // Filled inside the transaction, read back out after it commits.
    var advanced = false;
    var persisted = false;

    // The review ritual must NEVER crash the UI. The single write below is the
    // only thing here that can fail, so it is wrapped: ANY error (a transient
    // storage failure, or — belt-and-suspenders — an unexpected transaction
    // state) is logged and swallowed, and the deck still advances. An unsaved
    // card simply resurfaces next session.
    try {
      await isar.writeTxn(() async {
        // 1 ─ SM-2 schedule on the highlight.
        final fresh = await isar.highlights.get(card.id);
        if (fresh != null) {
          fresh
            ..reviewEase = next.easeFactor
            ..reviewIntervalDays = next.intervalDays
            ..reviewReps = next.repetitions
            ..reviewDueAt = next.dueAt;
          await isar.highlights.put(fresh);
        }

        // 2 ─ Today's activity row: +1 reviewedCount, and on the first graded
        //     card of the session flip reviewedComplete (so a heatmap can tell
        //     "did a full session" from "graded a card or two"). Date-only
        //     keyed, so it auto-rolls at midnight with no background task.
        var activity = await isar.dailyActivitys
            .filter()
            .userIdEqualTo(userId)
            .dayEqualTo(today)
            .findFirst();
        activity ??= DailyActivity()
          ..userId = userId
          ..day = today;
        activity.reviewedCount += 1;
        if (isFirstGradeOfSession) activity.reviewedComplete = true;
        await isar.dailyActivitys.put(activity);

        // 3 ─ Streak — advances at most once per day, on the first graded card,
        //     so even a partial ripasso keeps the flame alive.
        if (isFirstGradeOfSession) {
          var rs = await isar.reviewStates
              .filter()
              .userIdEqualTo(userId)
              .findFirst();
          rs ??= ReviewState()..userId = userId;

          // Normalise stored timestamps to LOCAL date-only before comparing.
          // Isar reads DateTime back as UTC, so the old raw `!= today` (today is
          // local midnight) was ALWAYS true — which silently reset the streak to
          // 1 every day and re-fired the Supabase/Jam side effects on every
          // session. Compare local-day to local-day.
          final lastReviewedLocal = rs.lastReviewedOn == null
              ? null
              : _dateOnly(rs.lastReviewedOn!.toLocal());
          final reviewedTodayLocal = rs.reviewedTodayDate == null
              ? null
              : _dateOnly(rs.reviewedTodayDate!.toLocal());

          // Reset today's counter across the day boundary.
          if (reviewedTodayLocal != today) {
            rs.reviewedTodayCount = 0;
            rs.reviewedTodayDate = today;
          }
          rs.reviewedTodayCount += 1;

          if (lastReviewedLocal != today) {
            final yesterday = today.subtract(const Duration(days: 1));
            rs.currentStreak =
                lastReviewedLocal == yesterday ? rs.currentStreak + 1 : 1;
            if (rs.currentStreak > rs.bestStreak) {
              rs.bestStreak = rs.currentStreak;
            }
            rs.lastReviewedOn = today;
            advanced = true;
          }

          await isar.reviewStates.put(rs);
        }
      });
      persisted = true;
    } catch (error, stack) {
      // Never surface a crash to the review UI — log and degrade gracefully.
      debugPrint('[Ripasso] grade not persisted (continuing session): '
          '$error\n$stack');
    }

    // ── Side effects, only when the write actually committed ─────────────────
    var incremented = state.streakIncremented;
    if (persisted && isFirstGradeOfSession) {
      incremented = advanced || incremented;
      // The session now counts as today's review — silence the evening
      // "did you do your review today?" nudge so it can't fire later.
      unawaited(LocalNotifService.cancelEveningReviewReminder());
      if (advanced) {
        unawaited(_notifyJamMates());
      }
    }

    // Advance the deck regardless, so a grade tap is never a dead end. The
    // recap counters deliberately count EVERY graded tap (even one whose Isar
    // write failed and will resurface tomorrow): the recap reflects what the
    // user did today, not what the store managed to persist.
    state = state.copyWith(
      index: state.index + 1,
      streakIncremented: incremented,
      forgotCount: state.forgotCount + (grade == ReviewGrade.forgot ? 1 : 0),
      hardCount: state.hardCount + (grade == ReviewGrade.hard ? 1 : 0),
      goodCount: state.goodCount + (grade == ReviewGrade.good ? 1 : 0),
    );

    // The streak + activity log changed; refresh the streak + heatmap sources.
    if (persisted) {
      ref.invalidate(reviewStateProvider);
      ref.invalidate(reviewedDaysProvider);
    }

    // Session over → record the completed quiz ONCE on the server (Ripasso 2.0,
    // mark_review_completed_v2 RPC: bumps profiles.review_streak AND writes the
    // score/total/duration into every jam the user belongs to), and persist
    // today's recap so the finished screen AND the locked entry card can show
    // the results until the next 08:00 reset. The old per-card
    // mark_review_completed sync is gone — completion is a single atomic call.
    if (state.isFinished && state.deck.isNotEmpty) {
      final cards = state.total;
      // Quiz total = answerable questions only (un-quizzable recalls excluded),
      // so score/total and accuracy reflect what was actually quizzed.
      final quizTotal = state.questionsTotal;
      final score = state.score;
      final startedAt = state.startedAt;
      final elapsed = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds;
      final forgot = state.forgotCount;
      final hard = state.hardCount;
      final good = state.goodCount;
      unawaited(_markCompletedOnServer(
        cards: cards,
        score: score,
        total: quizTotal,
        durationSeconds: elapsed,
      ));
      unawaited(saveRipassoResults(
        cards: cards,
        forgot: forgot,
        hard: hard,
        good: good,
        score: score,
        total: quizTotal,
        durationSeconds: elapsed,
      ).then((_) {
        try {
          ref.invalidate(ripassoResultsProvider);
        } catch (_) {/* provider disposed — nothing to refresh */}
      }));
      // Lock the daily ripasso until 08:00 tomorrow — ONLY now, at the END of
      // the session. Setting it per-grade replaced the in-flight session with
      // the locked summary right after the first answer, so multi-card decks
      // never finished and the completion writes above never ran. Locking at
      // completion keeps the session intact; an abandoned session simply
      // resumes its remaining (still-due) cards next time.
      unawaited(markRipassoCompletedNow().then((_) {
        try {
          ref.invalidate(ripassoLockProvider);
        } catch (_) {/* provider disposed — nothing to refresh */}
      }));
    }
  }

  /// One atomic server call at session end (mark_review_completed_v2): bumps the
  /// profile streak the jam "Ripasso" leaderboard reads AND records today's
  /// score/total/duration in every jam the user belongs to. Best-effort.
  Future<void> _markCompletedOnServer({
    required int cards,
    required int score,
    required int total,
    required int durationSeconds,
  }) async {
    try {
      await ref.read(supabaseServiceProvider).markReviewCompletedV2(
            cards: cards,
            score: score,
            total: total,
            durationSeconds: durationSeconds,
          );
    } catch (error) {
      debugPrint('[Ripasso] server completion skipped: $error');
    }
  }

  Future<void> _notifyJamMates() async {
    try {
      await ref.read(supabaseServiceProvider).notifyJamMatesReviewDone();
    } catch (error) {
      debugPrint('[Ripasso] jam-mate notify skipped: $error');
    }
  }

}

final reviewSessionControllerProvider = AutoDisposeNotifierProvider<
    ReviewSessionController, ReviewSessionState>(ReviewSessionController.new);
