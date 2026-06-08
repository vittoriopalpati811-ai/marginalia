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

  /// Schedule (or re-schedule) a repeating daily "Ripasso" reminder telling the
  /// user how many highlights are due. Runs under its own stable identifier
  /// ("review_due") in parallel with the daily phrase, so it is idempotent —
  /// re-scheduling on each launch/foreground replaces the pending request and
  /// keeps the count fresh. Cancel it (see [cancelReviewReminder]) when nothing
  /// is due, so a stale "you have N to review" never fires.
  static Future<void> scheduleReviewReminder({
    int hour = 9,
    int minute = 0,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('scheduleReviewReminder', {
        'hour': hour,
        'minute': minute,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('[LocalNotif] scheduleReviewReminder failed: $e');
    }
  }

  /// Cancel the pending Ripasso reminder, if any.
  static Future<void> cancelReviewReminder() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('cancelReviewReminder');
    } catch (e) {
      debugPrint('[LocalNotif] cancelReviewReminder failed: $e');
    }
  }

  /// Schedule (or re-schedule) the repeating evening "Did you do your review
  /// today?" nudge under its own stable identifier ("review_evening"), firing at
  /// 21:00 local. Distinct from the morning [scheduleReviewReminder] so the two
  /// never collide. Idempotent (re-scheduling replaces the pending request). The
  /// caller is responsible for only scheduling this when the user has NOT
  /// reviewed today, and for cancelling it (see [cancelEveningReviewReminder])
  /// the moment a review session is started/completed.
  static Future<void> scheduleEveningReviewReminder({
    int hour = 21,
    int minute = 0,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('scheduleEveningReviewReminder', {
        'hour': hour,
        'minute': minute,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('[LocalNotif] scheduleEveningReviewReminder failed: $e');
    }
  }

  /// Cancel the pending evening Ripasso reminder, if any.
  static Future<void> cancelEveningReviewReminder() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('cancelEveningReviewReminder');
    } catch (e) {
      debugPrint('[LocalNotif] cancelEveningReviewReminder failed: $e');
    }
  }
}
