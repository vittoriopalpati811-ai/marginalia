import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/models/book.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../library/book_cover.dart';
import '../profile/profile_shared_widgets.dart'
    show favCoversProvider, favCoverKey;

// ─── Jam Book Voting Screen ───────────────────────────────────────────────────

class JamBookVotingScreen extends ConsumerStatefulWidget {
  const JamBookVotingScreen({super.key, required this.jamId});
  final String jamId;

  @override
  ConsumerState<JamBookVotingScreen> createState() =>
      _JamBookVotingScreenState();
}

class _JamBookVotingScreenState extends ConsumerState<JamBookVotingScreen> {
  @override
  Widget build(BuildContext context) {
    final proposalsAsync = ref.watch(bookProposalsProvider(widget.jamId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.jamVoteTitle,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: ScriptaColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: ScriptaColors.primaryDark),
            onPressed: () => _showProposeSheet(),
            tooltip: context.l10n.jamVoteProposeBook,
          ),
        ],
      ),
      body: proposalsAsync.when(
        data: (proposals) => proposals.isEmpty
            ? _EmptyState(onAdd: _showProposeSheet)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: proposals.length,
                itemBuilder: (_, i) => _ProposalCard(
                  data: proposals[i],
                  currentUserId: currentUser?.id,
                  onVote: () => _vote(proposals[i]),
                  onDelete: proposals[i]['proposed_by'] == currentUser?.id
                      ? () => _delete(proposals[i]['id'] as String)
                      : null,
                ).animate(delay: (i * 40).ms).fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: ScriptaColors.primaryDark, strokeWidth: 1.5),
        ),
        error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
      ),
    );
  }

  Future<void> _vote(Map<String, dynamic> proposal) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    final votes = proposal['jam_book_votes'] as List? ?? [];
    final hasVoted = votes.any((v) => v['user_id'] == userId);
    final svc = ref.read(supabaseServiceProvider);
    try {
      if (hasVoted) {
        await svc.unvoteForBook(proposal['id'] as String);
      } else {
        await svc.voteForBook(proposal['id'] as String);
      }
      ref.invalidate(bookProposalsProvider(widget.jamId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    }
  }

  Future<void> _delete(String proposalId) async {
    try {
      await ref.read(supabaseServiceProvider).deleteBookProposal(proposalId);
      ref.invalidate(bookProposalsProvider(widget.jamId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    }
  }

  void _showProposeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposeSheet(
        jamId: widget.jamId,
        onProposed: () => ref.invalidate(bookProposalsProvider(widget.jamId)),
      ),
    );
  }
}

// ─── Proposal card ────────────────────────────────────────────────────────────

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.data,
    required this.currentUserId,
    required this.onVote,
    this.onDelete,
  });

  final Map<String, dynamic> data;
  final String? currentUserId;
  final VoidCallback onVote;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final votes = data['jam_book_votes'] as List? ?? [];
    final voteCount = votes.length;
    final hasVoted = votes.any((v) => v['user_id'] == currentUserId);
    final proposer = data['profiles'] as Map<String, dynamic>?;
    final proposerName = proposer?['display_name'] as String? ??
        proposer?['username'] as String? ?? 'User';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasVoted
              ? ScriptaColors.primary.withAlpha(80)
              : ScriptaColors.rule,
          width: hasVoted ? 1.5 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book cover placeholder
            Container(
              width: 48,
              height: 68,
              decoration: BoxDecoration(
                color: ScriptaColors.primaryFaint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: ScriptaColors.primaryDark,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'] as String? ?? '',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.ink,
                    ),
                  ),
                  if ((data['author'] as String?) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      (data['author'] as String).toUpperCase(),
                      style: ScriptaTextStyles.bookAuthor,
                    ),
                  ],
                  if ((data['description'] as String?) != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      data['description'] as String,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: ScriptaColors.inkMuted,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        context.l10n.jamVoteProposedBy(proposerName),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: ScriptaColors.inkFaint,
                        ),
                      ),
                      const Spacer(),
                      if (onDelete != null)
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: ScriptaColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Vote button
            GestureDetector(
              onTap: onVote,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: 200.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasVoted
                          ? ScriptaColors.primary
                          : ScriptaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.thumb_up_rounded,
                      size: 18,
                      color: hasVoted ? Colors.white : ScriptaColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$voteCount',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasVoted
                          ? ScriptaColors.primaryDark
                          : ScriptaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: ScriptaColors.inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.jamVoteNoProposals,
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: ScriptaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.jamVoteNoProposalsBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: ScriptaColors.inkMuted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.jamProposeBook),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Propose sheet ────────────────────────────────────────────────────────────
//
// The user proposes the book of the month by picking one from their OWN
// library (booksProvider) instead of free-typing title/author. The selected
// book is submitted with the exact same fields the old typed form used —
// proposeBook(jamId, title, author) — so the proposal table is unchanged.
// A search field filters the list by title/author once the library is long.

