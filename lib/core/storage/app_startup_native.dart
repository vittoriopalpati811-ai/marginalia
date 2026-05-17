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
import '../providers/onboarding_provider.dart';
import '../services/onboarding_service.dart';

Future<void> launchApp() async {
  final dir = await getApplicationDocumentsDirectory();

  // Open Isar and check onboarding status in parallel.
  final results = await Future.wait([
    Isar.open(
      [BookSchema, HighlightSchema, TagSchema, JamSchema],
      directory: dir.path,
    ),
    OnboardingService.isComplete(),
  ]);

  final isar = results[0] as Isar;
  final onboardingComplete = results[1] as bool;

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
        onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
      ],
      child: const MarginaliaApp(),
    ),
  );
}
