import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [markdown] to a temp file named [filename] and opens the system
/// share sheet so the user can save/send it as a .md file.
Future<void> writeAndShareMarkdown({
  required String markdown,
  required String filename,
  String? subject,
}) async {
  final tmpDir = await getTemporaryDirectory();
  final file = File('${tmpDir.path}/$filename');
  await file.writeAsString(markdown, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/markdown')],
    subject: subject ?? 'Marginalia Export',
    text: '📚 I miei highlight da Marginalia',
  );
}
