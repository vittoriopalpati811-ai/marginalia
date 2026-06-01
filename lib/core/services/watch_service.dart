// ─── Watch service ────────────────────────────────────────────────────────────
//
// Pushes the daily phrase + reading stats to the paired Apple Watch via the
// native WatchConnectivity bridge (AppDelegate "marginalia/watch" channel →
// WCSession.updateApplicationContext). The watch app stores the values in its
// shared App Group and reloads the complications. No-op off iOS.
//
// Keys MUST match what the watch app reads (MarginaliaWatchApp.swift):
// w_text / w_book / w_author / w_month_min / w_streak / w_updated.

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

class WatchService {
  static const _channel = MethodChannel('marginalia/watch');

  static Future<void> send({
    required String text,
    required String book,
    required String author,
    required int monthMinutes,
    required int streak,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('send', <String, dynamic>{
        'w_text': text,
        'w_book': book,
        'w_author': author,
        'w_month_min': monthMinutes,
        'w_streak': streak,
        'w_updated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // MissingPluginException off-device, or no paired watch — safe to ignore.
      debugPrint('[WatchService] send skipped: $e');
    }
  }
}
