// ─── Content filter service ──────────────────────────────────────────────────
//
// A pure-Dart, dependency-free first-line keyword filter for objectionable TEXT
// posted to the social feed (posts + comments). It flags four buckets —
// violence (gore / graphic violence), spam, scam (fraud / phishing) and sexual
// (pornographic) — using accent-normalized, case-insensitive, word-boundary
// matching so partial matches inside innocent words don't trigger (e.g.
// "scampo"/"scampi" must NOT match "scam", "classic" must NOT match the
// short token list).
//
// This is intentionally conservative: it catches obvious, clearly-objectionable
// terms and unambiguous scam / porn markers, and is biased toward avoiding
// false positives over exhaustive coverage. The keyword lists live in
// clearly-commented private constants below so they are trivial to extend later.
//
// ⚠️ Scope: this filter only inspects TEXT. Real IMAGE moderation (detecting
// gore / nudity in uploaded photos) requires a server-side vision classifier
// and is out of scope here. Treat this as a lightweight client-side guardrail,
// not a complete moderation system — the authoritative report/block flow
// (report_sheet.dart + Supabase) remains the real safety net.

/// The category a piece of text was flagged under. Buckets are ordered by
/// severity in [ContentFilter._orderedCategories]; [ContentFilterResult.category]
/// reports the most severe bucket that matched.
enum ContentCategory { violence, scam, sexual, spam }

/// Outcome of inspecting a piece of text.
///
/// [flagged] is true when at least one keyword matched. [category] is the
/// single most-severe bucket that matched (null when not flagged), and
/// [matched] lists the actual normalized tokens/phrases that triggered, across
/// all buckets — useful for logging / debugging, never shown to the user.
class ContentFilterResult {
  const ContentFilterResult({
    required this.flagged,
    this.category,
    this.matched = const [],
  });

  final bool flagged;
  final ContentCategory? category;
  final List<String> matched;

  static const clean = ContentFilterResult(flagged: false);
}

/// First-line keyword filter. Use the shared [contentFilter] instance.
class ContentFilter {
  const ContentFilter._();

  // ── Keyword buckets ─────────────────────────────────────────────────────
  //
  // Each entry is matched as a whole word/phrase after the text is lowercased
  // and stripped of diacritics. Multi-word phrases (e.g. "click here to win")
  // are matched as a contiguous sequence with word boundaries on each end.
  // Keep tokens reasonably long and unambiguous to avoid false positives;
  // prefer adding a phrase over a short standalone token.

  /// Violence / gore — graphic, clearly-objectionable terms (IT + EN).
  /// Everyday words like "war"/"guerra" are deliberately excluded to avoid
  /// flagging normal book discussion.
  static const List<String> _violence = [
    // English
    'gore', 'gory', 'decapitate', 'decapitation', 'beheading', 'dismember',
    'dismembered', 'mutilate', 'mutilation', 'disembowel', 'bloodbath',
    'massacre', 'snuff film', 'torture porn',
    // Italian
    'decapitazione', 'decapitare', 'sgozzare', 'sventrare', 'smembrare',
    'smembramento', 'mutilazione', 'massacrare', 'mattanza', 'sgozzato',
  ];

  /// Scam / fraud / phishing markers (IT + EN). Mostly multi-word so they only
  /// fire on the unmistakable shape of a scam, not isolated common words.
  static const List<String> _scam = [
    // English
    'free crypto', 'crypto giveaway', 'bitcoin giveaway', 'double your money',
    'guaranteed profit', 'guaranteed returns', 'wire transfer fee',
    'nigerian prince', 'click here to win', 'you have won', 'claim your prize',
    'verify your account', 'send bitcoin', 'investment opportunity',
    'work from home guaranteed', 'get rich quick', 'phishing',
    // Italian
    'soldi facili', 'guadagno garantito', 'profitto garantito',
    'regalo bitcoin', 'regalo crypto', 'hai vinto un premio', 'hai vinto',
    'verifica il tuo account', 'invia bitcoin', 'guadagna da casa garantito',
    'investimento sicuro', 'arricchirsi subito', 'truffa',
  ];

  /// Sexual / pornographic markers (IT + EN). Clinical/medical and romance
  /// vocabulary is excluded; these are explicit porn / solicitation markers.
  static const List<String> _sexual = [
    // English
    'porn', 'porno', 'pornographic', 'xxx', 'hardcore sex', 'nudes',
    'onlyfans', 'camgirl', 'cumshot', 'blowjob', 'deepthroat', 'creampie',
    'milf', 'sex tape', 'free sex', 'live sex',
    // Italian
    'pornografia', 'pornografico', 'scopare', 'sborra', 'pompino',
    'troia', 'vogliosa', 'sesso gratis', 'sesso in webcam', 'video porno',
  ];

