// Global inbox state — kept alive across tabs so:
//   1. New messages refresh the inbox automatically (no pull-to-refresh)
//   2. The bottom-nav Messages tab can show a red unread badge from any
//      screen, not just when the user is on the Messages tab.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Conversations list. NOT autoDispose — the bottom-nav badge needs
/// this populated even when the user is not on the Messages tab, and
/// the inbox preview otherwise served stale "Foto" text until pull-to-refresh.
///
/// Explicit FutureProvider<...> annotation breaks the type-inference cycle
/// caused by inboxRealtimeProvider also referencing this provider via
/// `ref.invalidate(conversationsProvider)`.
final FutureProvider<List<Map<String, dynamic>>> conversationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Touching this provider also wires up the realtime subscription
  // (see inboxRealtimeProvider below) so the inbox auto-refreshes when
  // anyone sends a message.
  ref.watch(inboxRealtimeProvider);

  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  return svc.fetchConversations();
});

/// Opens a Supabase realtime channel for the current user; on any new
/// `messages` row INSERT, invalidates [conversationsProvider] so the
/// inbox refetches with the latest message preview + unread state.
///
/// We don't filter the channel by conversation IDs because that list
/// changes over time (new chats, new group invites); cheaper to just
/// invalidate on every insert and let the RLS-aware fetch do the rest.
final inboxRealtimeProvider = Provider<void>((ref) {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return;

  final uid = svc.userId;
  if (uid == null) return;

  final channel = svc.client
      .channel('inbox:$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          // Don't react to messages we sent ourselves — the chat screen's
          // own optimistic update has already handled them, and refetching
          // the inbox right after a local send creates a brief preview
          // flicker.
          final senderId = payload.newRecord['sender_id'] as String?;
          if (senderId == uid) return;
          ref.invalidate(conversationsProvider);
        },
      )
      .subscribe((status, [_]) {
        if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('[inbox-realtime] channel error');
        }
      });

  ref.onDispose(() => channel.unsubscribe());
});

/// Number of conversations where the latest message is from someone else
/// and is newer than my `last_read_at`. Drives the red dot on the
/// bottom-nav Messages tab.
final unreadConversationsCountProvider = Provider<int>((ref) {
  final svc   = ref.watch(supabaseServiceProvider);
  final me    = svc.userId;
  if (me == null) return 0;

  final convs = ref.watch(conversationsProvider).asData?.value ?? const [];

  var count = 0;
  for (final c in convs) {
    final lastMsg = c['last_message'] as Map<String, dynamic>?;
    if (lastMsg == null) continue;

    final senderId = lastMsg['sender_id'] as String?;
    if (senderId == me) continue;          // I sent it → not unread

    final msgIso  = lastMsg['created_at'] as String?;
    if (msgIso == null) continue;
    final msgTime = DateTime.tryParse(msgIso);
    if (msgTime == null) continue;

    final readIso = c['my_last_read_at'] as String?;
    if (readIso == null) {
      count++;                              // never opened
    } else {
      final readTime = DateTime.tryParse(readIso);
      if (readTime != null && msgTime.isAfter(readTime)) count++;
    }
  }
  return count;
});
