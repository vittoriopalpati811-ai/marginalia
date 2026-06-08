import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Web stub: no file system available, shares the markdown as plain text.
Future<void> writeAndShareMarkdown({
  required String markdown,
  required String filename,
  String? subject,
  Rect? sharePositionOrigin,
}) async {
  await Share.share(
    markdown,
    subject: subject ?? 'Scripta Export',
    sharePositionOrigin: sharePositionOrigin,
  );
}

/// Web stub: shares the CSV text (no file system).
Future<void> writeAndShareCsv({
  required String csv,
  required String filename,
  String? subject,
  Rect? sharePositionOrigin,
}) async {
  await Share.share(
    csv,
    subject: subject ?? 'Scripta Export',
    sharePositionOrigin: sharePositionOrigin,
  );
}
