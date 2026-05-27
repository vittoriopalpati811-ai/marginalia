import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../providers/onboarding_provider.dart';
import '../services/onboarding_service.dart';

Future<void> launchApp() async {
  // Read persisted onboarding state from localStorage so returning users
  // skip straight into the app while new users always see the onboarding.
  final onboardingComplete = await OnboardingService.isComplete();

  runApp(
    ProviderScope(
      overrides: [
        onboardingCompleteProvider.overrideWith((ref) => onboardingComplete),
      ],
      child: const MarginaliaApp(),
    ),
  );
}
