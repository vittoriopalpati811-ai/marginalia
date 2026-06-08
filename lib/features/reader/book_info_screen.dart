import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';
import '../library/book_cover.dart';

/// Lightweight book-detail screen reached by tapping a book's name from a
/// highlight ("frase"). Shows the same kind of info as the AI recommendations —
/// the Scripta-generated cover, title, author/year, a short overview, the
/// categories and page count — but for a book the user already has.
///
/// The overview/metadata is fetched live from the Google Books API (keyless,
/// free). Everything degrades gracefully: if the lookup fails or returns
/// nothing, the cover + title + author still render.
class BookInfoScreen extends StatefulWidget {
  const BookInfoScreen({super.key, required this.title, required this.author});

  final String title;
  final String author;

  @override
  State<BookInfoScreen> createState() => _BookInfoScreenState();
}

class _BookInfoScreenState extends State<BookInfoScreen> {
  bool _loading = true;
  String? _plot;
  List<String> _categories = const [];
  String? _year;
  int? _pages;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// Kindle stores authors as "Surname, Firstname". Flip them to the natural
  /// "Firstname Surname" order that book APIs expect. Anything without a comma
  /// is returned trimmed as-is.
  String _normAuthor(String a) {
    final i = a.indexOf(',');
    if (i < 0) return a.trim();
    final surname = a.substring(0, i).trim();
    final firstname = a.substring(i + 1).trim();
    return [firstname, surname].where((s) => s.isNotEmpty).join(' ');
  }

  /// Reduce a title to its core for matching only: drop a trailing parenthetical
  /// " (...)" and any ":" subtitle. Used to build looser, more forgiving queries.
  String _coreTitle(String t) {
    var core = t;
    final paren = core.indexOf(' (');
    if (paren >= 0) core = core.substring(0, paren);
    final colon = core.indexOf(':');
    if (colon >= 0) core = core.substring(0, colon);
    return core.trim();
  }

  /// Coerce a description/first_sentence value that may be a plain String, a
  /// List of strings, or a {'value': ...} map into a single trimmed String.
  String? _coerceText(dynamic v) {
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is List) {
      final t = v.map((e) => e.toString()).join(' ').trim();
      return t.isEmpty ? null : t;
    }
    if (v is Map && v['value'] != null) {
      final t = v['value'].toString().trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  Future<void> _fetch() async {
    final coreTitle = _coreTitle(widget.title);
    final normAuthor = _normAuthor(widget.author);

    try {
      // ── Google Books: free-text first, intitle: as a fallback ─────────────
      // Stop at the first item that actually carries a description.
      final queries = <String>[
        if (coreTitle.isNotEmpty && normAuthor.isNotEmpty)
          '"$coreTitle" $normAuthor'
        else if (coreTitle.isNotEmpty)
          '"$coreTitle"',
        if (coreTitle.isNotEmpty) 'intitle:$coreTitle',
      ];

      for (final q in queries) {
        if (q.trim().isEmpty) continue;
        if (_plot != null) break;
        try {
          final uri = Uri.https(
            'www.googleapis.com',
            '/books/v1/volumes',
            // Italian only: langRestrict + the IT catalog. The plot must never
            // appear in a foreign language, so we ALSO hard-check
            // volumeInfo.language == 'it' per item below (langRestrict is only a
            // soft hint that Google sometimes ignores).
            {'q': q, 'maxResults': '10', 'langRestrict': 'it', 'country': 'IT'},
          );
          final resp = await http.get(uri).timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) continue;
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final items = data['items'] as List?;
          if (items == null || items.isEmpty) continue;
          for (final item in items) {
            final vi = (item as Map)['volumeInfo'];
            if (vi is! Map) continue;
            // Reject any non-Italian edition — no foreign-language plots.
            final lang = (vi['language'] ?? '').toString().toLowerCase();
            if (lang != 'it') continue;
            final desc = _coerceText(vi['description']);
            if (desc == null) continue;
            // First ITALIAN item with a real description (synopsis) wins.
            _plot = desc;
            final pub = vi['publishedDate'];
            if (pub is String && pub.length >= 4) _year = pub.substring(0, 4);
            final pc = vi['pageCount'];
            if (pc is int && pc > 0) _pages = pc;
            break;
          }
        } catch (_) {
          // Per-attempt failure — try the next query / fallback. Never fatal.
        }
      }

      // ── Open Library: ONLY language-agnostic numeric metadata (pages/year).
      // We deliberately do NOT use it for the plot — first_sentence is a book
      // EXCERPT (often in the original language), not an Italian synopsis. That
      // was the "Spanish excerpt in the plot" bug.
      if (coreTitle.isNotEmpty && (_pages == null || _year == null)) {
        try {
          final uri = Uri.https('openlibrary.org', '/search.json', {
            'title': coreTitle,
            'author': normAuthor,
            'limit': '1',
            'fields': 'number_of_pages_median,first_publish_year',
          });
          final resp = await http.get(uri).timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final docs = data['docs'] as List?;
            if (docs != null && docs.isNotEmpty) {
              final doc = docs.first as Map<String, dynamic>;
              if (_pages == null) {
                final pc = doc['number_of_pages_median'];
                if (pc is int && pc > 0) _pages = pc;
              }
              if (_year == null) {
                final y = doc['first_publish_year'];
                if (y is int && y > 0) _year = y.toString();
              }
            }
          }
        } catch (_) {
          // Open Library best-effort — never fatal.
        }
      }
    } catch (_) {
      // Keyless best-effort lookup — never fatal.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final meta = [widget.author, _year ?? '']
        .where((s) => s.trim().isNotEmpty && s != '—')
        .join(' · ');

    Widget sectionHeader(String label) => Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 10),
          child: Row(children: [
            Text(label.toUpperCase(),
                style: ScriptaTextStyles.sectionTitle),
            const SizedBox(width: 12),
            const Expanded(
                child: Divider(color: ScriptaColors.ruleFaint, height: 1)),
          ]),
        );

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: ScriptaColors.inkMuted),
        title: Text(
          it ? 'Dettagli libro' : 'Book details',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ScriptaColors.inkMuted,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover + title + author/year (centred) ────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(38),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 150,
                        height: 214,
                        child: BookEditorialCover(
                          title: widget.title,
                          author: widget.author,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ebGaramond(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.ink,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: ScriptaColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (_loading) ...[
              const SizedBox(height: 40),
              const Center(
                child: CircularProgressIndicator(
                    color: ScriptaColors.sienna, strokeWidth: 1.5),
              ),
            ] else ...[
              // ── Pages (when known) ─────────────────────────────────────────
              if (_pages != null) ...[
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    '$_pages ${it ? 'pagine' : 'pages'}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.inkFaint,
                    ),
                  ),
                ),
              ],

              // ── Overview (Italian synopsis only; whole section hidden when
              //    no Italian plot is available — no placeholder, dynamic for
              //    any user-added book) ─────────────────────────────────────────
              if (_plot != null) ...[
                sectionHeader(it ? 'Trama' : 'Overview'),
                Text(
                  _plot!,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 15.5,
                    height: 1.6,
                    color: ScriptaColors.ink,
                  ),
                ),
              ],

              // ── Categories ──────────────────────────────────────────────────
              if (_categories.isNotEmpty) ...[
                sectionHeader(it ? 'Categorie' : 'Categories'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .map((c) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: ScriptaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: ScriptaColors.ruleFaint,
                                  width: 0.8),
                            ),
                            child: Text(
                              c,
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: ScriptaColors.inkMuted,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
