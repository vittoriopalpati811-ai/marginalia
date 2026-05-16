import 'dart:io';
import 'dart:typed_data';

// Writes bytes to path and returns the path. Used by ShareCardService.
Future<String> writeShareFile(String path, Uint8List bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes);
  return path;
}
