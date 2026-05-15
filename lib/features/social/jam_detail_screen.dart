import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import 'jam_highlight_detail_screen.dart' show reactionsProvider, commentsProvider, JamHighlightDetailScreen;
import 'weekly_prompt.dart';

// Provider: highlights condivisi nella jam
final jamHighlightsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) => ref.watch(supabaseServiceProvider).fetchJamHighlights(jamId),
);

// Provider: members della jam con profilo (currently_reading)
final jamMembersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) async {
    try {
      return await ref.watch(supabaseServiceProvider).fetchJamMembers(jamId);
    } catch (_) {
      return [];
    }
  },
);

class JamDetailScreen extends ConsumerStatefulWidget {
  const JamDetailScreen({super.key, required this.jamId, required this.jamName});

  final String jamId;
  final String jamName;

  @override
  ConsumerState<JamDetailScreen> createState() => _JamDetailScreenState();
}

class _JamDetailScreenState extends ConsumerState<JamDetailScreen> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    final service = ref.read(supabaseServiceProvider);
    _channel = service.subscribeToJam(widget.jamId, (_) {
      if (mounted) ref.invalidate(jamHighlightsProvider(widget.jamId));
    });
  }

  Future<void> _shareHighlight({String? filterByBookTitle}) async {
    final list = await ref.read(allHighlightsProvider.future);

    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Nessun highlight disponibile. Importa prima un file Kindle.')),
      );
      return;
    }

    // Optional filter: if a book title was suggested, prioritise those highlights
    final filtered = filterByBookTitle != null
        ? list
            .where((h) =>
                (h.bookTitle ?? '').toLowerCase() ==
                filterByBookTitle.toLowerCase())
            .toList()
        : list;
    final showList = filtered.isEmpty ? list : filtered;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                filterByBookTitle != null && filtered.isNotEmpty
                    ? 'I tuoi highlight da "$filterByBookTitle"'
                    : 'Scegli un highlight da condividere',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: showList.length,
                itemBuilder: (_, i) {
                  final h = showList[i];
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final service = ref.read(supabaseServiceProvider);
                      try {
                        await service.shareHighlightInJam(
                          widget.jamId,
                          (h.supabaseId != null && h.supabaseId!.isNotEmpty)
                              ? h.supabaseId!
                              : '${h.id}',
                        );
                        ref.invalidate(jamHighlightsProvider(widget.jamId));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Highlight condiviso!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Errore: $e')),
                          );
                        }
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: MarginaliaDecorations.card(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((h.bookTitle ?? '').isNotEmpty) ...[
                            Text(
                              h.bookTitle!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: MarginaliaColors.sienna,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            h.content.length > 120
                                ? '${h.content.substring(0, 120)}…'
                                : h.content,
                            style: MarginaliaTextStyles.highlightBodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jamAsync = ref.watch(jamHighlightsProvider(widget.jamId));
    final membersAsync = ref.watch(jamMembersProvider(widget.jamId));
    final prompt = WeeklyPrompt.current();

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: MarginaliaDecorations.gradientHeader,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          widget.jamName,
                          style: const TextStyle(
                            color: Color(0xFFF1EEE7),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cerchia di lettura',
                          style: TextStyle(
                            color: const Color(0xFFF1EEE7).withAlpha(180),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              titlePadding: EdgeInsets.zero,
              title: const SizedBox.shrink(),
            ),
            backgroundColor: MarginaliaColors.primary,
            foregroundColor: const Color(0xFFF1EEE7),
            elevation: 0,
            scrolledUnderElevation: 0,
          ),

          // ── Prompt settimanale ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: _WeeklyPromptBanner(prompt: prompt),
          ),

          // ── Membri & currently reading ───────────────────────────────────
          membersAsync.when(
            data: (members) => SliverToBoxAdapter(
              child: _MembersStrip(members: members),
            ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Sezione header ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Text('HIGHLIGHT CONDIVISI',
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Divider(color: MarginaliaColors.rule)),
                ],
              ),
            ),
          ),

          // ── Lista highlights ───────────────────────────────────────────────
          jamAsync.when(
            data: (highlights) => highlights.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyJamHighlights(onShare: _shareHighlight),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    sliver: SliverList.builder(
                      itemCount: highlights.length,
                      itemBuilder: (ctx, i) {
                        final data = highlights[i];
                        return _JamHighlightCard(
                          data: data,
                          index: i,
                          onTap: () => _openDiscussion(data),
                          onMatchTap: (bookTitle) =>
                              _shareHighlight(filterByBookTitle: bookTitle),
                        );
                      },
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.primary,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Errore: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _shareHighlight(),
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        icon: const Icon(Icons.add),
        label: const Text('Condividi',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _openDiscussion(Map<String, dynamic> data) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final book = highlight?['books'] as Map<String, dynamic>?;
    final profile = data['profiles'] as Map<String, dynamic>?;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JamHighlightDetailScreen(
          jamHighlightId: data['id'] as String,
          content: highlight?['content'] as String? ?? '',
          bookTitle: book?['title'] as String? ?? '',
          bookAuthor: book?['author'] as String? ?? '',
          sharedBy: profile?['display_name'] as String? ?? 'Utente',
        ),
      ),
    );
  }
}

