import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the user has already completed the onboarding flow.
///
/// Initialized at app startup via [ProviderScope.overrides] in
/// app_startup_native.dart / app_startup_web.dart. Screens that complete
/// onboarding call:
///
///   ref.read(onboardingCompleteProvider.notifier).state = true;
///
/// Default is `false` so that any code path that fails to override (e.g.
/// hot-restart on web before localStorage loads, fresh install) defaults
/// to showing onboarding rather than skipping it. The user explicitly
/// asked for onboarding to be mandatory before the app is visible.
final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

/// The user's self-selected gender, used ONLY locally to gently tailor the
/// daily-phrase tone. Values: 'female' | 'male' | 'unspecified' (or null until
/// chosen).
///
/// PRIVACY: this is privacy-sensitive special-category data. It is persisted
/// ONLY on-device via [GenderService] and is NEVER uploaded to Supabase or any
/// server. Seeded at startup via [ProviderScope.overrides] in
/// app_startup_native.dart / app_startup_web.dart, the same way as
/// [onboardingCompleteProvider].
final genderProvider = StateProvider<String?>((ref) => null);
