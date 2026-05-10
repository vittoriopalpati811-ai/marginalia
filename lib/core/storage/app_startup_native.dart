import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../app.dart';
import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../models/tag_native.dart';
import '../models/jam_native.dart';
import '../providers/isar_provider_native.dart';

Future<void> launchApp() async {
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [BookSchema, HighlightSchema, TagSchema, JamSchema],
    directory: dir.path,
  );
  runApp(
    ProviderScope(
      overrides: [isarProvider.overrideWithValue(isar)],
      child: const MarginaliaApp(),
    ),
  );
}
