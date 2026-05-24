// ─── HomeTab ──────────────────────────────────────────────────────────────────
//
// Discovery home — three editorial sections:
//   1. "Frase di oggi"   — one contextual highlight, rotates 4× per day
//   2. "Frasi recenti"   — horizontal strip of last 12 saved highlights
//   3. "Scopri"          — new-book recommendations via Open Library API
//
// Algorithm for §3:
//   • Extract the top-4 "theme words" from the 20 most-recent highlights
//     (words ≥5 chars, Italian + English stop-word list, ranked by frequency)
//   • Query Open Library search API with those words
//   • Filter out books the user already has in their library (by title)
//   • Surface up to 5 results with real cover images when available

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/models/highlight.dart';
import '../../core/models/book.dart';
import '../library/book_cover.dart';
import 'feed_tab.dart'; // CreatePostSheet

// ─── Home-scoped providers ────────────────────────────────────────────────────

/// "Frase di oggi" — deterministic, changes 4× a day (6-hour buckets).
final _todayHighlightProvider = FutureProvider.autoDispose<Highlight?>(
  (ref) async {
    final all = await ref.watch(allHighlightsProvider.future);
    if (all.isEmpty) return null;

    // Stable sort (oldest → newest) ensures a consistent index per bucket.
    final stable = List<Highlight>.from(all)
      ..sort((a, b) =>
          (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));

    final now       = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final bucket    = now.hour ~/ 6; // 0=night · 1=morning · 2=afternoon · 3=evening
    final index     = (dayOfYear * 4 + bucket) % stable.length;
    return stable[index];
  },
);

