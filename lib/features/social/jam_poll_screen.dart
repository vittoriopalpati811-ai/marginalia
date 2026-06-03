import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Jam Highlight Poll Screen ────────────────────────────────────────────────

class JamPollScreen extends ConsumerStatefulWidget {
  const JamPollScreen({super.key, required this.jamId});
  final String jamId;

  @override
  ConsumerState<JamPollScreen> createState() => _JamPollScreenState();
}

class _JamPollScreenState extends ConsumerState<JamPollScreen> {
  @override
  Widget build(BuildContext context) {
    final pollsAsync = ref.watch(jamPollsProvider(widget.jamId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.jamPollTitle,
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
            onPressed: _showCreatePollSheet,
            tooltip: context.l10n.jamPollNewPollTooltip,
          ),
        ],
      ),
      body: pollsAsync.when(
        data: (polls) => polls.isEmpty
            ? _EmptyState(onCreate: _showCreatePollSheet)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: polls.length,
                itemBuilder: (_, i) => _PollCard(
                  data: polls[i],
                  currentUserId: currentUser?.id ?? '',
                  onVote: (candidateId) => _vote(polls[i], candidateId),
                  onSubmitCandidate: () => _showSubmitCandidateSheet(polls[i]['id'] as String),
                ).animate(delay: (i * 40).ms).fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: MarginaliaColors.primary, strokeWidth: 1.5),
        ),
        error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
      ),
    );
  }

  Future<void> _vote(Map<String, dynamic> poll, String candidateId) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;
    final candidates = poll['jam_poll_candidates'] as List? ?? [];

    // Check if user already voted
    bool alreadyVoted = false;
    String? myVotedCandidateId;
    for (final c in candidates) {
      final votes = c['jam_poll_votes'] as List? ?? [];
      if (votes.any((v) => v['user_id'] == userId)) {
        alreadyVoted = true;
        myVotedCandidateId = c['id'] as String?;
        break;
      }
    }

    final svc = ref.read(supabaseServiceProvider);
    try {
      if (alreadyVoted && myVotedCandidateId == candidateId) {
        // Toggle off
        await svc.unvoteOnPollCandidate(candidateId);
      } else {
        if (alreadyVoted && myVotedCandidateId != null) {
          await svc.unvoteOnPollCandidate(myVotedCandidateId);
        }
        await svc.voteOnPollCandidate(candidateId);
      }
      ref.invalidate(jamPollsProvider(widget.jamId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    }
  }

  void _showCreatePollSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePollSheet(
        jamId: widget.jamId,
        onCreated: () => ref.invalidate(jamPollsProvider(widget.jamId)),
      ),
    );
  }

  void _showSubmitCandidateSheet(String pollId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubmitCandidateSheet(
        pollId: pollId,
        onSubmitted: () => ref.invalidate(jamPollsProvider(widget.jamId)),
      ),
    );
  }
}

