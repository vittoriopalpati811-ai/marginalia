// Conditional export: native (dart:io) on iOS/Android/desktop, stub on web.
export 'share_file_helper_web.dart'
    if (dart.library.io) 'share_file_helper_native.dart';
