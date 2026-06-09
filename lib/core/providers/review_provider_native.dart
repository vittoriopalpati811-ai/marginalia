import 'dart:async';

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
class ReviewSessionState {
  const ReviewSessionState({
    required this.deck,
    required this.index,
    required this.streakIncremented,
  });

  /// The cards for this session, in order. Stable for the session's lifetime.
  final List<Highlight> deck;

  /// Index of the current top card. When `index >= deck.length` the session is
  /// finished and the review screen shows the "all caught up" state.
  final int index;

  /// True once the just-finished session pushed the streak to a new day — lets
  /// the finished state play the one-time flame bounce / "+1".
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

/// Drives the deck on the review screen. Holds the in-memory queue + index,
/// applies SM-2 on each grade (offline, in a writeTxn), and updates the streak
/// once the session has at least one graded card.
class ReviewSessionController
    extends AutoDisposeNotifier<ReviewSessionState> {
  @override
  ReviewSessionState build() => const ReviewSessionState(
        deck: [],
        index: 0,
        streakIncremented: false,
      );

  /// Loads the deck for today. Called once when the review screen mounts.
  Future<void> load() async {
    final deck = await ref.read(dueHighlightsProvider.future);
    state = ReviewSessionState(
      deck: deck,
      index: 0,
      streakIncremented: false,
    );
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
    var streak = 0;
    var best = 0;
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

          streak = rs.currentStreak;
          best = rs.bestStreak;
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
        // Best-effort, fire-and-forget Supabase mirrors — they never block or
        // break the offline loop and silently degrade if migration 050/051
        // isn't applied yet. Guarded by `advanced`, so each fires at most once
        // per day (when the streak rolls to a new day).
        unawaited(_mirrorStreak(streak, best, today));
        unawaited(_notifyJamMates());
      }
    }

    // Advance the deck regardless, so a grade tap is never a dead end.
    state = state.copyWith(
      index: state.index + 1,
      streakIncremented: incremented,
    );

    // The streak + activity log changed; refresh the streak + heatmap sources.
    if (persisted) {
      ref.invalidate(reviewStateProvider);
      ref.invalidate(reviewedDaysProvider);
      // Flow today's running card count into the Jam results feed (an upsert
      // keyed by day keeps the latest), so jam-mates see Ripasso activity — both
      // the user's own and everyone else's.
      unawaited(_logRipassoToJams(state.index));
    }
  }

  Future<void> _logRipassoToJams(int cardsReviewed) async {
    try {
      await ref
          .read(supabaseServiceProvider)
          .logRipassoResultsToJams(cardsReviewed);
    } catch (error) {
      debugPrint('[Ripasso] jam result log skipped: $error');
    }
  }

  Future<void> _notifyJamMates() async {
    try {
      await ref.read(supabaseServiceProvider).notifyJamMatesReviewDone();
    } catch (error) {
      debugPrint('[Ripasso] jam-mate notify skipped: $error');
    }
  }

  Future<void> _mirrorStreak(int streak, int best, DateTime lastReviewedOn) async {
    try {
      await ref
          .read(supabaseServiceProvider)
          .updateReviewStreak(
            streak: streak,
            bestStreak: best,
            lastReviewedOn: lastReviewedOn,
          );
    } catch (error) {
      debugPrint('[Ripasso] streak mirror skipped: $error');
    }
  }
}

final reviewSessionControllerProvider = AutoDisposeNotifierProvider<
    ReviewSessionController, ReviewSessionState>(ReviewSessionController.new);
