// Global inbox state — kept alive across tabs so:
//   1. New messages refresh the inbox automatically (no pull-to-refresh)
//   2. The bottom-nav Messages tab can show a red unread badge from any
//      screen, not just when the user is on the Messages tab.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Conversations list. NOT autoDispose — the bottom-nav badge needs
/// this populated even when the user is not on the Messages tab, and
/// the inbox preview otherwise served stale "Foto" text until pull-to-refresh.
///
/// Re-runs whenever the signed-in user changes (so login refetches,
/// logout clears) AND whenever inboxRealtimeProvider's channel state
/// changes (so the realtime subscription stays alive).
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

  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final svc = ref.read(supabaseServiceProvider);
  return svc.fetchConversations();
});

/// Opens a Supabase realtime channel for the current user; on any new
/// `messages` row INSERT, invalidates [conversationsProvider] so the
/// inbox refetches with the latest message preview + unread state.
///
/// Critically: this provider watches ONLY the current user's *id*
/// (`currentUserProvider.select((u) => u?.id)`), NOT the whole User object.
/// [currentUserProvider] is backed by the auth-state stream and re-emits a
/// brand-new `User` instance on EVERY auth event — token refresh, app
/// resume, etc. Watching the whole object rebuilt this provider on each of
/// those events; every rebuild ran `onDispose` (unsubscribing the channel)
/// and opened a fresh one, so the channel never stayed up long enough to
/// deliver realtime inserts. The Supabase realtime logs showed the tenant
/// churning connect → "no connected users" → terminate → reconnect. Selecting
/// just the id means the provider only rebuilds on a real login/logout, so the
/// channel stays subscribed and inserts actually arrive. (Same defect/fix as
/// the recommendations provider.)
///
/// We don't filter the channel by conversation IDs because that list
/// changes over time (new chats, new group invites); cheaper to just
/// invalidate on every insert and let the RLS-aware fetch do the rest.
final inboxRealtimeProvider = Provider<void>((ref) {
  // Watch ONLY the id, not the whole User — see the doc comment above.
  final uid = ref.watch(currentUserProvider.select((u) => u?.id));
  if (uid == null) return;

  final svc = ref.read(supabaseServiceProvider);

  RealtimeChannel? channel;
  Timer? reconnectTimer;
  Timer? invalidateTimer;
  var disposed = false;

  // Coalesce rapid inbox refetches into one fetchConversations() call ~300ms
  // later. In an active chat every incoming message fires an INSERT *and* the
  // read-receipt UPDATE it triggers; debouncing keeps the N+1 inbox query from
  // running twice per message while still feeling instant.
  void scheduleInboxRefresh() {
    invalidateTimer?.cancel();
    invalidateTimer = Timer(const Duration(milliseconds: 300), () {
      if (!disposed) ref.invalidate(conversationsProvider);
    });
  }

  void subscribe() {
    // Tear down any previous channel before opening a fresh one so a
    // reconnect never leaks a half-open channel.
    final previous = channel;
    if (previous != null) {
      svc.client.removeChannel(previous);
    }

    channel = svc.client
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
            scheduleInboxRefresh();
          },
        )
        .onPostgresChanges(
          // Read-state reactivity: when THIS user's conversation_members row
          // changes (last_read_at advances as they read a chat — here or on
          // another device), refetch the inbox so the unread/bold styling
          // clears WITHOUT a manual pull-to-refresh. This is the missing link:
          // marking a conversation read updates conversation_members, which was
          // not previously surfaced to the list. Requires migration 052
          // (conversation_members added to the realtime publication +
          // REPLICA IDENTITY FULL, so this user_id filter actually matches).
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => scheduleInboxRefresh(),
        )
        .subscribe((status, [error]) {
          // Surface all status transitions so this is debuggable if it
          // breaks again. Visible in the browser console / Xcode logs.
          debugPrint('[inbox-realtime] status=$status error=$error');

          // Resilience: if the socket drops (channelError / closed / timedOut)
          // recreate the channel after a short backoff so realtime recovers
          // without an app restart. Guard against scheduling multiple timers
          // and against firing after the provider was disposed.
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (disposed || reconnectTimer != null) return;
            reconnectTimer = Timer(const Duration(seconds: 2), () {
              reconnectTimer = null;
              if (disposed) return;
              debugPrint('[inbox-realtime] re-subscribing after $status');
              subscribe();
            });
          }
        });
  }

  subscribe();

  ref.onDispose(() {
    disposed = true;
    reconnectTimer?.cancel();
    invalidateTimer?.cancel();
    final c = channel;
    if (c != null) svc.client.removeChannel(c);
  });
});

