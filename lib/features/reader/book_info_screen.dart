import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';
import '../library/book_cover.dart';

/// Lightweight book-detail screen reached by tapping a book's name from a
/// highlight ("frase"). Shows the same kind of info as the AI recommendations —
/// the Marginalia-generated cover, title, author/year, a short overview, the
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

  Future<void> _fetch() async {
    try {
      final terms = <String>[
        if (widget.title.trim().isNotEmpty) 'intitle:${widget.title.trim()}',
        if (widget.author.trim().isNotEmpty) 'inauthor:${widget.author.trim()}',
      ].join(' ');
      final url = Uri.parse(
        'https://www.googleapis.com/books/v1/volumes'
        '?q=${Uri.encodeQueryComponent(terms)}&maxResults=1',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = data['items'] as List?;
        if (items != null && items.isNotEmpty) {
          final vi = (items.first as Map)['volumeInfo'] as Map<String, dynamic>;
          final desc = vi['description'];
          if (desc is String && desc.trim().isNotEmpty) _plot = desc.trim();
          final cats = vi['categories'];
          if (cats is List) {
            _categories = cats.map((e) => e.toString()).take(4).toList();
          }
          final pub = vi['publishedDate'];
          if (pub is String && pub.length >= 4) _year = pub.substring(0, 4);
          final pc = vi['pageCount'];
          if (pc is int && pc > 0) _pages = pc;
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
                style: MarginaliaTextStyles.sectionTitle),
            const SizedBox(width: 12),
            const Expanded(
                child: Divider(color: MarginaliaColors.ruleFaint, height: 1)),
          ]),
        );

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: MarginaliaColors.inkMuted),
        title: Text(
          it ? 'Dettagli libro' : 'Book details',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MarginaliaColors.inkMuted,
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
                      color: MarginaliaColors.ink,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: MarginaliaColors.inkMuted,
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
                    color: MarginaliaColors.sienna, strokeWidth: 1.5),
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
                      color: MarginaliaColors.inkFaint,
                    ),
                  ),
                ),
              ],

              // ── Overview ────────────────────────────────────────────────────
              sectionHeader(it ? 'Trama' : 'Overview'),
              Text(
                _plot ??
                    (it
                        ? 'Trama non disponibile per questo titolo.'
                        : 'No overview available for this title.'),
                style: GoogleFonts.ebGaramond(
                  fontSize: 15.5,
                  height: 1.6,
                  color: _plot != null
                      ? MarginaliaColors.ink
                      : MarginaliaColors.inkFaint,
                ),
              ),

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
                              color: MarginaliaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: MarginaliaColors.ruleFaint,
                                  width: 0.8),
                            ),
                            child: Text(
                              c,
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.inkMuted,
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
