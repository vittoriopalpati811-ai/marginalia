import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';

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
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Book of the month',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: MarginaliaColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: MarginaliaColors.primary),
            onPressed: () => _showProposeSheet(),
            tooltip: 'Propose a book',
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
          child: CircularProgressIndicator(color: MarginaliaColors.primary, strokeWidth: 1.5),
        ),
        error: (e, _) => Center(child: Text('$e')),
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
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasVoted
              ? MarginaliaColors.primary.withAlpha(80)
              : MarginaliaColors.rule,
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
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: MarginaliaColors.primary,
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
                      color: MarginaliaColors.ink,
                    ),
                  ),
                  if ((data['author'] as String?) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      (data['author'] as String).toUpperCase(),
                      style: MarginaliaTextStyles.bookAuthor,
                    ),
                  ],
                  if ((data['description'] as String?) != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      data['description'] as String,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: MarginaliaColors.inkMuted,
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
                        'Proposto da $proposerName',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                      const Spacer(),
                      if (onDelete != null)
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: MarginaliaColors.inkFaint,
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
                          ? MarginaliaColors.primary
                          : MarginaliaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.thumb_up_rounded,
                      size: 18,
                      color: hasVoted ? Colors.white : MarginaliaColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$voteCount',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasVoted
                          ? MarginaliaColors.primary
                          : MarginaliaColors.inkMuted,
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
              color: MarginaliaColors.inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'No proposals yet',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Suggest the next book to read together.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: MarginaliaColors.inkMuted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Propose a book'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Propose sheet ────────────────────────────────────────────────────────────

class _ProposeSheet extends ConsumerStatefulWidget {
  const _ProposeSheet({required this.jamId, required this.onProposed});
  final String jamId;
  final VoidCallback onProposed;

  @override
  ConsumerState<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends ConsumerState<_ProposeSheet> {
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(supabaseServiceProvider).proposeBook(
            jamId: widget.jamId,
            title: _titleCtrl.text.trim(),
            author: _authorCtrl.text.trim().isEmpty
                ? null
                : _authorCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
          );
      widget.onProposed();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Propose a book',
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: MarginaliaColors.ink,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(hintText: 'Title *', prefixIcon: Icon(Icons.book_outlined)),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _authorCtrl,
            decoration: const InputDecoration(hintText: 'Author', prefixIcon: Icon(Icons.person_outline)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(hintText: 'Why this book? (optional)'),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Propose'),
            ),
          ),
        ],
      ),
    );
  }
}


