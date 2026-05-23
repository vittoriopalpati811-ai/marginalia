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

// ─── Notifications ────────────────────────────────────────────────────────────

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.read(supabaseServiceProvider).fetchNotifications(),
);

final unreadNotificationCountProvider =
    FutureProvider.autoDispose<int>(
  (ref) => ref.read(supabaseServiceProvider).fetchUnreadNotificationCount(),
);
