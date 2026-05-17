import 'package:share_plus/share_plus.dart';

/// Web stub: no file system available, shares the markdown as plain text.
Future<void> writeAndShareMarkdown({
  required String markdown,
  required String filename,
  String? subject,
}) async {
  await Share.share(
    markdown,
    subject: subject ?? 'Marginalia Export',
  );
}