/// Last 12 highlights for the horizontal "recent" strip.
final _recentHighlightsProvider = FutureProvider.autoDispose<List<Highlight>>(
  (ref) async {
    final all = await ref.watch(allHighlightsProvider.future);
    final sorted = List<Highlight>.from(all)
      ..sort((a, b) =>
          (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
    return sorted.take(12).toList();
  },
);

/// Book recommendation data class — sourced from Open Library.
class _BookSuggestion {
  const _BookSuggestion({
    required this.title,
    required this.author,
    this.coverUrl,
  });
  final String title;
  final String author;
  final String? coverUrl; // Open Library cover image URL, nullable
}

/// §3 — New book recommendations via Open Library API.
///
/// Algorithm:
///   1. Extract top-4 theme words from the 20 most-recent highlights.
///   2. Query Open Library: GET /search.json?q=<words>&limit=25.
///   3. Filter out titles already in the user's library (case-insensitive).
///   4. Return first 5 results with cover URL when available.
final _recommendedBooksProvider =
    FutureProvider.autoDispose<List<_BookSuggestion>>(
  (ref) async {
    final all     = await ref.watch(allHighlightsProvider.future);
    final myBooks = ref.watch(booksProvider).value ?? [];
    if (all.isEmpty) return [];

    // 1. Sort by addedAt desc, take 20 most recent highlights
    final sorted = List<Highlight>.from(all)
      ..sort((a, b) =>
          (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
    final recent = sorted.take(20).toList();

    // 2. Build word-frequency map from recent highlight content
    final wordFreq = <String, int>{};
    for (final h in recent) {
      for (final w in _extractWords(h.content)) {
        wordFreq[w] = (wordFreq[w] ?? 0) + 1;
      }
    }
    if (wordFreq.isEmpty) return [];

    // Top-4 most-frequent theme words → search query
    final topWords = (wordFreq.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((e) => e.key)
        .toList();

    // 3. Build set of user's existing book titles (lowercase for comparison)
    final myTitlesLower =
        myBooks.map((b) => b.title.toLowerCase().trim()).toSet();

    // 4. Query Open Library
    final query = Uri.encodeQueryComponent(topWords.join(' '));
    try {
      final uri = Uri.parse(
        'https://openlibrary.org/search.json'
        '?q=$query&limit=25&fields=title,author_name,cover_i',
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final docs  = (body['docs'] as List<dynamic>?) ?? [];

      final results = <_BookSuggestion>[];
      for (final raw in docs) {
        final doc   = raw as Map<String, dynamic>;
        final title = (doc['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        // Skip books the user already owns
        if (myTitlesLower.contains(title.toLowerCase())) continue;

        final authorList =
            (doc['author_name'] as List<dynamic>?)?.cast<String>() ?? [];
        final author  = authorList.isNotEmpty ? authorList.first : '';
        final coverId = doc['cover_i'];
        final coverUrl = coverId != null
            ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
            : null;

        results.add(_BookSuggestion(
          title:    title,
          author:   author,
          coverUrl: coverUrl,
        ));
        if (results.length >= 5) break;
      }
      return results;
    } catch (_) {
      return [];
    }
  },
);

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

// ─── Time-of-day helpers ──────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 6)  return 'Notte fonda';
  if (h < 12) return 'Buongiorno';
  if (h < 18) return 'Buon pomeriggio';
  if (h < 22) return 'Buonasera';
  return 'Buonanotte';
}

String _timeBucketLabel() {
  final h = DateTime.now().hour;
  if (h < 6)  return '🌙 notte';
  if (h < 12) return '🌤 mattina';
  if (h < 18) return '☀️ pomeriggio';
  if (h < 22) return '🌆 sera';
  return '🌙 notte';
}

// ─── HomeTab ──────────────────────────────────────────────────────────────────

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: RefreshIndicator(
        color: MarginaliaColors.primary,
        onRefresh: () async {
          ref.invalidate(allHighlightsProvider);
          ref.invalidate(booksProvider);
          ref.invalidate(_todayHighlightProvider);
          ref.invalidate(_recentHighlightsProvider);
          ref.invalidate(_recommendedBooksProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _HomeHeader(topPadding: top)),
            const SliverToBoxAdapter(child: _TodaySection()),
            const SliverToBoxAdapter(child: _RecentSection()),
            const SliverToBoxAdapter(child: _RecommendedSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.topPadding});
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MarginaliaDecorations.gradientHeader,
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Marginalia', style: MarginaliaTextStyles.wordmarkLight),
                const SizedBox(height: 4),
                Text(
                  _greeting(),
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFF1EEE7).withAlpha(150),
                    fontSize: 13,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => CreatePostSheet(onCreated: () {}),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF1EEE7).withAlpha(28),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFFF1EEE7).withAlpha(50),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: Color(0xFFF1EEE7)),
                  SizedBox(width: 6),
                  Text(
                    'Scrivi',
                    style: TextStyle(
                      color: Color(0xFFF1EEE7),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.tag});
  final String label;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(), style: MarginaliaTextStyles.sectionTitle),
        if (tag != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tag!,
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: MarginaliaColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        const Expanded(
          child: Divider(color: MarginaliaColors.ruleFaint, thickness: 0.8),
        ),
      ],
    );
  }
}

// ─── §1 — Frase di oggi ───────────────────────────────────────────────────────

class _TodaySection extends ConsumerWidget {
  const _TodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_todayHighlightProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: 'Frase di oggi', tag: _timeBucketLabel()),
          const SizedBox(height: 14),
          async.when(
            loading: () => const _TodayCardSkeleton(),
            error:   (_, __) => const _EmptyCard(
              message: 'Nessuna frase disponibile.',
            ),
            data: (highlight) => highlight == null
                ? const _EmptyCard(
                    message: 'Importa i tuoi highlight Kindle per iniziare.',
                  )
                : _TodayHighlightCard(highlight: highlight),
          ),
        ],
      ),
    );
  }
}

class _TodayHighlightCard extends StatelessWidget {
  const _TodayHighlightCard({required this.highlight});
  final Highlight highlight;

