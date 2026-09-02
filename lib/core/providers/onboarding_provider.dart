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

/// The reader's own description of their cycle, as `yyyy-MM-dd|length` (the
/// day their last period started, and how many days their cycle usually runs).
/// Null until they set it, and cleared the moment they remove it.
///
/// This replaced the HealthKit read that Apple rejected under Guideline 2.5.1.
/// It is a better fit for the promise the app makes: the reader CHOOSES to tell
/// Scripta, sees the value in Settings and can delete it, instead of the phone
/// handing over cycle samples in the background.
///
/// PRIVACY: special-category data, persisted ONLY on-device via [CycleService]
/// and NEVER uploaded. Seeded at startup via [ProviderScope.overrides] like
/// [genderProvider].
final cycleProvider = StateProvider<String?>((ref) => null);

/// How the user tends to feel before something on their calendar, used ONLY
/// locally to tailor the daily-phrase tone when an event is coming up. Values:
/// 'calm' | 'focused' | 'anxious' (or null until chosen / skipped).
///
/// PRIVACY: stored ONLY on-device via [EventApproachService], NEVER uploaded.
/// Seeded at startup via [ProviderScope.overrides] in app_startup_*.dart, the
/// same way as [genderProvider].
final eventApproachProvider = StateProvider<String?>((ref) => null);
