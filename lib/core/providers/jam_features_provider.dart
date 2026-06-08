// ─── Jam 2.0 Providers ───────────────────────────────────────────────────────
//
// Providers for: Book Voting, Reading Challenges, Highlight Polls, Notifications.
// Feature 4 (Member Profile Sheet) is purely UI — no provider needed.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

// ─── Book Voting ──────────────────────────────────────────────────────────────

final bookProposalsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) =>
      ref.read(supabaseServiceProvider).fetchBookProposals(jamId),
);

/// The Jam's "Libro del mese": the proposal with the most votes (the leading
/// pick). Returns null while loading or when there are no proposals. Derived
/// from [bookProposalsProvider] so it stays in sync with voting.
final jamCurrentBookProvider =
    Provider.autoDispose.family<Map<String, dynamic>?, String>((ref, jamId) {
  final list = ref.watch(bookProposalsProvider(jamId)).asData?.value;
  if (list == null || list.isEmpty) return null;
  Map<String, dynamic>? best;
  var bestVotes = -1;
  for (final p in list) {
    final votes = (p['jam_book_votes'] as List?)?.length ?? 0;
    if (votes > bestVotes) {
      bestVotes = votes;
      best = p;
    }
  }
  return best;
});

// ─── Reading Challenges ───────────────────────────────────────────────────────

final jamChallengesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) =>
      ref.read(supabaseServiceProvider).fetchJamChallenges(jamId),
);

// ─── Highlight Polls ──────────────────────────────────────────────────────────

final jamPollsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) =>
      ref.read(supabaseServiceProvider).fetchJamPolls(jamId),
);

// ─── Ripasso leaderboard (review competition) ─────────────────────────────────

final jamReviewLeaderboardProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) =>
      ref.read(supabaseServiceProvider).fetchJamReviewLeaderboard(jamId),
);

// ─── Notifications ────────────────────────────────────────────────────────────

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.read(supabaseServiceProvider).fetchNotifications(),
);

final unreadNotificationCountProvider =
    FutureProvider.autoDispose<int>(
  (ref) => ref.read(supabaseServiceProvider).fetchUnreadNotificationCount(),
);
