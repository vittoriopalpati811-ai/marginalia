// ─── Save an image to the device photo library / gallery ───────────────────────
//
// Thin wrapper over the native `marginalia/photos` MethodChannel. iOS saves via
// PHPhotoLibrary (AppDelegate.swift); Android saves via MediaStore
// (MainActivity.kt). Fails SAFE: returns false if the platform side is missing
// or the user denied permission, so callers can show a graceful message.

import 'dart:typed_data';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('marginalia/photos');

/// Saves [bytes] (PNG/JPEG) to the camera roll / gallery.
/// Returns true on success, false on any failure (no exception is thrown).
Future<bool> saveImageToGallery(Uint8List bytes) async {
  try {
    final ok = await _channel.invokeMethod<bool>('saveImage', {'bytes': bytes});
    return ok ?? false;
  } catch (_) {
    return false;
  }
}
