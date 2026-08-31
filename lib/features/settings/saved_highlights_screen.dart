import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/theme.dart';

/// The reader's private shelf of saved highlights.
///
/// PRIVATE BY CONSTRUCTION, not by a permission check: it renders
/// [favoriteHighlightsProvider], which reads the signed-in user's own rows
/// (local Isar on device, own-user Supabase rows on web) and is never exposed
/// on a profile, in a Jam, or in the feed. There is no "other user" variant of
/// this screen to get wrong — the only way to see someone's saves would be to
/// hold their account.
class SavedHighlightsScreen extends ConsumerWidget {
  const SavedHighlightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(favoriteHighlightsProvider);

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: ScriptaColors.inkMuted),
        title: Text(
          context.l10n.savedHighlightsTitle,
          style: ScriptaTextStyles.sectionTitleClean,
        ),
      ),
      body: savedAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: ScriptaColors.primaryDark,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
        data: (saved) {
          if (saved.isEmpty) return const _EmptySaved();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: saved.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) return _SavedHeader(count: saved.length);
              return _SavedCard(highlight: saved[i - 1]);
            },
          );
        },
      ),
    );
  }
}

/// Count + the reassurance that this list is nobody else's business.
class _SavedHeader extends StatelessWidget {
  const _SavedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.savedHighlightsCount(count),
            style: ScriptaTextStyles.label
                .copyWith(color: ScriptaColors.inkMuted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 13, color: ScriptaColors.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.l10n.savedHighlightsPrivate,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: ScriptaColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard({required this.highlight});

  final Highlight highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = highlight.bookTitle;
    final author = highlight.bookAuthor;

    return Material(
      color: ScriptaColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/highlight/${highlight.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      highlight.content,
                      style: ScriptaTextStyles.highlightBodySmall.copyWith(
                        fontSize: 15.5,
                        height: 1.7,
                      ),
                    ),
                    if (title != null && title.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        author != null && author.isNotEmpty
                            ? '$title · $author'
                            : title,
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          letterSpacing: 0.3,
                          color: ScriptaColors.primaryDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Un-save right here: this is the one screen where the reader is
              // reviewing the pile, so removing has to be one tap away.
              IconButton(
                tooltip: context.l10n.savedHighlightsRemoved,
                icon: const Icon(Icons.bookmark_rounded,
                    size: 20, color: ScriptaColors.primaryDark),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l10n;
                  final saved = await ref
                      .read(highlightFavoriteNotifierProvider.notifier)
                      .toggleFavorite(highlight.id);
                  messenger.showSnackBar(SnackBar(
                    content: Text(saved == null
                        ? l10n.savedHighlightsError
                        : l10n.savedHighlightsRemoved),
                    duration: const Duration(seconds: 2),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySaved extends StatelessWidget {
  const _EmptySaved();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: ScriptaColors.primaryFaint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.bookmark_outline_rounded,
                  size: 30, color: ScriptaColors.primaryDark),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.savedHighlightsEmpty,
              style: ScriptaTextStyles.sectionTitle
                  .copyWith(color: ScriptaColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.savedHighlightsEmptyHint,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.5,
                color: ScriptaColors.inkFaint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
