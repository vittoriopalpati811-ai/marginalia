import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the user has already completed the onboarding flow.
///
/// Initialized at app startup via [ProviderScope.overrides] (see
/// app_startup_native.dart). Screens that complete onboarding call:
///
///   ref.read(onboardingCompleteProvider.notifier).state = true;
///
/// Default is `true` so that hot-reload / web builds never show onboarding
/// unexpectedly.
final onboardingCompleteProvider = StateProvider<bool>((ref) => true);
