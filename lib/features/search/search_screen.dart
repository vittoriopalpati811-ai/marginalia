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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(fontSize: 16, color: MarginaliaColors.text),
          decoration: const InputDecoration(
            hintText: 'Cerca tra i tuoi highlight…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(color: MarginaliaColors.textMuted),
          ),
          onChanged: (value) =>
              ref.read(searchQueryProvider.notifier).state = value,
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: query.isEmpty
          ? _EmptySearch()
          : resultsAsync.when(
              data: (highlights) => highlights.isEmpty
                  ? const Center(
                      child: Text(
                        'Nessun risultato trovato.',
                        style: TextStyle(color: MarginaliaColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: highlights.length,
                      itemBuilder: (ctx, i) {
                        final h = highlights[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          title: _HighlightedText(
                            text: h.content,
                            query: query,
                          ),
                          subtitle: h.book.value != null
                              ? Text(
                                  h.book.value!.title,
                                  style: MarginaliaTextStyles.bookAuthor,
                                )
                              : null,
                          onTap: () => context.push('/highlight/${h.id}'),
                        ).animate(delay: (i * 30).ms).fadeIn(duration: 200.ms);
                      },
                    ),
              loading: () => const Center(
                child: CircularProgressIndicator(color: MarginaliaColors.accent),
              ),
              error: (e, _) => Center(child: Text('$e')),
            ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, size: 56, color: MarginaliaColors.accentLight),
          const SizedBox(height: 12),
          const Text(
            'Cerca per parola chiave\nnei tuoi highlight',
            textAlign: TextAlign.center,
            style: TextStyle(color: MarginaliaColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// Highlights matching query text in the displayed content
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
        text.length > 120 ? '${text.substring(0, 120)}…' : text,
        style: MarginaliaTextStyles.highlightBodySmall,
        maxLines: 3,
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
              backgroundColor: MarginaliaColors.highlightYellow,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: afterTrimmed),
        ],
        style: MarginaliaTextStyles.highlightBodySmall,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
