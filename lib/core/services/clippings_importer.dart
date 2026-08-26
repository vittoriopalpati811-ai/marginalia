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
import 'import_match.dart';
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

/// Builds one canonical "My Clippings" entry from a Kobo Bookmark row.
/// Kobo rows have no Kindle-style location, and the importer dedups on
/// book+location — without a synthetic location every same-book highlight
/// collides with the first one and gets silently dropped. The stable
/// content-hash location (same trick as the paste synthesizer) keeps distinct
/// highlights distinct AND makes a re-import dedup instead of duplicating.
/// The author's parentheses are sanitised because the parser reads the LAST
/// '(...)' of the title line as the author. Exposed for unit testing.
/// A stable, numeric synthetic location for a Kobo highlight.
///
/// It has to be BOTH:
///   * stable across SDK upgrades — it is persisted as the highlight's location
///     and compared on every later import, so `String.hashCode` (what this used
///     to be) would silently duplicate a reader's whole Kobo library the first
///     time Dart changed its hashing. The Amazon sync already moved to a
///     digest for exactly this reason; Kobo had been left behind.
///   * numeric — MyClippingsParser reads `[\d-]+` out of a location line, so a
///     hex digest parses as no location at all, and every same-book highlight
///     would collide on the null key and be dropped.
///
/// So: fold the first 48 bits of the content digest into an integer.
int koboLocation(String text) =>
    int.parse(contentFingerprint(text).substring(0, 12), radix: 16);

String buildKoboEntry({
  String? title,
  String? author,
  required String text,
  String? date,
}) {
  final safeTitle = ((title ?? '').trim().isEmpty ? 'Kobo' : title!.trim());
  final safeAuthor =
      (author ?? '').trim().replaceAll('(', '[').replaceAll(')', ']');
  final location = koboLocation(text);
  // Kobo can hand us a bookmark whose `content` row is gone, so there is no
  // author at all. MyClippingsParser REJECTS an entry whose first line is not
  // "Title (Author)" — empty parentheses do not match either, its pattern needs
  // a character inside — so those highlights used to be dropped on the floor
  // without a word. Naming the source beats losing the sentence; the reader can
  // correct it, they cannot recover what never arrived.
  final titleLine = '$safeTitle (${safeAuthor.isEmpty ? 'Kobo' : safeAuthor})';
  return '$titleLine\n'
      '- Your Highlight | location $location | Added on ${date ?? ''}\n\n$text';
}

/// Lets the user pick their Kobo `KoboReader.sqlite` and imports its highlights
/// (the Bookmark table joined with the book metadata in `content`). Returns the
/// [ImportResult], or `null` if the user cancelled. Throws on a malformed file
/// or when no highlights are found — callers should surface it.
/// Reads a Kobo `KoboReader.sqlite` and returns one canonical "My Clippings"
/// entry per highlight, in book/date order.
///
/// Split out of [pickAndImportKobo] on purpose: this half depends only on the
/// file, so a test can run it against a real SQLite database and catch a wrong
/// assumption about Kobo's schema (the `Bookmark`/`content` tables and the
/// `VolumeID` → `ContentID` join). Inside the picker it was unreachable from
/// any test.
///
/// Each `Bookmark` row with non-empty `Text` is a highlight; `content` holds
/// the book-level row that carries the title and author.
List<String> koboEntriesFromDb(String path) {
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
      final text = ((row['text'] as String?) ?? '').trim();
      if (text.isEmpty) continue;
      entries.add(buildKoboEntry(
        title: row['title'] as String?,
        author: row['author'] as String?,
        text: text,
        date: row['date']?.toString(),
      ));
    }
  } finally {
    db.dispose();
  }
  return entries;
}

Future<ImportResult?> pickAndImportKobo(WidgetRef ref) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.any);
  if (picked == null || picked.files.isEmpty) return null;
  final path = picked.files.first.path;
  if (path == null) return null;

  final entries = koboEntriesFromDb(path);

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
