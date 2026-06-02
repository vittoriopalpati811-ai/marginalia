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
import 'package:sqlite3/sqlite3.dart';

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

/// Lets the user pick their Kobo `KoboReader.sqlite` and imports its highlights
/// (the Bookmark table joined with the book metadata in `content`). Returns the
/// [ImportResult], or `null` if the user cancelled. Throws on a malformed file
/// or when no highlights are found — callers should surface it.
Future<ImportResult?> pickAndImportKobo(WidgetRef ref) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.any);
  if (picked == null || picked.files.isEmpty) return null;
  final path = picked.files.first.path;
  if (path == null) return null;

  // Read the Kobo annotations DB (read-only). Each Bookmark row with non-empty
  // Text is a highlight; join `content` (the book-level row, ContentID ==
  // VolumeID) for the title + author.
  final entries = <String>[];
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final rows = db.select('''
      SELECT b.Text AS text, b.DateCreated AS date,
             c.BookTitle AS title, c.Attribution AS author
      FROM Bookmark b
      LEFT JOIN content c ON c.ContentID = b.VolumeID
      WHERE b.Text IS NOT NULL AND TRIM(b.Text) <> ''
      ORDER BY c.BookTitle, b.DateCreated
    ''');
    for (final row in rows) {
      final title = ((row['title'] as String?) ?? 'Kobo').trim();
      final author = ((row['author'] as String?) ?? '').trim();
      final text = ((row['text'] as String?) ?? '').trim();
      if (text.isEmpty) continue;
      entries.add('$title ($author)\n'
          '- Your Highlight | Added on ${row['date'] ?? ''}\n\n$text');
    }
  } finally {
    db.dispose();
  }

  if (entries.isEmpty) {
    throw Exception('Nessun highlight trovato in questo file Kobo.');
  }

  // Reuse the My Clippings importer (same "==========" separator format).
  final clippingsText = entries.join('\n==========\n');
  final userId = ref.read(currentUserProvider)?.id ?? 'local';
  final isar = ref.read(isarProvider);
  final supabase = ref.read(supabaseServiceProvider);
  final service = ImportService(isar, userId, supabaseService: supabase);
  return service.importClippingsText(clippingsText);
}
