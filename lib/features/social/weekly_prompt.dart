/// Rotating weekly prompts that nudge Jam members to share contextually.
/// The current prompt is deterministic per ISO week so all members of the same
/// jam see the same prompt at the same time.
class WeeklyPrompt {
  static const _prompts = [
    'Share a highlight that changed your mind this week.',
    'A quote that made you laugh recently — share it with the Jam.',
    'The most uncomfortable idea you have underlined recently.',
    'A highlight you disagree with the author on. Why?',
    'The quote you would get tattooed, if you weren\'t afraid.',
    'A passage you had to re-read three times. Why?',
    'The most practical advice you extracted this week.',
    'A sentence you thought was obvious, but keeps coming back to you.',
    'A highlight from a book you wouldn\'t recommend — but with a good idea inside.',
    'The most "difficult" quote you underlined. Explain it in 2 lines.',
    'A passage you shared offline with someone. Bring it here.',
    'An annotation you made years ago that you would read differently today.',
  ];

  /// Current prompt — rotates by ISO week-of-year, stable within a week.
  static String current([DateTime? now]) {
    final n = now ?? DateTime.now();
    final week = _isoWeekNumber(n);
    return _prompts[week % _prompts.length];
  }

  // Approximate ISO 8601 week number for the given date.
  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final diff = thursday.difference(
        firstThursday.subtract(Duration(days: (firstThursday.weekday + 6) % 7)));
    return (diff.inDays / 7).floor() + 1;
  }
}