class _ProposeSheet extends ConsumerStatefulWidget {
  const _ProposeSheet({required this.jamId, required this.onProposed});
  final String jamId;
  final VoidCallback onProposed;

  @override
  ConsumerState<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends ConsumerState<_ProposeSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _propose(Book book) async {
    if (_loading) return;
    setState(() => _loading = true);
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    try {
      // Mirror the original typed-form call exactly: proposeBook only takes
      // jamId/title/author/description. The library book supplies a clean
      // title + author; description stays null (the form's "why" was optional).
      await ref.read(supabaseServiceProvider).proposeBook(
            jamId: widget.jamId,
            title: book.title.trim(),
            author: book.author.trim().isEmpty ? null : book.author.trim(),
            description: null,
          );
      widget.onProposed();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isIt
                ? '"${book.title}" proposto come libro del mese.'
                : '"${book.title}" proposed as book of the month.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isIt
                ? 'Impossibile proporre il libro. Riprova.'
                : 'Could not propose the book. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final booksAsync = ref.watch(booksProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: ScriptaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.jamVoteProposeBook,
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: ScriptaColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isIt
                ? 'Scegli un libro dalla tua libreria.'
                : 'Pick a book from your library.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: ScriptaColors.inkMuted,
            ),
          ),
          const SizedBox(height: 16),
          booksAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(
                    color: ScriptaColors.primaryDark, strokeWidth: 1.5),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                isIt
                    ? 'Impossibile caricare la libreria.'
                    : 'Could not load your library.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 14, color: ScriptaColors.inkMuted),
              ),
            ),
            data: (books) {
              if (books.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      const Icon(Icons.menu_book_outlined,
                          size: 44, color: ScriptaColors.inkFaint),
                      const SizedBox(height: 14),
                      Text(
                        isIt
                            ? 'La tua libreria è vuota.'
                            : 'Your library is empty.',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ScriptaColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isIt
                            ? 'Importa o aggiungi un libro per poterlo proporre.'
                            : 'Import or add a book before you can propose one.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: ScriptaColors.inkMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final filtered = _query.isEmpty
                  ? books
                  : books
                      .where((b) =>
                          b.title.toLowerCase().contains(_query) ||
                          b.author.toLowerCase().contains(_query))
                      .toList();

              return Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search filter — shown once the library is non-trivial.
                    if (books.length > 6) ...[
                      TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: isIt
                              ? 'Cerca per titolo o autore'
                              : 'Search by title or author',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          isIt
                              ? 'Nessun libro corrisponde alla ricerca.'
                              : 'No book matches your search.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                              fontSize: 14, color: ScriptaColors.inkMuted),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _LibraryBookRow(
                            book: filtered[i],
                            enabled: !_loading,
                            onTap: () => _propose(filtered[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Library book row ─────────────────────────────────────────────────────────

class _LibraryBookRow extends ConsumerWidget {
  const _LibraryBookRow({
    required this.book,
    required this.onTap,
    required this.enabled,
  });

  final Book book;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer the reader's custom cover for this book; fall back to any Kindle
    // cover URL on the book, then to the generated doodle.
    final customCover = ref
        .watch(favCoversProvider(null))
        .asData
        ?.value[favCoverKey(book.title, book.author)];
    final coverUrl = (customCover != null && customCover.isNotEmpty)
        ? customCover
        : book.coverUrl;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ScriptaColors.rule, width: 0.8),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 56,
                  child: BookEditorialCover(
                    title: book.title,
                    author: book.author,
                    coverUrl: coverUrl,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ScriptaColors.ink,
                        ),
                      ),
                      if (book.author.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          book.author.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ScriptaTextStyles.bookAuthor,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.add_circle_outline,
                    size: 22, color: ScriptaColors.primaryDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


