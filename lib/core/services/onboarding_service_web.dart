// On web we skip onboarding entirely — the import flow is different
// (drag-and-drop in the library screen) and web is a secondary target.
class OnboardingService {
  static Future<bool> isComplete() async => true;
  static Future<void> markComplete() async {}
}
