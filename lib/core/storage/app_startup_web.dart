import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../providers/onboarding_provider.dart';
import '../services/event_approach_service.dart';
import '../services/gender_service.dart';
import '../services/onboarding_service.dart';

Future<void> launchApp() async {
  // Read persisted onboarding state from localStorage so returning users
  // skip straight into the app while new users always see the onboarding.
  final onboardingComplete = await OnboardingService.isComplete();

  // Privacy-sensitive: read the locally-stored gender (never uploaded) so the
  // daily-phrase personalisation can restore it across launches.
  final savedGender = await GenderService.read();
  final savedEventApproach = await EventApproachService.read();

  runApp(
    ProviderScope(
      overrides: [
        onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
        genderProvider.overrideWith((ref) => savedGender),
        eventApproachProvider.overrideWith((ref) => savedEventApproach),
      ],
      child: const ScriptaApp(),
    ),
  );
}
