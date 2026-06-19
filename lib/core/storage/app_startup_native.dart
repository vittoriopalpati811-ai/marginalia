import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../app.dart';
import '../models/book_native.dart';
import '../models/highlight_native.dart';
import '../models/tag_native.dart';
import '../models/jam_native.dart';
import '../models/review_state_native.dart';
import '../models/daily_activity_native.dart';
import '../providers/isar_provider_native.dart';
import '../providers/locale_provider.dart';
import '../providers/onboarding_provider.dart';
import '../services/event_approach_service.dart';
import '../services/gender_service.dart';
import '../services/locale_service.dart';
import '../services/onboarding_service.dart';

Future<void> launchApp() async {
  // Open the local database FIRST, on its own, with full error handling.
  //
  // This is the single piece of startup that can hard-fail on a real device:
  // the Isar native library or the documents directory. It used to run
  // unguarded inside a `Future.wait`, so any failure threw before runApp() and
  // produced a silent black screen. If _openIsar() ultimately fails it now
  // propagates to the zone guard in main(), which renders a readable error
  // screen instead of black.
  final isar = await _openIsar();

  // The remaining reads are already internally defensive, but guard them too so
  // a surprise here can never block the app from launching.
  var onboardingComplete = false;
  // English-predominant default until the persisted choice is read below
  // (Italian only on Italian-language devices). See LocaleService.deviceDefault.
  var savedLocale = LocaleService.deviceDefault();
  try {
    onboardingComplete = await OnboardingService.isComplete();
  } catch (error) {
    debugPrint('[launchApp] onboarding read failed (non-fatal): $error');
  }
  try {
    savedLocale = await LocaleService.getLocale();
  } catch (error) {
    debugPrint('[launchApp] locale read failed (non-fatal): $error');
  }
  // Privacy-sensitive: read the locally-stored gender (never uploaded) so the
  // daily-phrase personalisation can restore it across launches.
  String? savedGender;
  try {
    savedGender = await GenderService.read();
  } catch (error) {
    debugPrint('[launchApp] gender read failed (non-fatal): $error');
  }
  // Locally-stored "how I approach a calendar event" (never uploaded) so the
  // daily-phrase personalisation can restore it across launches.
  String? savedEventApproach;
  try {
    savedEventApproach = await EventApproachService.read();
  } catch (error) {
    debugPrint('[launchApp] event-approach read failed (non-fatal): $error');
  }

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
        onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
        localeProvider.overrideWith((ref) => savedLocale),
        genderProvider.overrideWith((ref) => savedGender),
        eventApproachProvider.overrideWith((ref) => savedEventApproach),
      ],
      child: const ScriptaApp(),
    ),
  );
}

/// Opens the Isar database defensively:
///   • reuses an already-open instance (e.g. after a bootstrap retry),
///   • falls back across writable directories if the documents dir is missing,
///   • bounds each attempt with a timeout so a hang surfaces as an error
///     instead of an indefinite black screen,
///   • retries once after a short delay for transient first-launch races.
///
/// If it still cannot open, the error propagates to main()'s zone guard, which
/// shows the real exception on the error screen.
Future<Isar> _openIsar() async {
  final List<CollectionSchema<dynamic>> schemas = [
    BookSchema,
    HighlightSchema,
    TagSchema,
    JamSchema,
    ReviewStateSchema,
    DailyActivitySchema,
  ];

  // Reuse an instance that is already open (idempotent across retries).
  // getInstance() only returns instances that are currently open.
  final existing = Isar.getInstance();
  if (existing != null) return existing;

  final dir = await _resolveStorageDirectory();

  try {
    return await Isar.open(schemas, directory: dir.path)
        .timeout(const Duration(seconds: 12));
  } catch (error) {
    debugPrint('[launchApp] Isar.open failed, retrying once: $error');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // A concurrent open may have finished while we waited.
    final maybe = Isar.getInstance();
    if (maybe != null) return maybe;

    return await Isar.open(schemas, directory: dir.path)
        .timeout(const Duration(seconds: 12));
  }
}

/// Resolves a writable directory for the database, preferring the app documents
/// directory and degrading gracefully if a platform can't provide it.
Future<Directory> _resolveStorageDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (error) {
    debugPrint('[launchApp] documents dir unavailable, trying support dir: $error');
  }
  try {
    return await getApplicationSupportDirectory();
  } catch (error) {
    debugPrint('[launchApp] support dir unavailable, using temp dir: $error');
  }
  return getTemporaryDirectory();
}