  @override
  Widget build(BuildContext context) {
    const cream      = Color(0xFFF5F0E8);
    const creamFaint = Color(0xAAF5F0E8);
    const creamDim   = Color(0x66F5F0E8);

    return Container(
      width: double.infinity,
      decoration: MarginaliaDecorations.heroCard,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: GoogleFonts.ebGaramond(
              fontSize: 56,
              height: 0.72,
              color: const Color(0x44F5F0E8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            highlight.content,
            style: GoogleFonts.ebGaramond(
              fontSize: 17.5,
              height: 1.72,
              color: cream,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.1,
            ),
            maxLines: 9,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          const Divider(color: Color(0x33F5F0E8), thickness: 0.8),
          const SizedBox(height: 10),
          if (highlight.bookTitle?.isNotEmpty ?? false)
            Text(
              highlight.bookTitle!.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: creamFaint,
                letterSpacing: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (highlight.bookAuthor?.isNotEmpty ?? false) ...[
            const SizedBox(height: 3),
            Text(
              highlight.bookAuthor!,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: creamDim,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayCardSkeleton extends StatelessWidget {
  const _TodayCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ─── §2 — Frasi recenti ───────────────────────────────────────────────────────

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recentHighlightsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 28, 16, 14),
          child: _SectionHeader(label: 'Le tue frasi recenti'),
        ),
        async.when(
          loading: () => const _HorizontalSkeleton(),
          error:   (_, __) => const SizedBox.shrink(),
          data: (highlights) {
            if (highlights.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _EmptyCard(message: 'Nessuna frase salvata ancora.'),
              );
            }
            return SizedBox(
              height: 150,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: highlights.length,
                itemBuilder: (_, i) =>
                    _RecentHighlightCard(highlight: highlights[i]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RecentHighlightCard extends StatelessWidget {
  const _RecentHighlightCard({required this.highlight});
  final Highlight highlight;

  static Color _tintColor(String? color) => switch (color) {
        'yellow' => MarginaliaColors.highlightAmber,
        'blue'   => MarginaliaColors.highlightSky,
        'pink'   => MarginaliaColors.highlightRose,
        'orange' => MarginaliaColors.highlightTangerine,
        _        => MarginaliaColors.primaryFaint,
      };

  @override
  Widget build(BuildContext context) {
    final tint = _tintColor(highlight.color);

    return Container(
      width: 192,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withAlpha(38), MarginaliaColors.surface),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              highlight.content,
              style: GoogleFonts.ebGaramond(
                fontSize: 13,
                height: 1.55,
                color: MarginaliaColors.ink,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (highlight.bookTitle ?? '').toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.inkFaint,
              letterSpacing: 0.8,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HorizontalSkeleton extends StatelessWidget {
  const _HorizontalSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          width: 192,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: MarginaliaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─── §3 — Scopri (libri consigliati da Open Library) ─────────────────────────

class _RecommendedSection extends ConsumerWidget {
  const _RecommendedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recommendedBooksProvider);

    return async.when(
      loading: () => const _BooksSkeleton(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (books) {
        if (books.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 28, 16, 4),
              child: _SectionHeader(label: 'Scopri'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Libri simili a quelli che stai leggendo',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: MarginaliaColors.inkFaint,
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: books.length,
                itemBuilder: (_, i) =>
                    _RecommendedBookCard(suggestion: books[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecommendedBookCard extends StatelessWidget {
  const _RecommendedBookCard({required this.suggestion});
  final _BookSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real cover from Open Library, editorial fallback if missing/broken
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 140,
              width: 124,
              child: suggestion.coverUrl != null
                  ? Image.network(
                      suggestion.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => BookEditorialCover(
                        title: suggestion.title,
                        author: suggestion.author,
                      ),
                    )
                  : BookEditorialCover(
                      title: suggestion.title,
                      author: suggestion.author,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.title,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.ink,
              height: 1.3,
              letterSpacing: -0.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (suggestion.author.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              suggestion.author,
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: MarginaliaColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _BooksSkeleton extends StatelessWidget {
  const _BooksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 28, 16, 14),
          child: _SectionHeader(label: 'Scopri'),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            itemBuilder: (_, __) => Container(
              width: 124,
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 140,
                    width: 124,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 90,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 10,
                    width: 60,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.ruleFaint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Generic empty card ───────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MarginaliaColors.ruleFaint, width: 1),
      ),
      child: Column(
        children: [
          Text(
            '“',
            style: GoogleFonts.ebGaramond(
              fontSize: 48,
              height: 0.9,
              color: MarginaliaColors.siennaFaint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: MarginaliaColors.inkFaint,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
