// ─── Instagram Stories direct-share channel ──────────────────────────────────
//
// Thin Dart wrapper over the native `marginalia/instagram` MethodChannel
// (implemented in ios/Runner/AppDelegate.swift). It lets the app:
//   • ask whether Instagram is installed (so we only show the dedicated
//     "Instagram Stories" button when it would actually work), and
//   • hand a rendered 9:16 PNG straight to Instagram's Stories composer via the
//     documented `instagram-stories://` URL scheme + pasteboard sticker key.
//
// Everything is defensive: on web, on Android (no handler yet), or if Instagram
// is missing / the call throws, the methods simply return false and the caller
// falls back to the regular system share sheet. The button is therefore never a
// dead end.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('marginalia/instagram');

/// True only when Instagram is installed and the Stories scheme is reachable
/// (iOS). Returns false on web/Android or on any platform error.
Future<bool> instagramStoriesAvailable() async {
  if (kIsWeb) return false;
  try {
    final available = await _channel.invokeMethod<bool>('isAvailable');
    return available ?? false;
  } catch (_) {
    return false;
  }
}

/// Hands [pngBytes] (a 1080×1920 PNG) to Instagram's Stories composer as the
/// background image. Returns true if Instagram opened, false otherwise (caller
/// should fall back to the system share sheet).
Future<bool> shareImageToInstagramStories(Uint8List pngBytes) async {
  if (kIsWeb) return false;
  try {
    final ok = await _channel.invokeMethod<bool>(
      'shareToStories',
      <String, dynamic>{'image': pngBytes},
    );
    return ok ?? false;
  } catch (_) {
    return false;
  }
}
