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

  final deck = [...due, ...fresh];
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

  return due + (freshTotal > kDailyNewCardCap ? kDailyNewCardCap : freshTotal);
});

/// Reads (creating if absent) the per-user [ReviewState] singleton. Not
/// autoDispose: the streak should stay stable across navigation within a
/// session. Invalidated by the session controller after a streak update.
final reviewStateProvider = FutureProvider<ReviewState>((ref) async {
  final isar = ref.watch(isarProvider);
  final userId = ref.watch(currentUserProvider)?.id ?? 'local';

  final existing =
      await isar.reviewStates.filter().userIdEqualTo(userId).findFirst();
  if (existing != null) return existing;

  final created = ReviewState()..userId = userId;
  await isar.writeTxn(() async => isar.reviewStates.put(created));
  return created;
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

  /// Grades the current card: persists the new SM-2 schedule, advances the deck,
  /// and — the first time a card is graded in this session — bumps the streak.
  Future<void> grade(ReviewGrade grade) async {
    final card = state.current;
    if (card == null) return;

    final isFirstGradeOfSession = state.index == 0;
    final now = DateTime.now();

    final next = scheduleSm2(
      easeFactor: card.reviewEase ?? kDefaultEaseFactor,
      intervalDays: card.reviewIntervalDays ?? 0,
      repetitions: card.reviewReps ?? 0,
      grade: grade,
      now: now,
    );

    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      final fresh = await isar.highlights.get(card.id);
      if (fresh == null) return;
      fresh
        ..reviewEase = next.easeFactor
        ..reviewIntervalDays = next.intervalDays
        ..reviewReps = next.repetitions
        ..reviewDueAt = next.dueAt;
      await isar.highlights.put(fresh);
    });

    // Record this card in today's activity log (offline-first; foundation for
    // the profile review-heatmap). One row per local day; reviewedCount sums
    // every card graded that day across sessions.
    await _logActivity(now, completedSession: isFirstGradeOfSession);

    // Streak counts after the FIRST graded card, so even a partial ripasso keeps
    // the flame alive.
    var incremented = state.streakIncremented;
    if (isFirstGradeOfSession) {
      incremented = await _applyStreak(now) || incremented;
      // The session is now under way and counts as today's review — silence the
      // evening "did you do your review today?" nudge so it can't fire later.
      unawaited(LocalNotifService.cancelEveningReviewReminder());
    }

    state = state.copyWith(
      index: state.index + 1,
      streakIncremented: incremented,
    );

    // The activity log changed; refresh the heatmap source.
    ref.invalidate(reviewedDaysProvider);
  }

  /// Upserts today's [DailyActivity] row: +1 [reviewedCount], and on the first
  /// graded card of the session flips [reviewedComplete] so a heatmap can tell
  /// "did a full session" from "graded a card or two". Date-only keyed, so it
  /// auto-rolls at midnight without a background task.
  Future<void> _logActivity(
    DateTime now, {
    required bool completedSession,
  }) async {
    final isar = ref.read(isarProvider);
    final userId = ref.read(currentUserProvider)?.id ?? 'local';
    final today = _dateOnly(now);

    await isar.writeTxn(() async {
      var row = await isar.dailyActivitys
          .filter()
          .userIdEqualTo(userId)
          .dayEqualTo(today)
          .findFirst();
      row ??= DailyActivity()
        ..userId = userId
        ..day = today;
      row.reviewedCount += 1;
      if (completedSession) row.reviewedComplete = true;
      await isar.dailyActivitys.put(row);
    });
  }

  /// Continues/resets the consecutive-day streak and records today's progress.
  /// Returns true if [currentStreak] advanced to a new day (for the UI bounce).
  Future<bool> _applyStreak(DateTime now) async {
    final isar = ref.read(isarProvider);
    final userId = ref.read(currentUserProvider)?.id ?? 'local';
    final today = _dateOnly(now);

    var advanced = false;
    late int streak;
    late int best;

    await isar.writeTxn(() async {
      var rs =
          await isar.reviewStates.filter().userIdEqualTo(userId).findFirst();
      rs ??= ReviewState()..userId = userId;

      // Reset today's counter across the day boundary.
      if (rs.reviewedTodayDate != today) {
        rs.reviewedTodayCount = 0;
        rs.reviewedTodayDate = today;
      }
      rs.reviewedTodayCount += 1;

      if (rs.lastReviewedOn != today) {
        final yesterday = today.subtract(const Duration(days: 1));
        rs.currentStreak =
            rs.lastReviewedOn == yesterday ? rs.currentStreak + 1 : 1;
        if (rs.currentStreak > rs.bestStreak) rs.bestStreak = rs.currentStreak;
        rs.lastReviewedOn = today;
        advanced = true;
      }

      streak = rs.currentStreak;
      best = rs.bestStreak;
      await isar.reviewStates.put(rs);
    });

    // Refresh any widget watching the streak (Library card, Profile, review UI).
    ref.invalidate(reviewStateProvider);

    if (advanced) {
      // Best-effort, fire-and-forget Supabase mirror — never blocks the offline
      // loop and silently degrades if migration 050 isn't applied yet.
      unawaited(_mirrorStreak(streak, best, today));
      // First completed review of the day → tell our jam-mates. The `advanced`
      // guard means this fires at most once per day (when the streak rolls to a
      // new day), never on subsequent cards. Fire-and-forget, never throws.
      unawaited(_notifyJamMates());
    }
    return advanced;
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
