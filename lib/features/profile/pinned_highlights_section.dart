import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final pinnedHighlightsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, userId) async {
  final svc = ref.read(supabaseServiceProvider);
  return svc.fetchPinnedHighlights(userId);
});

// ─── Section widget (used in MyProfileScreen) ─────────────────────────────────

class PinnedHighlightsSection extends ConsumerWidget {
  const PinnedHighlightsSection({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedAsync = ref.watch(pinnedHighlightsProvider(userId));

    return pinnedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Row(
                children: [
                  Text('IN EVIDENZA', style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(
                      child:
                          Divider(color: MarginaliaColors.ruleFaint, height: 1)),
                  const SizedBox(width: 12),
                  // Edit button
                  GestureDetector(
                    onTap: () => _openEditSheet(context, ref, items, userId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: MarginaliaColors.primary.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined,
                              size: 11, color: MarginaliaColors.sienna),
                          const SizedBox(width: 4),
                          Text(
                            'Modifica',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: MarginaliaColors.sienna,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cards
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Tocca "Modifica" per scegliere fino a 3 highlight da mettere in evidenza.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: MarginaliaColors.inkMuted,
                    height: 1.5,
                  ),
                ),
              )
            else
              ...items.asMap().entries.map((e) {
                final i  = e.key;
                final hl = e.value;
                return _PinnedCard(highlight: hl, index: i);
              }),
          ],
        );
      },
    );
  }

  Future<void> _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> currentPinned,
    String userId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPinnedSheet(
        currentPinned: currentPinned,
        onSave: (ids) async {
          await ref.read(supabaseServiceProvider).updatePinnedHighlights(ids);
          ref.invalidate(pinnedHighlightsProvider(userId));
        },
      ),
    );
  }
}

// ─── Pinned highlight card ────────────────────────────────────────────────────

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({required this.highlight, required this.index});
  final Map<String, dynamic> highlight;
  final int index;

  Color _accentFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.sienna,
      };

  @override
  Widget build(BuildContext context) {
    final content = highlight['content'] as String? ?? '';
    final color   = highlight['color']   as String?;
    final books   = highlight['books']   as Map?;
    final title   = books?['title']  as String?;
    final author  = books?['author'] as String?;
    final accent  = _accentFor(color);
    final excerpt =
        content.length > 180 ? '${content.substring(0, 180)}…' : content;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: MarginaliaDecorations.card(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null && title.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: MarginaliaColors.sienna,
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (author != null && author.isNotEmpty)
                              Text(
                                ' · ${author.toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: MarginaliaColors.inkFaint,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        excerpt,
                        style: MarginaliaTextStyles.highlightBodySmall,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
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
        .fadeIn(duration: 280.ms)
        .slideY(begin: 0.04, end: 0, duration: 280.ms);
  }
}

// ─── Edit pinned sheet ────────────────────────────────────────────────────────

class _EditPinnedSheet extends ConsumerStatefulWidget {
  const _EditPinnedSheet({
    required this.currentPinned,
    required this.onSave,
  });
  final List<Map<String, dynamic>> currentPinned;
  final Future<void> Function(List<String> ids) onSave;

  @override
  ConsumerState<_EditPinnedSheet> createState() => _EditPinnedSheetState();
}

class _EditPinnedSheetState extends ConsumerState<_EditPinnedSheet> {
  late List<String> _selectedIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.currentPinned
        .map((h) => h['id'] as String)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(highlightsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: MarginaliaColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MarginaliaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Highlight in evidenza',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: MarginaliaColors.ink,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Seleziona fino a 3  (${_selectedIds.length}/3)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: MarginaliaColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              await widget.onSave(_selectedIds);
                              if (mounted) Navigator.of(context).pop();
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: MarginaliaColors.primary,
                        foregroundColor: const Color(0xFFF2F5EA),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Color(0xFFF2F5EA)))
                          : const Text('Salva',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const Divider(color: MarginaliaColors.ruleFaint, height: 20),

              // List of all highlights
              Expanded(
                child: allAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: MarginaliaColors.sienna, strokeWidth: 1.5),
                  ),
                  error: (e, _) =>
                      Center(child: Text('Errore: $e')),
                  data: (all) {
                    // Only synced highlights can be pinned (need a supabaseId)
                    final highlights =
                        all.where((h) => h.supabaseId != null).toList();
                    if (highlights.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Sincronizza prima i tuoi highlight per poterli mettere in evidenza.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: MarginaliaColors.inkMuted,
                                fontSize: 14,
                                height: 1.5)),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: highlights.length,
                      separatorBuilder: (_, __) => const Divider(
                          color: MarginaliaColors.ruleFaint,
                          height: 1,
                          indent: 56),
                      itemBuilder: (_, i) {
                        final h      = highlights[i];
                        final id     = h.supabaseId!;
                        final sel    = _selectedIds.contains(id);
                        final maxed  = _selectedIds.length >= 3 && !sel;

                        return ListTile(
                          onTap: maxed
                              ? null
                              : () {
                                  setState(() {
                                    if (sel) {
                                      _selectedIds.remove(id);
                                    } else {
                                      _selectedIds.add(id);
                                    }
                                  });
                                },
                          leading: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: sel
                                  ? MarginaliaColors.primary
                                  : maxed
                                      ? MarginaliaColors.ruleFaint
                                      : MarginaliaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel
                                    ? MarginaliaColors.primary
                                    : MarginaliaColors.rule,
                              ),
                            ),
                            child: sel
                                ? const Icon(Icons.check,
                                    size: 14, color: Color(0xFFF2F5EA))
                                : null,
                          ),
                          title: Text(
                            h.content.length > 100
                                ? '${h.content.substring(0, 100)}…'
                                : h.content,
                            style: TextStyle(
                              fontSize: 13,
                              color: maxed
                                  ? MarginaliaColors.inkFaint
                                  : MarginaliaColors.ink,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: (h.bookTitle?.isNotEmpty ?? false)
                              ? Text(
                                  h.bookTitle!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: MarginaliaColors.sienna,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
