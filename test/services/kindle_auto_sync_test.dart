import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scripta/core/services/kindle_auto_sync.dart';

// The automatic sync decides, unattended, whether to open a webview against
// Amazon. Every rule below is a rule about NOT doing that — an unasked-for job
// that runs too eagerly, twice at once, or after the session died is worse than
// one that never runs. The webview half is device-only; this is the half that
// can be pinned down, so it is.

/// Builds a notifier whose persisted state is already settled, so tests never
/// race the constructor's async `_load()`.
Future<KindleAutoSync> _sync({
  bool connected = false,
  Duration? since,
  bool needsRelogin = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'kindle.connected': connected,
    'kindle.needsRelogin': needsRelogin,
    if (since != null)
      'kindle.lastSyncMs':
          DateTime.now().subtract(since).millisecondsSinceEpoch,
  });
  final notifier = KindleAutoSync();
  await Future<void>.delayed(Duration.zero); // let _load() land
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a cold start does not race the saved flags', () async {
    // Regression: the app asks for a sync from a post-frame callback, which
    // fires long before SharedPreferences answers. The notifier used to still
    // read `connected: false` at that moment and skip the run — so on a
    // connected device the automatic sync did nothing on the open that mattered
    // and only caught up on a later resume. NOTE the missing `await` on the
    // load: this test is only meaningful if it asks immediately.
    SharedPreferences.setMockInitialValues({
      'kindle.connected': true,
      'kindle.lastSyncMs': DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch,
    });
    var runs = 0;
    final sync = KindleAutoSync()..runner = () async => ++runs;

    await sync.maybeSyncInBackground();

    expect(runs, 1, reason: 'cold start skipped the sync it was opened for');
  });

  test('a device that never synced is never touched in the background', () async {
    var runs = 0;
    final sync = await _sync(connected: false);
    sync.runner = () async => ++runs;

    await sync.maybeSyncInBackground();

    expect(runs, 0, reason: 'synced without the reader ever connecting Kindle');
  });

  test('a fresh sync is left alone', () async {
    var runs = 0;
    final sync = await _sync(connected: true, since: const Duration(minutes: 5));
    sync.runner = () async => ++runs;

    await sync.maybeSyncInBackground();

    expect(runs, 0, reason: 'hammered Amazon minutes after the last run');
  });

  test('a stale sync runs and records the new time', () async {
    final sync = await _sync(
      connected: true,
      since: kKindleSyncInterval + const Duration(minutes: 1),
    );
    sync.runner = () async => 3;

    expect(sync.state.isStale, isTrue);
    await sync.maybeSyncInBackground();

    expect(sync.state.phase, KindleSyncPhase.done);
    expect(sync.state.lastImported, 3);
    expect(sync.state.isStale, isFalse, reason: 'the run was not recorded');
  });

  test('an expired Amazon session stops the loop instead of retrying forever',
      () async {
    var runs = 0;
    final sync = await _sync(connected: true, since: const Duration(days: 2));
    sync.runner = () async {
      runs++;
      throw amazonSessionExpired;
    };

    await sync.maybeSyncInBackground();
    expect(sync.state.phase, KindleSyncPhase.needsRelogin);

    // The reader now has to reconnect; until then every later open is a no-op.
    await sync.maybeSyncInBackground();
    expect(runs, 1, reason: 'kept retrying a session Amazon already refused');
  });

  test('an ordinary failure is quiet and retried on the next open', () async {
    var runs = 0;
    final sync = await _sync(connected: true, since: const Duration(days: 2));
    sync.runner = () async {
      runs++;
      throw Exception('network');
    };

    await sync.maybeSyncInBackground();
    expect(sync.state.phase, KindleSyncPhase.failed);

    await sync.maybeSyncInBackground();
    expect(runs, 2, reason: 'a transient failure must not disable the sync');
  });

  test('with no host mounted the request is dropped, not queued', () async {
    final sync = await _sync(connected: true, since: const Duration(days: 2));
    sync.runner = null;

    await sync.maybeSyncInBackground();

    expect(sync.state.phase, isNot(KindleSyncPhase.running),
        reason: 'left stuck in running with nothing able to finish it');
  });

  test('the first manual sync is what unlocks the unattended ones', () async {
    final sync = await _sync(connected: false);
    expect(sync.state.connected, isFalse);

    await sync.markConnected(imported: 12);

    expect(sync.state.connected, isTrue);
    expect(sync.state.lastImported, 12);
    expect(sync.state.isStale, isFalse);
    expect(SharedPreferences.getInstance()
        .then((p) => p.getBool('kindle.connected')), completion(isTrue));
  });

  test('disconnecting forgets everything, including the relogin flag', () async {
    final sync = await _sync(
        connected: true, since: const Duration(days: 2), needsRelogin: true);
    expect(sync.state.phase, KindleSyncPhase.needsRelogin);

    await sync.disconnect();

    expect(sync.state.connected, isFalse);
    expect(sync.state.phase, KindleSyncPhase.idle);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('kindle.needsRelogin'), isNull);
  });
}
