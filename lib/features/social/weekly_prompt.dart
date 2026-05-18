/// Rotating weekly prompts that nudge Jam members to share contextually.
/// The current prompt is deterministic per ISO week so all members of the same
/// jam see the same prompt at the same time.
class WeeklyPrompt {
  static const _prompts = [
    'Condividi un highlight che ti ha cambiato idea questa settimana.',
    'Una citazione che ti ha fatto ridere di recente — passala alla Jam.',
    'L\'idea più scomoda che hai sottolineato negli ultimi giorni.',
    'Un highlight su cui sei in disaccordo con l\'autore. Perché?',
    'La citazione che vorresti tatuarti, se non avessi paura.',
    'Un passaggio che hai dovuto rileggere tre volte. Perché?',
    'Il consiglio più pratico che hai estratto questa settimana.',
    'Una frase che pensavi fosse banale, ma che ora ti torna in mente.',
    'Un highlight da un libro che non consiglieresti — ma con una buona idea dentro.',
    'La citazione più "difficile" che hai sottolineato. Spiegacela in 2 righe.',
    'Un passaggio che hai condiviso offline con qualcuno. Riportacelo qui.',
    'Una sottolineatura che hai fatto anni fa e che oggi leggeresti diversamente.',
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
