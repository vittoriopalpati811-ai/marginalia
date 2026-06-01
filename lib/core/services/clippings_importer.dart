// ─── Clippings importer (shared helper) ──────────────────────────────────────
//
// Opens a .txt file picker, decodes it (BOM-aware, UTF-8 with latin1 fallback)
// and imports it as a Kindle "My Clippings.txt" via ImportService. Shared by the
// Library "+" button and the Settings "Import My Clippings.txt" entry so the two
// stay in sync and there's a single import code path.

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/isar_provider.dart';
import 'import_service.dart';

/// Strips a UTF-8 BOM if present, decodes as UTF-8, falls back to latin1.
String decodeClippings(Uint8List bytes) {
  var data = bytes;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    data = bytes.sublist(3);
  }
  try {
    return utf8.decode(data);
  } catch (_) {}
  return latin1.decode(data);
}

/// Lets the user pick a `.txt` file and imports it as My Clippings.
/// Returns the [ImportResult], or `null` if the user cancelled (no file).
/// Throws on import failure — callers should wrap in try/catch and surface it.
Future<ImportResult?> pickAndImportClippings(WidgetRef ref) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['txt'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;

  final file = picked.files.first;
  if (file.bytes == null) return null;

  final rawText = decodeClippings(file.bytes!);
  final userId = ref.read(currentUserProvider)?.id ?? 'local';
  final isar = ref.read(isarProvider);
  final supabase = ref.read(supabaseServiceProvider);
  final service = ImportService(isar, userId, supabaseService: supabase);
  return service.importClippingsText(rawText);
}
