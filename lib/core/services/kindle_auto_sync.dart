// ─── Kindle sync that runs by itself ─────────────────────────────────────────
//
// The Amazon sync was already hands-off ONCE you reached the notebook page: the
// extractor is injected automatically and the highlights import themselves. What
// was missing is the part that makes it feel automatic — it only ever happened
// when the reader remembered to open Settings and tap. Founder, on rival apps:
// "rendi tutto piu automatico".
//
// So: after the first successful sync we remember that this device is connected,
// and from then on the app quietly re-syncs on its own when it is opened and the
// last run is stale. No screen, no spinner, no interruption; the reader simply
// finds new highlights waiting.
//
// Three things make that safe to do silently:
//
//   • It is IDEMPOTENT. ImportService dedups on (book, location), so re-reading
//     the whole notebook adds only what is genuinely new — a repeat run costs
//     nothing and can never duplicate a highlight.
//   • The Amazon session lives in the platform cookie store, which survives app
//     restarts, so a background run needs no password and never sees one.
//   • It FAILS SILENTLY. If the session has expired Amazon redirects to the
//     sign-in page; we detect that, stop, and raise a quiet flag so the app can
//     ask for a reconnection at a moment that suits the reader — a background
//     job must never hijack the screen or throw an error at someone who did not
//     ask for anything.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How stale a sync has to be before opening the app triggers another one.
/// Kindle highlights arrive at reading pace, not chat pace; six hours keeps the
/// library fresh across a morning and an evening without hammering Amazon.
const Duration kKindleSyncInterval = Duration(hours: 6);

const _kConnected     = 'kindle.connected';
const _kLastSyncMs    = 'kindle.lastSyncMs';
const _kNeedsRelogin  = 'kindle.needsRelogin';

/// What the background sync is doing, for the few places that show it.
enum KindleSyncPhase { idle, running, done, needsRelogin, failed }

class KindleSyncState {
  const KindleSyncState({
    required this.connected,
    required this.phase,
    this.lastSync,
    this.lastImported = 0,
  });

  /// This device has completed at least one sync, so it may run unattended.
  final bool connected;
  final KindleSyncPhase phase;
  final DateTime? lastSync;

  /// Highlights added by the most recent run — 0 is the normal, quiet case.
  final int lastImported;

  bool get isStale =>
      lastSync == null || DateTime.now().difference(lastSync!) >= kKindleSyncInterval;

  KindleSyncState copyWith({
    bool? connected,
    KindleSyncPhase? phase,
    DateTime? lastSync,
    int? lastImported,
  }) =>
      KindleSyncState(
        connected: connected ?? this.connected,
        phase: phase ?? this.phase,
        lastSync: lastSync ?? this.lastSync,
        lastImported: lastImported ?? this.lastImported,
      );
}

class KindleAutoSync extends StateNotifier<KindleSyncState> {
  KindleAutoSync()
      : super(const KindleSyncState(
          connected: false,
          phase: KindleSyncPhase.idle,
        )) {
    _ready = _load();
  }

  /// Completes once the persisted flags are in [state].
  ///
  /// This matters more than it looks: the app asks for a sync from a post-frame
  /// callback, which fires well before this read of SharedPreferences returns.
  /// Without waiting, a connected device sees `connected: false` on every cold
  /// start and silently skips the very sync the reader is waiting for.
  late final Future<void> _ready;

  /// Set by the hidden webview host once it is mounted and able to run a sync.
  /// Null means "no one can drive a sync right now", and every request is simply
  /// dropped — silence is the correct behaviour for an unasked-for job.
  Future<int> Function()? runner;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastSyncMs);
    state = state.copyWith(
      connected: prefs.getBool(_kConnected) ?? false,
      lastSync: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      phase: (prefs.getBool(_kNeedsRelogin) ?? false)
          ? KindleSyncPhase.needsRelogin
          : KindleSyncPhase.idle,
    );
  }

  /// Called after a sync the reader drove themselves. From this point the device
  /// is trusted to sync unattended.
  Future<void> markConnected({int imported = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setBool(_kConnected, true);
    await prefs.setBool(_kNeedsRelogin, false);
    await prefs.setInt(_kLastSyncMs, now.millisecondsSinceEpoch);
    state = state.copyWith(
      connected: true,
      lastSync: now,
      lastImported: imported,
      phase: KindleSyncPhase.done,
    );
  }

  /// The Amazon session is gone. Stop trying, and let the UI ask for a
  /// reconnection when the reader is actually looking.
  Future<void> markNeedsRelogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNeedsRelogin, true);
    state = state.copyWith(phase: KindleSyncPhase.needsRelogin);
  }

  /// The entry point for "the app was opened": sync only if this device is
  /// connected, is not waiting for a re-login, and the last run has gone stale.
  Future<void> maybeSyncInBackground() async {
    await _ready;
    if (!state.connected) return;
    if (state.phase == KindleSyncPhase.running) return;
    if (state.phase == KindleSyncPhase.needsRelogin) return;
    if (!state.isStale) return;
    await syncNow();
  }

  /// Runs a sync now. Used by the automatic path and by the manual "refresh"
  /// in Settings, so both share one implementation and one set of states.
  Future<void> syncNow() async {
    final run = runner;
    if (run == null || state.phase == KindleSyncPhase.running) return;

    state = state.copyWith(phase: KindleSyncPhase.running, lastImported: 0);
    try {
      final imported = await run();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_kLastSyncMs, now.millisecondsSinceEpoch);
      state = state.copyWith(
        phase: KindleSyncPhase.done,
        lastSync: now,
        lastImported: imported,
      );
    } on _AmazonSessionExpired {
      await markNeedsRelogin();
    } catch (_) {
      // A failed unattended sync is a non-event: the next app open tries again.
      state = state.copyWith(phase: KindleSyncPhase.failed);
    }
  }

  /// Forget the connection — used when the reader disconnects Kindle.
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConnected);
    await prefs.remove(_kLastSyncMs);
    await prefs.remove(_kNeedsRelogin);
    state = const KindleSyncState(
      connected: false,
      phase: KindleSyncPhase.idle,
    );
  }
}

/// Thrown by the runner when Amazon bounces us to the sign-in page.
class _AmazonSessionExpired implements Exception {
  const _AmazonSessionExpired();
}

/// Public alias so the webview host can signal an expired session.
const amazonSessionExpired = _AmazonSessionExpired();

final kindleAutoSyncProvider =
    StateNotifierProvider<KindleAutoSync, KindleSyncState>(
  (ref) => KindleAutoSync(),
);
