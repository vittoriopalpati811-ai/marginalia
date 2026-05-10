import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/models/book.dart';
import 'core/models/highlight.dart';
import 'core/models/tag.dart';
import 'core/models/jam.dart';
import 'core/providers/isar_provider.dart';

// ⚠️  Replace with your actual Supabase project values.
// Find them in: Supabase dashboard → Project Settings → API
const _supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';
const _supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Initialize Isar with all schemas
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [BookSchema, HighlightSchema, TagSchema, JamSchema],
    directory: dir.path,
  );

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
      ],
      child: const MarginaliaApp(),
    ),
  );
}
