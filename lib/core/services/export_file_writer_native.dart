import 'dart:io';
import 'dart:ui' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [markdown] to a temp file named [filename] and opens the system
/// share sheet so the user can save/send it as a .md file.
Future<void> writeAndShareMarkdown({
  required String markdown,
  required String filename,
  String? subject,
  Rect? sharePositionOrigin,
}) async {
  final tmpDir = await getTemporaryDirectory();
  final file = File('${tmpDir.path}/$filename');
  await file.writeAsString(markdown, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/markdown')],
    subject: subject ?? 'Scripta Export',
    text: '📚 I miei highlight da Scripta',
    sharePositionOrigin: sharePositionOrigin,
  );
}

/// Writes [csv] to a temp .csv file and opens the system share sheet. The CSV is
/// shaped for a Notion database import (Reading Tracker) but works in Sheets,
/// Excel, Numbers, etc.
Future<void> writeAndShareCsv({
  required String csv,
  required String filename,
  String? subject,
  Rect? sharePositionOrigin,
}) async {
  final tmpDir = await getTemporaryDirectory();
  final file = File('${tmpDir.path}/$filename');
  await file.writeAsString(csv, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv')],
    subject: subject ?? 'Scripta Export',
    text: '📚 Scripta — Reading Tracker',
    sharePositionOrigin: sharePositionOrigin,
  );
}
