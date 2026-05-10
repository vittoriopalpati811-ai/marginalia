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

const _supabaseUrl = 'https://ibucvloawkfwobaelwbr.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc';

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
