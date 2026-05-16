import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final feedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchFeed();
  } catch (_) {
    return [];
  }
});

// ─── FeedTab ──────────────────────────────────────────────────────────────────

class FeedTab extends ConsumerWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(supabaseServiceProvider);
    if (!svc.isAuthenticated) return _NotLoggedIn();

    final feedAsync = ref.watch(feedProvider);

    return feedAsync.when(
      data: (items) => items.isEmpty ? _EmptyFeed() : _FeedList(items: items),
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: MarginaliaColors.sienna,
          strokeWidth: 1.5,
        ),
      ),
      error: (_, __) => const Center(
        child: Text(
          'Errore nel caricamento del feed.',
          style: TextStyle(color: MarginaliaColors.inkMuted, fontSize: 14),
        ),
      ),
    );
  }
}

// ─── Feed list ────────────────────────────────────────────────────────────────

class _FeedList extends StatelessWidget {
  const _FeedList({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _FeedCard(item: items[i], index: i),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Feed card ────────────────────────────────────────────────────────────────

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, required this.index});
  final Map<String, dynamic> item;
  final int index;

  String? get _content {
    try {
      return (item['highlights'] as Map?)?['content'] as String?;
    } catch (_) { return null; }
  }

  String? get _bookTitle {
    try {
      return ((item['highlights'] as Map?)?['books'] as Map?)?['title'] as String?;
    } catch (_) { return null; }
  }

  String? get _bookAuthor {
    try {
      return ((item['highlights'] as Map?)?['books'] as Map?)?['author'] as String?;
    } catch (_) { return null; }
  }

  String? get _kindleColor {
    try {
      return (item['highlights'] as Map?)?['color'] as String?;
    } catch (_) { return null; }
  }

  String? get _highlightId {
    try {
      return (item['highlights'] as Map?)?['id'] as String?;
    } catch (_) { return null; }
  }

  String? get _sharedBy => item['shared_by'] as String?;

  String? get _userName {
    try {
      return (item['profile'] as Map?)?['display_name'] as String? ?? 'Utente';
    } catch (_) { return null; }
  }

  String? get _jamTitle {
    try {
      return (item['jams'] as Map?)?['title'] as String?;
    } catch (_) { return null; }
  }

  String? get _jamId {
    try {
      return (item['jams'] as Map?)?['id'] as String?;
    } catch (_) { return null; }
  }

  String? get _sharedAt => item['shared_at'] as String?;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
    return '${(diff.inDays / 7).round()}w fa';
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
    final name = _userName ?? 'Utente';
    final content = _content ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = MarginaliaDecorations.bookCoverColor(name);
    final accent = _accentFor(_kindleColor);
    final timeAgo = _timeAgo(_sharedAt);
    final jamTitle = _jamTitle;
    final jamId = _jamId;
    final bookTitle = _bookTitle;
    final bookAuthor = _bookAuthor;
    final userId = _sharedBy;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── User header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: userId != null
                      ? () => context.push('/user/$userId')
                      : null,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [avatarColor, MarginaliaColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xFFF1EEE7),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: userId != null
                            ? () => context.push('/user/$userId')
                            : null,
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(
                          timeAgo,
                          style: const TextStyle(
                            fontSize: 11,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
                // Jam badge
                if (jamTitle != null)
                  GestureDetector(
                    onTap: jamId != null
                        ? () => context.push('/jam/$jamId?name=${Uri.encodeComponent(jamTitle)}')
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.group_outlined,
                              size: 10, color: MarginaliaColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            jamTitle,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Highlight card ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: MarginaliaColors.surfaceElevated,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Kindle color accent strip
                    Container(width: 3, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Book info
                            if (bookTitle != null && bookTitle.isNotEmpty) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      bookTitle,
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
                                  if (bookAuthor != null && bookAuthor.isNotEmpty)
                                    Text(
                                      ' · ${bookAuthor.toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: MarginaliaColors.inkFaint,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            // Quote
                            Text(
                              content.length > 240
                                  ? '${content.substring(0, 240)}…'
                                  : content,
                              style: MarginaliaTextStyles.highlightBodySmall
                                  .copyWith(fontSize: 13.5, height: 1.75),
                              maxLines: 6,
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
          ),

          const SizedBox(height: 12),
        ],
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 280.ms);
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.dynamic_feed_outlined,
                  size: 32, color: MarginaliaColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Il tuo feed è vuoto',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Segui altri lettori dalla scheda Amici\nper vedere i loro highlight qui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Not logged in state ──────────────────────────────────────────────────────

class _NotLoggedIn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 32, color: MarginaliaColors.siennaLight),
            ),
            const SizedBox(height: 20),
            const Text(
              'Accedi per vedere il feed',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Il feed sociale richiede un account Marginalia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/auth'),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Accedi'),
            ),
          ],
        ),
      ),
    );
  }
}
