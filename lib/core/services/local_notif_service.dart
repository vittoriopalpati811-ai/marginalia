import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// Schedules the daily "frase del giorno" engagement nudge as a native iOS
/// local notification.
///
/// The native side (ios/Runner/AppDelegate.swift) exposes a
/// `marginalia/localnotif` method channel that reuses the same
/// UNUserNotificationCenter authorization already requested for push, so this
/// never triggers a second permission prompt. The notification fires daily at a
/// fixed time via a repeating UNCalendarNotificationTrigger under the stable
/// identifier `daily_phrase`, so [scheduleDailyPhrase] is idempotent — calling
/// it on every launch replaces the pending request instead of stacking copies.
///
/// iOS-only and best-effort: every call is wrapped in try/catch so a missing
/// channel (off-iOS) or a not-yet-granted permission can never crash the app.
class LocalNotifService {
  const LocalNotifService._();

  static const MethodChannel _ch = MethodChannel('marginalia/localnotif');

  static bool get _supported => !kIsWeb && Platform.isIOS;

  /// Schedule (or re-schedule) the repeating daily phrase reminder.
  static Future<void> scheduleDailyPhrase({
    int hour = 9,
    int minute = 0,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('scheduleDailyPhrase', {
        'hour': hour,
        'minute': minute,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('[LocalNotif] scheduleDailyPhrase failed: $e');
    }
  }

  /// Cancel the pending daily phrase reminder, if any.
  static Future<void> cancel() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('cancelDailyPhrase');
    } catch (e) {
      debugPrint('[LocalNotif] cancel failed: $e');
    }
  }
}
