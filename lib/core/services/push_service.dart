import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

import 'supabase_service.dart';

/// Bridges native APNs registration to Supabase.
///
/// The native side (ios/Runner/AppDelegate.swift) exposes a `marginalia/push`
/// method channel. [start] requests notification permission + registers for
/// remote notifications; when iOS returns the device token, AppDelegate invokes
/// `onToken`, which we persist via [SupabaseService.registerDeviceToken]
/// (table `device_tokens`, platform `ios`). The `send-push-notification` edge
/// function later reads those tokens to deliver pushes.
///
/// No-op on anything other than iOS. Idempotent — safe to call on every
/// auth-state change.
class PushService {
  PushService(this._supabase);

  final SupabaseService _supabase;

  static const MethodChannel _channel = MethodChannel('marginalia/push');
  bool _started = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToken') {
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          try {
            await _supabase.registerDeviceToken(token);
          } catch (e) {
            debugPrint('[Push] registerDeviceToken failed: $e');
          }
        }
      }
    });

    try {
      await _channel.invokeMethod<bool>('register');
    } catch (e) {
      // MissingPluginException off-iOS, or the user denied permission.
      debugPrint('[Push] register failed: $e');
    }
  }
}