// ─── Banner prompt settimanale ────────────────────────────────────────────────

class _WeeklyPromptBanner extends StatelessWidget {
  const _WeeklyPromptBanner({required this.prompt});
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: MarginaliaColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22261E1D),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome,
                color: Color(0xFFF1EEE7), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROMPT DELLA SETTIMANA',
                    style: TextStyle(
                      color: Color(0x99F1EEE7),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prompt,
                    style: const TextStyle(
                      color: Color(0xFFF1EEE7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
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

// ─── Strip membri ─────────────────────────────────────────────────────────────

class _MembersStrip extends StatelessWidget {
  const _MembersStrip({required this.members});
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: members.length,
          itemBuilder: (_, i) {
            final m = members[i];
            final profile = m['profile'] as Map<String, dynamic>?;
            final name = profile?['display_name'] as String? ?? 'Utente';
            final readingTitle =
                profile?['currently_reading_title'] as String?;
            final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7F785B), Color(0xFF4C3B3A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xFFF1EEE7),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 80,
                    child: Text(
                      readingTitle != null && readingTitle.isNotEmpty
                          ? '📖 $readingTitle'
                          : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: MarginaliaColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyJamHighlights extends StatelessWidget {
  const _EmptyJamHighlights({required this.onShare});
  final VoidCallback onShare;

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
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_stories_outlined,
                size: 28, color: MarginaliaColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nessun highlight ancora',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Condividi un tuo highlight\nper avviare la conversazione.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MarginaliaColors.inkMuted,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card highlight nella jam ─────────────────────────────────────────────────

class _JamHighlightCard extends ConsumerWidget {
  const _JamHighlightCard({
    required this.data,
    required this.index,
    required this.onTap,
    required this.onMatchTap,
  });

  final Map<String, dynamic> data;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<String> onMatchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final content = highlight?['content'] as String? ?? '';
    final book = highlight?['books'] as Map<String, dynamic>?;
    final bookTitle = book?['title'] as String? ?? '';
    final bookAuthor = book?['author'] as String? ?? '';
    final color = highlight?['color'] as String?;
    final profile = data['profiles'] as Map<String, dynamic>?;
    final sharedBy = profile?['display_name'] as String? ?? 'Utente';
    final sharedAt = data['shared_at'] as String?;
    final jhId = data['id'] as String? ?? '';

    final accentColor = _accentFor(color);

    // Reactions count
    final reactionsAsync = ref.watch(reactionsProvider(jhId));
    final commentsAsync = ref.watch(commentsProvider(jhId));

    // Match suggestion: do I have other highlights from this book?
    final myHighlightsAsync = ref.watch(allHighlightsProvider);
    final myMatchCount = myHighlightsAsync.maybeWhen(
      data: (list) => list
          .where((h) =>
              (h.bookTitle ?? '').toLowerCase() == bookTitle.toLowerCase())
          .length,
      orElse: () => 0,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: MarginaliaDecorations.card(),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bookTitle.isNotEmpty) ...[
                        Text(
                          bookTitle,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.sienna,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (bookAuthor.isNotEmpty)
                          Text(
                            bookAuthor.toUpperCase(),
                            style: MarginaliaTextStyles.bookAuthor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        content,
                        style: MarginaliaTextStyles.highlightBodySmall,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Footer: condiviso da + data
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.primaryFaint,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              sharedBy,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.primary,
                              ),
                            ),
                          ),
                          if (sharedAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(sharedAt),
                              style: MarginaliaTextStyles.label,
                            ),
                          ],
                          const Spacer(),
                          // Reaction & comment count
                          reactionsAsync.maybeWhen(
                            data: (rxs) => rxs.isEmpty
                                ? const SizedBox.shrink()
                                : _CountChip(
                                    icon: Icons.favorite_outline,
                                    count: rxs.length,
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          commentsAsync.maybeWhen(
                            data: (c) => c.isEmpty
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: _CountChip(
                                      icon: Icons.chat_bubble_outline,
                                      count: c.length,
                                    ),
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      // Match suggestion (only if I have highlights from same book)
                      if (myMatchCount > 0 && bookTitle.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => onMatchTap(bookTitle),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.siennaFaint,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: MarginaliaColors.siennaLight
                                      .withAlpha(80)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome_outlined,
                                    size: 14,
                                    color: MarginaliaColors.sienna),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Hai $myMatchCount ${myMatchCount == 1 ? "citazione" : "citazioni"} da questo libro · Rispondi',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: MarginaliaColors.sienna,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 300.ms);
  }

  Color _accentFor(String? color) => switch (color) {
        'yellow' => const Color(0xFFD4A017),
        'blue' => const Color(0xFF4A90BF),
        'pink' => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _ => MarginaliaColors.siennaLight,
      };

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.count});
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: MarginaliaColors.inkMuted),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.inkMuted,
          ),
        ),
      ],
    );
  }
}
