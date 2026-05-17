// Conditional export: native (dart:io) file write on iOS/Android/desktop,
// text-only share stub on web.
export 'export_file_writer_web.dart'
    if (dart.library.io) 'export_file_writer_native.dart';