  /// Spam markers (IT + EN). Aggressive promo / engagement-bait shapes.
  static const List<String> _spam = [
    // English
    'buy now', 'limited time offer', 'act now', 'click here', 'subscribe now',
    'follow for follow', 'follow4follow', 'f4f', 'dm me to earn',
    'cheap followers', 'buy followers', 'promo code', 'discount code',
    'visit my website', 'check my bio link', 'make money fast',
    // Italian
    'compra ora', 'offerta limitata', 'iscriviti ora', 'clicca qui',
    'segui per seguire', 'follower gratis', 'compra follower',
    'codice sconto', 'guadagna soldi', 'visita il mio sito',
    'link in bio', 'soldi veloci',
  ];

  // Severity order: a post that hits multiple buckets is reported under the
  // first match here. Violence and scam are treated as most severe.
  static const List<ContentCategory> _orderedCategories = [
    ContentCategory.violence,
    ContentCategory.scam,
    ContentCategory.sexual,
    ContentCategory.spam,
  ];

  List<String> _wordsFor(ContentCategory c) => switch (c) {
        ContentCategory.violence => _violence,
        ContentCategory.scam => _scam,
        ContentCategory.sexual => _sexual,
        ContentCategory.spam => _spam,
      };

  /// Inspects [text] and returns whether it is flagged, the most-severe
  /// matched [ContentCategory], and the list of matched tokens.
  ///
  /// Cheap to call (a handful of regex scans over normalized text); still,
  /// callers that render lists should memoize the result per item rather than
  /// recomputing inside `build`.
  ContentFilterResult inspect(String? text) {
    if (text == null || text.trim().isEmpty) return ContentFilterResult.clean;
    final normalized = _normalize(text);
    if (normalized.isEmpty) return ContentFilterResult.clean;

    ContentCategory? firstCategory;
    final matched = <String>[];

    for (final category in _orderedCategories) {
      for (final keyword in _wordsFor(category)) {
        if (_containsWord(normalized, keyword)) {
          firstCategory ??= category;
          matched.add(keyword);
        }
      }
    }

    if (firstCategory == null) return ContentFilterResult.clean;
    return ContentFilterResult(
      flagged: true,
      category: firstCategory,
      matched: matched,
    );
  }

  /// Convenience: true when [text] trips no bucket.
  bool isClean(String? text) => !inspect(text).flagged;

  // ── Internals ───────────────────────────────────────────────────────────

  /// Lowercase + strip common Latin diacritics so "pornò"/"PORNO" both match
  /// "porno" and accented Italian terms normalize consistently. Also collapses
  /// runs of whitespace so multi-word phrases match across newlines/tabs.
  String _normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      buffer.write(_stripDiacritic(rune));
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Maps a single accented Latin code point to its base letter; returns the
  /// original character otherwise. Covers the accents that appear in Italian
  /// and common European loanwords.
  String _stripDiacritic(int rune) {
    const map = {
      0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a',
      0x00E5: 'a',
      0x00E7: 'c',
      0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
      0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
      0x00F1: 'n',
      0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o', 0x00F6: 'o',
      0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
      0x00FD: 'y', 0x00FF: 'y',
    };
    return map[rune] ?? String.fromCharCode(rune);
  }

  // Cache compiled word-boundary regexes so repeated inspect() calls don't
  // recompile the same pattern. Patterns are built lazily on first use.
  static final Map<String, RegExp> _patternCache = {};

  /// Word-boundary, whole-token containment test on already-normalized text.
  /// Uses `(?<![a-z0-9])TOKEN(?![a-z0-9])` so the token can't be a substring of
  /// a longer alphanumeric word ("scam" won't match "scampo"/"scams" stems),
  /// while still allowing punctuation/spaces around it.
  bool _containsWord(String normalizedText, String keyword) {
    final pattern = _patternCache.putIfAbsent(
      keyword,
      () => RegExp(
        '(?<![a-z0-9])${RegExp.escape(keyword)}(?![a-z0-9])',
        caseSensitive: false,
      ),
    );
    return pattern.hasMatch(normalizedText);
  }
}

/// Shared, dependency-free instance. Import and call directly:
///   `if (contentFilter.inspect(text).flagged) { … }`
const ContentFilter contentFilter = ContentFilter._();