// ─── Poll card ────────────────────────────────────────────────────────────────

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.data,
    required this.currentUserId,
    required this.onVote,
    required this.onSubmitCandidate,
  });

  final Map<String, dynamic> data;
  final String currentUserId;
  final void Function(String) onVote;
  final VoidCallback onSubmitCandidate;

  bool get _isClosed => data['is_closed'] as bool? ?? false;

  @override
  Widget build(BuildContext context) {
    final candidates = data['jam_poll_candidates'] as List? ?? [];
    final title = data['title'] as String? ?? 'Poll';
    final endsAt = DateTime.tryParse(data['ends_at'] as String? ?? '');
    final isExpired = endsAt != null && DateTime.now().isAfter(endsAt);
    final closed = _isClosed || isExpired;

    // Total votes across all candidates
    int totalVotes = 0;
    String? myVotedCandidateId;
    for (final c in candidates) {
      final votes = c['jam_poll_votes'] as List? ?? [];
      totalVotes += votes.length;
      if (votes.any((v) => v['user_id'] == currentUserId)) {
        myVotedCandidateId = c['id'] as String?;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarginaliaColors.rule, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                const Icon(Icons.how_to_vote_outlined, color: MarginaliaColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.ink,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: closed ? MarginaliaColors.surfaceElevated : MarginaliaColors.primaryFaint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    closed ? context.l10n.jamPollStatusClosed : context.l10n.jamPollStatusOpen,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: closed ? MarginaliaColors.inkMuted : MarginaliaColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (endsAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                closed
                    ? context.l10n.jamPollEndedOn('${endsAt.day}/${endsAt.month}/${endsAt.year}')
                    : context.l10n.jamPollEndsOn('${endsAt.day}/${endsAt.month}/${endsAt.year}'),
                style: GoogleFonts.manrope(fontSize: 12, color: MarginaliaColors.inkFaint),
              ),
            ),
          const Divider(height: 1, color: MarginaliaColors.rule),

          // Candidates
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                context.l10n.jamPollNoCandidates,
                style: GoogleFonts.manrope(fontSize: 13, color: MarginaliaColors.inkMuted),
              ),
            )
          else
            ...candidates.asMap().entries.map((entry) {
              final c = entry.value as Map<String, dynamic>;
              final votes = c['jam_poll_votes'] as List? ?? [];
              final voteCount = votes.length;
              final myVote = c['id'] == myVotedCandidateId;
              final fraction = totalVotes > 0 ? voteCount / totalVotes : 0.0;

              return InkWell(
                onTap: closed ? null : () => onVote(c['id'] as String),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '"${c['highlight_content']}"',
                              style: GoogleFonts.ebGaramond(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: MarginaliaColors.ink,
                                height: 1.55,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Vote indicator
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: myVote
                                  ? MarginaliaColors.primary
                                  : MarginaliaColors.primaryFaint,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.favorite_rounded,
                                  size: 12,
                                  color: myVote ? Colors.white : MarginaliaColors.primary,
                                ),
                                Text(
                                  '$voteCount',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: myVote ? Colors.white : MarginaliaColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if ((c['book_title'] as String?) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          (c['book_title'] as String).toUpperCase(),
                          style: MarginaliaTextStyles.bookAuthor.copyWith(fontSize: 10),
                        ),
                      ],
                      // Vote bar
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 4,
                          backgroundColor: MarginaliaColors.primaryFaint,
                          color: myVote ? MarginaliaColors.primary : MarginaliaColors.sienna,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

          // Add candidate button (only if poll is open)
          if (!closed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: OutlinedButton.icon(
                onPressed: onSubmitCandidate,
                icon: const Icon(Icons.add, size: 16),
                label: Text(context.l10n.jamAddYourHighlight),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MarginaliaColors.primary,
                  side: const BorderSide(color: MarginaliaColors.rule),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.how_to_vote_outlined, size: 56, color: MarginaliaColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              context.l10n.jamPollNoPolls,
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: MarginaliaColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.jamPollNoPollsBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: MarginaliaColors.inkMuted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.jamCreatePoll),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create poll sheet ────────────────────────────────────────────────────────

class _CreatePollSheet extends ConsumerStatefulWidget {
  const _CreatePollSheet({required this.jamId, required this.onCreated});
  final String jamId;
  final VoidCallback onCreated;

  @override
  ConsumerState<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends ConsumerState<_CreatePollSheet> {
  final _titleCtrl = TextEditingController();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 7));
  bool _loading = false;
  bool _didSetDefaultTitle = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed the default poll title once, localized. Done here (not in a field
    // initializer) because it needs the inherited l10n from context.
    if (!_didSetDefaultTitle) {
      _didSetDefaultTitle = true;
      _titleCtrl.text = context.l10n.jamPollDefaultTitle;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(supabaseServiceProvider).createPoll(
            jamId: widget.jamId,
            title: _titleCtrl.text.trim(),
            endsAt: _endsAt,
          );
      widget.onCreated();
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
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: MarginaliaColors.rule, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.jamPollNewPollSheetTitle,
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: MarginaliaColors.ink),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(hintText: context.l10n.jamPollTitleFieldHint, prefixIcon: const Icon(Icons.how_to_vote_outlined)),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endsAt,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (picked != null) setState(() => _endsAt = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              context.l10n.jamPollEndsOnLabel('${_endsAt.day}/${_endsAt.month}/${_endsAt.year}'),
              style: GoogleFonts.manrope(fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(context.l10n.jamPollCreateCta),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Submit candidate sheet ───────────────────────────────────────────────────

class _SubmitCandidateSheet extends ConsumerStatefulWidget {
  const _SubmitCandidateSheet({required this.pollId, required this.onSubmitted});
  final String pollId;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_SubmitCandidateSheet> createState() => _SubmitCandidateSheetState();
}

class _SubmitCandidateSheetState extends ConsumerState<_SubmitCandidateSheet> {
  String? _selectedHighlightContent;
  String? _selectedBookTitle;
  String? _selectedBookAuthor;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final highlightsAsync = ref.watch(allHighlightsProvider);
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
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: MarginaliaColors.rule, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.jamPollChooseHighlightTitle,
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: MarginaliaColors.ink),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: highlightsAsync.when(
              data: (highlights) => highlights.isEmpty
                  ? Center(child: Text(context.l10n.jamNoHighlightsAvailable, style: GoogleFonts.manrope(color: MarginaliaColors.inkMuted)))
                  : ListView.builder(
                      itemCount: highlights.length,
                      itemBuilder: (_, i) {
                        final h = highlights[i];
                        final content = h.content as String? ?? '';
                        final selected = _selectedHighlightContent == content;
                        return ListTile(
                          selected: selected,
                          selectedTileColor: MarginaliaColors.primaryFaint,
                          title: Text(
                            '"$content"',
                            style: GoogleFonts.ebGaramond(fontSize: 14, fontStyle: FontStyle.italic),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: h.bookTitle != null
                              ? Text(h.bookTitle as String, style: GoogleFonts.manrope(fontSize: 11, color: MarginaliaColors.inkMuted))
                              : null,
                          onTap: () => setState(() {
                            _selectedHighlightContent = content;
                            _selectedBookTitle = h.bookTitle;
                            _selectedBookAuthor = h.bookAuthor;
                          }),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator(color: MarginaliaColors.primary, strokeWidth: 1.5)),
              error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: (_loading || _selectedHighlightContent == null) ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(context.l10n.jamPollAddToPollCta),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedHighlightContent == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(supabaseServiceProvider).submitPollCandidate(
            pollId: widget.pollId,
            highlightContent: _selectedHighlightContent!,
            bookTitle: _selectedBookTitle,
            bookAuthor: _selectedBookAuthor,
          );
      widget.onSubmitted();
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
}

