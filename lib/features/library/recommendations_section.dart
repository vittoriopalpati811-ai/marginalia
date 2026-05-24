// ─── Book recommendations section ────────────────────────────────────────────
//
// Shared widget used by both LibraryScreen and MyProfileScreen.
//
// Public surface:
//   BookRecommendation           — data class
//   libraryRecommendationsProvider — FutureProvider (TF-IDF + Open Library)
//   LibraryRecommendationsSection  — drop-in ConsumerWidget

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';

// ─── Stop-word list (Italian + English) ──────────────────────────────────────

const _kStopWords = {
  // Italian
  'questo', 'questa', 'questi', 'queste', 'quello', 'quella', 'quelli',
  'quelle', 'anche', 'ancora', 'quando', 'dove', 'come', 'perche',
  'tutto', 'tutta', 'tutti', 'tutte', 'ogni', 'qualcosa', 'qualcuno',
  'sempre', 'senza', 'dopo', 'prima', 'altri', 'altre', 'molto', 'molti',
  'molte', 'poco', 'pochi', 'poche', 'proprio', 'propria', 'propri',
  'essere', 'avere', 'aveva', 'erano', 'hanno', 'stata', 'stato',
  'della', 'delle', 'degli', 'nella', 'nelle', 'negli', 'sulla', 'sulle',
  'sugli', 'dalla', 'dalle', 'dagli', 'mentre', 'dunque', 'quindi',
  'allora', 'invece', 'almeno', 'infatti', 'oppure', 'ovvero', 'ormai',
  'spesso', 'finche', 'poiche', 'adesso', 'stessa',
  // English
  'about', 'after', 'again', 'against', 'being', 'before', 'because',
  'between', 'could', 'during', 'every', 'first', 'great', 'however',
  'large', 'later', 'makes', 'might', 'never', 'often', 'other', 'place',
  'right', 'shall', 'since', 'small', 'still', 'their', 'there', 'these',
  'thing', 'think', 'those', 'three', 'through', 'under', 'until',
  'using', 'where', 'which', 'while', 'whole', 'within', 'without',
  'would', 'years', 'always', 'cannot', 'either', 'almost', 'little',
  'maybe', 'people', 'should', 'things', 'though', 'toward', 'unless',
  'wanted', 'another', 'became', 'become', 'called', 'coming', 'giving',
  'having', 'making', 'moving', 'seemed', 'simply', 'taking', 'trying',
  'turned', 'really', 'rather',
};

List<String> _extractWords(String text) =>
    text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 5 && !_kStopWords.contains(w))
        .toList();

// ─── Country name → Italian ───────────────────────────────────────────────────

const _kCountryIt = {
  'United States': 'Stati Uniti', 'United Kingdom': 'Regno Unito',
  'England': 'Inghilterra', 'France': 'Francia', 'Germany': 'Germania',
  'Italy': 'Italia', 'Spain': 'Spagna', 'Russia': 'Russia',
  'Japan': 'Giappone', 'China': 'Cina', 'India': 'India',
  'Brazil': 'Brasile', 'Argentina': 'Argentina', 'Mexico': 'Messico',
  'Canada': 'Canada', 'Australia': 'Australia', 'Netherlands': 'Olanda',
  'Sweden': 'Svezia', 'Norway': 'Norvegia', 'Denmark': 'Danimarca',
  'Poland': 'Polonia', 'Austria': 'Austria', 'Switzerland': 'Svizzera',
  'Belgium': 'Belgio', 'Greece': 'Grecia', 'Portugal': 'Portogallo',
  'Czech Republic': 'Rep. Ceca', 'Hungary': 'Ungheria', 'Romania': 'Romania',
  'Turkey': 'Turchia', 'Iran': 'Iran', 'Israel': 'Israele',
  'South Africa': 'Sudafrica', 'Egypt': 'Egitto', 'Nigeria': 'Nigeria',
  'Colombia': 'Colombia', 'Chile': 'Cile', 'Peru': 'Perù', 'Cuba': 'Cuba',
  'Ireland': 'Irlanda', 'Scotland': 'Scozia', 'Wales': 'Galles',
};

String _italianCountry(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  return _kCountryIt[raw] ?? raw;
}

// ─── Book recommendation data class ──────────────────────────────────────────

class BookRecommendation {
  const BookRecommendation({
    required this.title,
    required this.author,
    required this.year,
    required this.country,
    required this.description,
    this.themeScore = 0,
  });
  final String title;
  final String author;
  final String year;
  final String country;
  final String description;
  final int themeScore;
}

// ─── Provider ─────────────────────────────────────────────────────────────────
//
// Algorithm:
//   1. Take 30 most-recent highlights → extract top-6 theme words (TF-IDF-like)
//   2. Query Open Library /search.json with those words
//   3. Filter out books already in the user's library (case-insensitive title)
//   4. Fetch /works/{key}.json in parallel → description + country
//   5. Re-rank by "description theme score" (content match, not genre)
//   6. Return top-5

