import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../app.dart' show router;
import 'supabase_service.dart';

/// Bridges native APNs registration to Supabase, and routes notification taps
/// into the app as deep links.
///
/// The native side (ios/Runner/AppDelegate.swift) exposes a `marginalia/push`
/// method channel. [start] requests notification permission + registers for
/// remote notifications; when iOS returns the device token, AppDelegate invokes
/// `onToken`, which we persist via [SupabaseService.registerDeviceToken]
/// (table `device_tokens`, platform `ios`). The `send-push-notification` edge
/// function later reads those tokens to deliver pushes.
///
/// When the user TAPS a notification, AppDelegate invokes `onNotificationTap`
/// with the payload's navigation keys, which [start] turns into a `go_router`
/// deep link: `conversation_id` → `/chat/<id>`, otherwise `post_id` →
/// `/post/<id>`. After wiring the handler, [start] calls `tapHandlerReady` so a
/// tap that launched the app from a terminated state (buffered natively) is
/// replayed and routed.
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
      switch (call.method) {
        case 'onToken':
          final token = call.arguments as String?;
          if (token != null && token.isNotEmpty) {
            try {
              await _supabase.registerDeviceToken(token);
            } catch (e) {
              debugPrint('[Push] registerDeviceToken failed: $e');
            }
          }
        case 'onNotificationTap':
          _handleNotificationTap(call.arguments);
      }
    });

    // Tell the native side the tap handler is attached, so any tap that was
    // buffered during a cold launch (terminated → tap → relaunch) gets replayed.
    try {
      await _channel.invokeMethod<void>('tapHandlerReady');
    } catch (e) {
      debugPrint('[Push] tapHandlerReady failed: $e');
    }

    try {
      await _channel.invokeMethod<bool>('register');
    } catch (e) {
      // MissingPluginException off-iOS, or the user denied permission.
      debugPrint('[Push] register failed: $e');
    }
  }

  /// Deep-links into the app from a tapped notification. AppDelegate forwards a
  /// `Map<String, String>` with the payload's navigation keys; a message push
  /// carries `conversation_id`, a like/comment push carries `type` + `post_id`.
  ///
  /// Routing is deferred to the next frame so a tap that arrives before the
  /// router/first frame is ready (cold launch) still navigates instead of
  /// being dropped.
  void _handleNotificationTap(Object? arguments) {
    if (arguments is! Map) return;
    final data = arguments;

    final conversationId = data['conversation_id'] as String?;
    final postId = data['post_id'] as String?;

    final String? location;
    if (conversationId != null && conversationId.isNotEmpty) {
      location = '/chat/${Uri.encodeComponent(conversationId)}';
    } else if (postId != null && postId.isNotEmpty) {
      location = '/post/${Uri.encodeComponent(postId)}';
    } else {
      location = null;
    }
    if (location == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        router.push(location!);
      } catch (e) {
        debugPrint('[Push] deep-link navigation failed: $e');
      }
    });
  }
}
