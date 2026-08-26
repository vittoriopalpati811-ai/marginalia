import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/parser/my_clippings_parser.dart';
import 'package:scripta/core/services/clippings_importer.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

// The Kobo import reads a KoboReader.sqlite with a hand-written query against
// tables Scripta does not own. Nothing used to exercise that query: it lived
// inside the file picker, so a wrong column name or a broken join would only
// have surfaced on a reader's device, as "Nessun highlight trovato".
//
// These tests build a database shaped like a real KoboReader.sqlite and run the
// production reader over it.

/// The subset of Kobo's schema the importer depends on.
void _createKoboSchema(Database db) {
  db.execute('''
    CREATE TABLE content (
      ContentID   TEXT PRIMARY KEY,
      BookTitle   TEXT,
      Attribution TEXT
    );
  ''');
  db.execute('''
    CREATE TABLE Bookmark (
      BookmarkID  TEXT PRIMARY KEY,
      VolumeID    TEXT,
      Text        TEXT,
      DateCreated TEXT
    );
  ''');
}

void main() {
  late Directory tmp;

  // On a device the native library comes from sqlite3_flutter_libs, which the
  // Dart VM used by `flutter test` does not load. Windows ships Microsoft's own
  // build of SQLite as winsqlite3.dll, which exports the same C API — point the
  // loader at it so these tests can run on the founder's machine. Linux and
  // macOS resolve the system library on their own, so they are left alone.
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('kobo_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String buildDb(void Function(Database) fill) {
    final path = '${tmp.path}${Platform.pathSeparator}KoboReader.sqlite';
    final db = sqlite3.open(path);
    _createKoboSchema(db);
    fill(db);
    db.dispose();
    return path;
  }

  test('reads highlights and joins the book title and author', () {
    final path = buildDb((db) {
      db.execute(
        "INSERT INTO content VALUES ('vol-1', 'Il deserto dei Tartari', 'Dino Buzzati')",
      );
      db.execute(
        "INSERT INTO Bookmark VALUES ('bm-1', 'vol-1', 'La vita della Fortezza parve fermarsi.', '2026-07-10T21:00:00')",
      );
      db.execute(
        "INSERT INTO Bookmark VALUES ('bm-2', 'vol-1', 'E intanto il tempo passava.', '2026-07-11T09:30:00')",
      );
    });

    final entries = koboEntriesFromDb(path);
    expect(entries.length, 2);

    // The entries must survive the My Clippings parser the importer feeds them
    // to — that round trip is the whole point of the canonical format.
    final parsed =
        MyClippingsParser().parse('${entries.join('\n==========\n')}\n==========\n');
    expect(parsed.length, 2);
    expect(parsed.every((h) => h.bookTitle == 'Il deserto dei Tartari'), isTrue);
    expect(parsed[0].location, isNotNull);
    expect(parsed[0].location, isNot(parsed[1].location));
  });

  test('skips rows with no text, which Kobo writes for plain bookmarks', () {
    final path = buildDb((db) {
      db.execute("INSERT INTO content VALUES ('vol-1', 'Meditations', 'Marcus Aurelius')");
      db.execute("INSERT INTO Bookmark VALUES ('bm-1', 'vol-1', NULL, '2026-01-01')");
      db.execute("INSERT INTO Bookmark VALUES ('bm-2', 'vol-1', '   ', '2026-01-02')");
      db.execute(
        "INSERT INTO Bookmark VALUES ('bm-3', 'vol-1', 'You have power over your mind.', '2026-01-03')",
      );
    });

    final entries = koboEntriesFromDb(path);
    expect(entries.length, 1);
    expect(entries.single, contains('You have power over your mind.'));
  });

  test('a highlight whose book row is missing still imports', () {
    // LEFT JOIN, so an orphaned VolumeID must not drop the highlight — it just
    // has no title, and buildKoboEntry falls back to "Kobo".
    final path = buildDb((db) {
      db.execute(
        "INSERT INTO Bookmark VALUES ('bm-1', 'vol-missing', 'Un pensiero orfano.', '2026-02-02')",
      );
    });

    final entries = koboEntriesFromDb(path);
    expect(entries.length, 1);
    final parsed = MyClippingsParser().parse('${entries.single}\n==========\n');
    expect(parsed.single.content, 'Un pensiero orfano.');
  });

  test('an empty library reads as no entries rather than throwing', () {
    final path = buildDb((_) {});
    expect(koboEntriesFromDb(path), isEmpty);
  });
}
