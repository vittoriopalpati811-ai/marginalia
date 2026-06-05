// Web stub — home_widget is not supported on Flutter web.
// All methods are no-ops; the iOS widget is irrelevant in a browser context.

class WidgetHighlight {
  final String text;
  final String bookTitle;
  final String author;
  final String timeGreeting;
  final String weatherMood;

  const WidgetHighlight({
    required this.text,
    required this.bookTitle,
    required this.author,
    required this.timeGreeting,
    required this.weatherMood,
  });
}

class WidgetService {
  static Future<void> init() async {}

  static Future<WidgetHighlight?> update(
    List<Map<String, dynamic>> highlights, {
    String? chosenText,
    String? chosenBook,
    String? chosenAuthor,
  }) async =>
      null;

  static Future<void> updateStats({
    required int streak,
    required int monthMinutes,
    required int yearBooks,
    required int yearGoal,
  }) async {}
}
