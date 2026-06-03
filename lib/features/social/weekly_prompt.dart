import 'package:flutter/widgets.dart';

import '../../core/l10n/l10n_extension.dart';

/// Rotating weekly prompts that nudge Jam members to share contextually.
/// The current prompt is deterministic per ISO week so all members of the same
/// jam see the same prompt at the same time.
class WeeklyPrompt {
  /// The localized prompt pool. Built from [context] so the strings follow the
  /// active locale. Order is stable so the ISO-week index keeps pointing at the
  /// same conceptual prompt across locales.
  static List<String> _prompts(BuildContext context) {
    final l10n = context.l10n;
    return [
      l10n.weeklyPrompt1,
      l10n.weeklyPrompt2,
      l10n.weeklyPrompt3,
      l10n.weeklyPrompt4,
      l10n.weeklyPrompt5,
      l10n.weeklyPrompt6,
      l10n.weeklyPrompt7,
      l10n.weeklyPrompt8,
      l10n.weeklyPrompt9,
      l10n.weeklyPrompt10,
      l10n.weeklyPrompt11,
      l10n.weeklyPrompt12,
    ];
  }

  /// Current localized prompt — rotates by ISO week-of-year, stable within a
  /// week. Needs a [context] to resolve the localized strings.
  static String current(BuildContext context, [DateTime? now]) {
    final prompts = _prompts(context);
    final n = now ?? DateTime.now();
    final week = _isoWeekNumber(n);
    return prompts[week % prompts.length];
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