/// Optimistic, session-local "read" timestamps keyed by conversation id.
///
/// When the user opens a chat we record the current time here *immediately*,
/// then overlay it on top of the server's `my_last_read_at` wherever unread
/// state is computed. This clears the red nav dot + the bold conversation
/// styling the instant the chat opens — without waiting for the
/// `mark_conversation_read` RPC to round-trip, and even if that RPC is
/// unavailable (e.g. the backend migration is not yet applied). It was the
/// reported symptom: "dopo aver visualizzato il messaggio rimane 'da
/// visualizzare'".
///
/// It can only ever make a conversation look READ, never unread: a genuinely
/// newer incoming message (created after our local read time) still surfaces
/// as unread, because the comparison below always uses the *latest* of the
/// local and server read times.
class LocallyReadConversations extends Notifier<Map<String, DateTime>> {
  static const _prefsKey = 'locally_read_conversations_v1';

  @override
  Map<String, DateTime> build() {
    // Hydrate from disk so a conversation the user already opened doesn't come
    // back as unread after the app is killed and reopened (founder, 2026-06-19:
    // "ogni volta che esco dall'app e rientro me lo da come nuovo messaggio").
    // The overlay can only ever make a chat look READ — a genuinely newer
    // incoming message is still after this timestamp, so nothing is hidden.
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final restored = <String, DateTime>{};
      for (final e in decoded.entries) {
        final t = DateTime.tryParse(e.value as String);
        if (t != null) restored[e.key] = t;
      }
      if (restored.isEmpty) return;
      // Merge: keep the later of any in-session value and the persisted one.
      final merged = <String, DateTime>{...restored};
      state.forEach((k, v) {
        final prev = merged[k];
        merged[k] = (prev == null || v.isAfter(prev)) ? v : prev;
      });
      state = merged;
    } catch (_) {
      // Best-effort: a corrupt/absent store just means no optimistic overlay.
    }
  }

  void markRead(String conversationId) {
    state = {...state, conversationId: DateTime.now().toUtc()};
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        {for (final e in state.entries) e.key: e.value.toIso8601String()},
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // Non-fatal: persistence is an optimisation over the server read state.
    }
  }
}

final locallyReadProvider =
    NotifierProvider<LocallyReadConversations, Map<String, DateTime>>(
  LocallyReadConversations.new,
);

/// Resolves the effective "read up to" instant for a conversation: the later
/// of the server's persisted `my_last_read_at` and any optimistic local read
/// recorded this session. Returns null only when the conversation has never
/// been read by either source.
DateTime? _effectiveReadTime(
  String? serverReadIso,
  DateTime? localRead,
) {
  final serverRead =
      serverReadIso != null ? DateTime.tryParse(serverReadIso) : null;
  if (serverRead == null) return localRead;
  if (localRead == null) return serverRead;
  return localRead.isAfter(serverRead) ? localRead : serverRead;
}

/// Number of conversations where the latest message is from someone else
/// and is newer than my effective read time. Drives the red dot on the
/// bottom-nav Messages tab.
final unreadConversationsCountProvider = Provider<int>((ref) {
  final svc   = ref.watch(supabaseServiceProvider);
  final me    = svc.userId;
  if (me == null) return 0;

  final convs = ref.watch(conversationsProvider).asData?.value ?? const [];
  final locallyRead = ref.watch(locallyReadProvider);

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

    final convId   = c['id'] as String?;
    final readTime = _effectiveReadTime(
      c['my_last_read_at'] as String?,
      convId != null ? locallyRead[convId] : null,
    );
    if (readTime == null) {
      count++;                              // never opened
    } else if (msgTime.isAfter(readTime)) {
      count++;
    }
  }
  return count;
});
