import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';

// Provider: highlights condivisi nella jam
final jamHighlightsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) => ref.watch(supabaseServiceProvider).fetchJamHighlights(jamId),
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

  Future<void> _shareHighlight() async {
    final highlights = ref.read(allHighlightsProvider);
    final list = highlights.valueOrNull ?? [];

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun highlight disponibile. Importa prima un file Kindle.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surface,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Scegli un highlight da condividere',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final h = list[i];
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final service = ref.read(supabaseServiceProvider);
                      try {
                        await service.shareHighlightInJam(
                          widget.jamId,
                          h.supabaseId.isNotEmpty ? h.supabaseId : '${h.id}',
                        );
                        ref.invalidate(jamHighlightsProvider(widget.jamId));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Highlight condiviso!')),
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
                      child: Text(
                        h.content.length > 120
                            ? '${h.content.substring(0, 120)}…'
                            : h.content,
                        style: MarginaliaTextStyles.highlightBodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
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
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cerchia di lettura',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
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
            backgroundColor: MarginaliaColors.sienna,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),

          // ── Sezione header ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text('HIGHLIGHT', style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.ruleFaint)),
                ],
              ),
            ),
          ),

          // ── Lista highlights ───────────────────────────────────────────────
          jamAsync.when(
            data: (highlights) => highlights.isEmpty
                ? SliverFillRemaining(
                    child: Center(
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
                            child: const Icon(Icons.auto_stories_outlined,
                                size: 28, color: MarginaliaColors.siennaLight),
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
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    sliver: SliverList.builder(
                      itemCount: highlights.length,
                      itemBuilder: (ctx, i) => _JamHighlightCard(
                        data: highlights[i],
                        index: i,
                      ),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna,
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
        onPressed: _shareHighlight,
        backgroundColor: MarginaliaColors.sienna,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Condividi', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ─── Card highlight nella jam ─────────────────────────────────────────────────

class _JamHighlightCard extends StatelessWidget {
  const _JamHighlightCard({required this.data, required this.index});

  final Map<String, dynamic> data;
  final int index;

  @override
  Widget build(BuildContext context) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final content = highlight?['content'] as String? ?? '';
    final book = highlight?['books'] as Map<String, dynamic>?;
    final bookTitle = book?['title'] as String? ?? '';
    final bookAuthor = book?['author'] as String? ?? '';
    final color = highlight?['color'] as String?;
    final profile = data['profiles'] as Map<String, dynamic>?;
    final sharedBy = profile?['display_name'] as String? ?? 'Utente';
    final sharedAt = data['shared_at'] as String?;

    final accentColor = _accentFor(color);

    return Container(
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: MarginaliaColors.siennaFaint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            sharedBy,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.sienna,
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 300.ms);
  }

  Color _accentFor(String? color) => switch (color) {
        'yellow' => const Color(0xFFF59E0B),
        'blue' => const Color(0xFF3B82F6),
        'pink' => const Color(0xFFEC4899),
        'orange' => const Color(0xFFF97316),
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
