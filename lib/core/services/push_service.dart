import 'dart:async' show Future;

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

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
/// Token re-registration is robust: besides registering once on [start]
/// (called on auth-state change at launch / sign-in), [PushService] registers
/// itself as a [WidgetsBindingObserver] and re-invokes the native `register`
/// every time the app returns to the foreground ([AppLifecycleState.resumed]).
/// This guarantees the CURRENT install's APNs token is re-sent — and thus
/// upserted into `device_tokens` — even after a TestFlight update changed it,
/// which a launch-only registration would miss.
///
/// No-op on anything other than iOS. Idempotent — safe to call on every
/// auth-state change.
class PushService with WidgetsBindingObserver {
  PushService(this._supabase);

  final SupabaseService _supabase;

  static const MethodChannel _channel = MethodChannel('marginalia/push');
  bool _started = false;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;

    // Re-register on every foreground so the CURRENT token is always saved.
    WidgetsBinding.instance.addObserver(this);

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onToken':
          final token = call.arguments as String?;
          if (token != null && token.isNotEmpty) {
            await _saveToken(token);
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

    await _register();
  }

  /// Re-runs registration when the app returns to the foreground. The native
  /// `register` re-requests permission if needed and re-fires `onToken`, so the
  /// latest token is re-upserted every time — covering a token that rotated
  /// while the app (or a fresh TestFlight build) was backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _register();
    }
  }

  /// Invokes the native `register` (request permission if needed +
  /// registerForRemoteNotifications). iOS-guarded and idempotent. Returns
  /// `true` when authorization was granted; logs and returns `false` when the
  /// user denied permission.
  Future<bool> _register() async {
    if (!_supported) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('register') ?? false;
      if (!granted) {
        debugPrint('[Push] permission DENIED');
      }
      return granted;
    } catch (e) {
      // MissingPluginException off-iOS, or a native registration error.
      debugPrint('[Push] register failed: $e');
      return false;
    }
  }

  /// Persists a received APNs token, retrying once after ~2s on failure so a
  /// transient network/Supabase error doesn't permanently drop the token.
  Future<void> _saveToken(String token) async {
    try {
      await _supabase.registerDeviceToken(token);
      debugPrint('[Push] token registered (len=${token.length})');
    } catch (e) {
      debugPrint('[Push] registerDeviceToken failed, retrying in 2s: $e');
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await _supabase.registerDeviceToken(token);
        debugPrint('[Push] token registered (len=${token.length})');
      } catch (e2) {
        debugPrint('[Push] registerDeviceToken retry failed: $e2');
      }
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
    // The Ripasso reminders (morning + evening local notifications) carry
    // `review == "true"` so a tap opens the daily recall screen directly.
    final isReview = data['review'] == 'true' || data['review'] == true;

    final String? location;
    if (conversationId != null && conversationId.isNotEmpty) {
      location = '/chat/${Uri.encodeComponent(conversationId)}';
    } else if (postId != null && postId.isNotEmpty) {
      location = '/post/${Uri.encodeComponent(postId)}';
    } else if (isReview) {
      location = '/review';
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
