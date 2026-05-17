import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Persists the onboarding-complete flag as a marker file in the app's
/// documents directory. Using a file avoids a new package dependency while
/// being reliable on iOS/Android.
class OnboardingService {
  static const _kMarkerName = '.onboarding_complete';

  static Future<bool> isComplete() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_kMarkerName').existsSync();
    } catch (_) {
      // If we can't read the flag (permissions, unexpected error) treat as
      // complete so we never permanently block the app.
      return true;
    }
  }

  static Future<void> markComplete() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/$_kMarkerName').writeAsString('1');
    } catch (_) {
      // Best-effort: if writing fails the user will see onboarding again
      // next launch, which is the safer fallback.
    }
  }
}