final libraryRecommendationsProvider =
    FutureProvider.autoDispose<List<BookRecommendation>>((ref) async {
  final all     = await ref.watch(allHighlightsProvider.future);
  final myBooks = ref.watch(booksProvider).value ?? [];
  if (all.isEmpty) return [];

  // Sort by addedAt desc, take 30 most recent
  final sorted = List<Highlight>.from(all)
    ..sort((a, b) =>
        (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
  final recent = sorted.take(30).toList();

  // Build word-frequency map
  final wordFreq = <String, int>{};
  for (final h in recent) {
    for (final w in _extractWords(h.content)) {
      wordFreq[w] = (wordFreq[w] ?? 0) + 1;
    }
  }
  if (wordFreq.isEmpty) return [];

  final topWords = (wordFreq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(6)
      .map((e) => e.key)
      .toList();
  final themeWordSet = topWords.toSet();

  // Exclude books already in library
  final myTitlesLower =
      myBooks.map((b) => b.title.toLowerCase().trim()).toSet();

  // Open Library search
  final query     = Uri.encodeQueryComponent(topWords.join(' '));
  final searchUri = Uri.parse(
    'https://openlibrary.org/search.json'
    '?q=$query&limit=25&fields=title,author_name,first_publish_year,key',
  );
  final searchResp = await http
      .get(searchUri, headers: {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 8));
  if (searchResp.statusCode != 200) return [];

  final docs = ((jsonDecode(searchResp.body)
          as Map<String, dynamic>)['docs'] as List<dynamic>?) ??
      [];

  final candidates = <Map<String, dynamic>>[];
  for (final raw in docs) {
    final doc   = raw as Map<String, dynamic>;
    final title = (doc['title'] as String? ?? '').trim();
    if (title.isEmpty || myTitlesLower.contains(title.toLowerCase())) continue;
    candidates.add(doc);
    if (candidates.length >= 8) break;
  }
  if (candidates.isEmpty) return [];

  // Fetch Works API in parallel for description + country
  final enriched = await Future.wait(
    candidates.map((doc) async {
      final title      = (doc['title'] as String? ?? '').trim();
      final authorList =
          (doc['author_name'] as List<dynamic>?)?.cast<String>() ?? [];
      final author     = authorList.isNotEmpty ? authorList.first : '—';
      final year       = (doc['first_publish_year'] as int?)?.toString() ?? '—';
      final key        = doc['key'] as String? ?? '';

      String description = '';
      String country     = '—';
      int    themeScore  = 0;

      if (key.isNotEmpty) {
        try {
          final worksResp = await http
              .get(Uri.parse('https://openlibrary.org$key.json'),
                  headers: {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 5));

          if (worksResp.statusCode == 200) {
            final w = jsonDecode(worksResp.body) as Map<String, dynamic>;

            final rawDesc = w['description'];
            if (rawDesc is String) {
              description = rawDesc;
            } else if (rawDesc is Map<String, dynamic>) {
              description = rawDesc['value'] as String? ?? '';
            }
            if (description.length > 500) {
              description = '${description.substring(0, 500)}…';
            }

            final places =
                (w['subject_places'] as List<dynamic>?)?.cast<String>() ?? [];
            if (places.isNotEmpty) country = _italianCountry(places.first);

            for (final word in _extractWords(description)) {
              if (themeWordSet.contains(word)) themeScore++;
            }
          }
        } catch (_) {
          // Works API unavailable — continue without description
        }
      }

      return BookRecommendation(
        title:       title,
        author:      author,
        year:        year,
        country:     country,
        description: description,
        themeScore:  themeScore,
      );
    }),
  );

  final ranked = List<BookRecommendation>.from(enriched)
    ..sort((a, b) => b.themeScore.compareTo(a.themeScore));
  return ranked.take(5).toList();
});

// ─── Section widget ───────────────────────────────────────────────────────────

class LibraryRecommendationsSection extends ConsumerWidget {
  const LibraryRecommendationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryRecommendationsProvider);

    return async.when(
      loading: () => const _RecommendationsSkeleton(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (books) {
        if (books.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('LIBRI CONSIGLIATI',
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Divider(
                        color: MarginaliaColors.ruleFaint, height: 1),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Selezionati per affinità tematica con i tuoi gusti, non solo per genere. Migliorano man mano che usi l'app.",
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: MarginaliaColors.inkFaint,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ...books.asMap().entries.map(
                    (e) => _RecommendationCard(rec: e.value, index: e.key),
                  ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec, required this.index});
  final BookRecommendation rec;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarginaliaColors.ruleFaint, width: 0.8),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rec.title,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.ink,
              height: 1.3,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            [rec.author, rec.year, rec.country]
                .where((s) => s.isNotEmpty && s != '—')
                .join(' · '),
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: MarginaliaColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 0.7, color: MarginaliaColors.ruleFaint),
          const SizedBox(height: 10),
          Text(
            rec.description.isNotEmpty ? rec.description : 'Trama non disponibile.',
            style: GoogleFonts.ebGaramond(
              fontSize: 14,
              height: 1.65,
              color: rec.description.isNotEmpty
                  ? MarginaliaColors.ink
                  : MarginaliaColors.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    )
        .animate(delay: (index * 80).ms)
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

// ─── Skeleton loader ──────────────────────────────────────────────────────────

class _RecommendationsSkeleton extends StatelessWidget {
  const _RecommendationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LIBRI CONSIGLIATI',
                  style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(
                child:
                    Divider(color: MarginaliaColors.ruleFaint, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < 3; i++)
            Container(
              height: 110,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: MarginaliaColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}
