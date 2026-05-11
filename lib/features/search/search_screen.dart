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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: MarginaliaDecorations.card(radius: 14),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 16,
                          color: MarginaliaColors.ink,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Cerca nei tuoi highlight…',
                          hintStyle: const TextStyle(
                            color: MarginaliaColors.inkFaint,
                            fontSize: 16,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: MarginaliaColors.inkFaint,
                            size: 20,
                          ),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: MarginaliaColors.inkFaint,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    ref.read(searchQueryProvider.notifier).state = '';
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
                  ),
                ],
              ),
            ),

            // ── Risultati ─────────────────────────────────────────────────
            Expanded(
              child: query.isEmpty
                  ? _EmptySearch()
                  : resultsAsync.when(
                      data: (highlights) => highlights.isEmpty
                          ? Center(
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
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
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
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                                    itemCount: highlights.length,
                                    itemBuilder: (ctx, i) {
                                      final h = highlights[i];
                                      return _SearchResultCard(
                                        content: h.content,
                                        query: query,
                                        onTap: () => context.push('/highlight/${h.id}'),
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
              height: 1.6,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card risultato di ricerca ────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.content,
    required this.query,
    required this.onTap,
    required this.index,
  });

  final String content;
  final String query;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: MarginaliaDecorations.card(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _HighlightedText(text: content, query: query),
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
    final afterTrimmed = after.length > 80 ? '${after.substring(0, 80)}…' : after;

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
              backgroundColor: Color(0xFFFFF0C2),
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
