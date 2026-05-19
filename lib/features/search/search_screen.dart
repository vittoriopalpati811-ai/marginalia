import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/highlights_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient header with embedded search bar ──────────────────────
          // SafeArea handles the status-bar inset; no manual padding.top needed.
          Container(
            decoration: MarginaliaDecorations.gradientHeader,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        const Text(
                          'Cerca',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF2F5EA),
                            letterSpacing: -0.8,
                            height: 1,
                          ),
                        ),
                        const Spacer(),
                        // Hint badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'highlight · note',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withAlpha(100),
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Search bar (translucent on dark bg)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withAlpha(30), width: 0.5),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFFF2F5EA),
                          height: 1.4,
                        ),
                        cursorColor: const Color(0xFFF2F5EA),
                        decoration: InputDecoration(
                          hintText: 'Cerca nei tuoi highlight…',
                          hintStyle: TextStyle(
                            color: Colors.white.withAlpha(70),
                            fontSize: 15,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.white.withAlpha(80),
                            size: 20,
                          ),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.white.withAlpha(80),
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    ref
                                        .read(searchQueryProvider.notifier)
                                        .state = '';
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (v) =>
                            ref.read(searchQueryProvider.notifier).state = v,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Results ────────────────────────────────────────────────────────
          Expanded(
            child: query.isEmpty
                ? _EmptySearch()
                : resultsAsync.when(
                    data: (highlights) => highlights.isEmpty
                        ? _NoResults(query: query)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Count banner
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 20, 20, 10),
                                child: Row(
                                  children: [
                                    Text(
                                      '${highlights.length} RISULTATI',
                                      style: MarginaliaTextStyles.sectionTitle,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Divider(
                                        color: MarginaliaColors.ruleFaint,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 120),
                                  itemCount: highlights.length,
                                  itemBuilder: (ctx, i) {
                                    final h = highlights[i];
                                    return _SearchResultCard(
                                      highlight: h,
                                      query: query,
                                      onTap: () =>
                                          context.push('/highlight/${h.id}'),
                                      index: i,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        color: MarginaliaColors.sienna,
                        strokeWidth: 1.5,
                      ),
                    ),
                    error: (e, _) => Center(child: Text('$e')),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: MarginaliaColors.siennaFaint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.search,
              size: 28,
              color: MarginaliaColors.siennaLight,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cerca per parola chiave',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Trova qualsiasi frase tra tutti\ni tuoi highlight Kindle.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MarginaliaColors.inkMuted,
              height: 1.65,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── No results state ─────────────────────────────────────────────────────────

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_outlined,
            size: 40,
            color: MarginaliaColors.inkFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessun risultato per "$query"',
            style: const TextStyle(
              color: MarginaliaColors.inkMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Search result card ───────────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.highlight,
    required this.query,
    required this.onTap,
    required this.index,
  });

  final dynamic highlight;
  final String query;
  final VoidCallback onTap;
  final int index;

  String? get _bookTitle {
    try { return highlight.bookTitle as String?; } catch (_) { return null; }
  }

  String? get _bookAuthor {
    try { return highlight.bookAuthor as String?; } catch (_) { return null; }
  }

  String? get _color {
    try { return highlight.color as String?; } catch (_) { return null; }
  }

  Color _accentFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };

  @override
  Widget build(BuildContext context) {
    final title = _bookTitle;
    final author = _bookAuthor;
    final accent = _accentFor(_color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: MarginaliaDecorations.card(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book title + author if available
              if (title != null && title.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: MarginaliaTextStyles.sectionTitle.copyWith(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          color: MarginaliaColors.inkMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (author != null && author.isNotEmpty)
                      Text(
                        author.toUpperCase(),
                        style: MarginaliaTextStyles.bookAuthor.copyWith(
                          fontSize: 8.5,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(height: 0.6, color: MarginaliaColors.ruleFaint),
                const SizedBox(height: 8),
              ],
              // Highlighted excerpt
              _HighlightedText(
                text: highlight.content as String,
                query: query,
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 250.ms, curve: Curves.easeOut);
  }
}

// ─── Testo con match evidenziato ──────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lower.indexOf(lowerQuery);

    if (index < 0) {
      return Text(
        text.length > 160 ? '${text.substring(0, 160)}…' : text,
        style: MarginaliaTextStyles.highlightBodySmall,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final before = text.substring(0, index);
    final match = text.substring(index, index + query.length);
    final after = text.substring(index + query.length);
    final afterTrimmed =
        after.length > 80 ? '${after.substring(0, 80)}…' : after;

    return Text.rich(
      TextSpan(
        children: [
          if (before.length > 40)
            TextSpan(text: '…${before.substring(before.length - 40)}')
          else
            TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(
              backgroundColor: MarginaliaColors.highlightAmber,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
            ),
          ),
          TextSpan(text: afterTrimmed),
        ],
        style: MarginaliaTextStyles.highlightBodySmall,
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}
