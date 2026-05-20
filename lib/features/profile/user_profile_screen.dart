import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _publicProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  try {
    return await svc.fetchPublicProfile(userId);
  } catch (_) {
    return null;
  }
});

final _userStatsProvider =
    FutureProvider.autoDispose.family<Map<String, int>, String>((ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  try {
    return await svc.fetchUserStats(userId);
  } catch (_) {
    return {'highlights': 0, 'shared': 0, 'following': 0, 'followers': 0};
  }
});

final _userSharedProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  try {
    return await svc.fetchUserSharedHighlights(userId);
  } catch (_) {
    return [];
  }
});

final _isFollowingUserProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return false;
  try {
    final ids = await svc.fetchFollowingIds();
    return ids.contains(userId);
  } catch (_) {
    return false;
  }
});

// ─── UserProfileScreen ────────────────────────────────────────────────────────

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _followLoading = false;

  Future<void> _toggleFollow(bool isFollowing) async {
    setState(() => _followLoading = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      if (isFollowing) {
        await svc.unfollowUser(widget.userId);
      } else {
        await svc.followUser(widget.userId);
      }
      ref.invalidate(_isFollowingUserProvider(widget.userId));
      ref.invalidate(_userStatsProvider(widget.userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(_publicProfileProvider(widget.userId));
    final statsAsync = ref.watch(_userStatsProvider(widget.userId));
    final sharedAsync = ref.watch(_userSharedProvider(widget.userId));
    final isFollowingAsync = ref.watch(_isFollowingUserProvider(widget.userId));
    final me = ref.read(supabaseServiceProvider).userId;
    final isMe = me == widget.userId;

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profilo non trovato.'));
          }
          final name = profile['display_name'] as String? ?? 'Utente';
          final readingTitle = profile['currently_reading_title'] as String?;
          final readingAuthor = profile['currently_reading_author'] as String?;
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          final avatarColor = MarginaliaDecorations.bookCoverColor(name);

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Collapsing gradient header ───────────────────────────────
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: MarginaliaColors.primary,
                foregroundColor: const Color(0xFFF1EEE7),
                elevation: 0,
                scrolledUnderElevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: MarginaliaDecorations.gradientHeader,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Avatar
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [avatarColor, MarginaliaColors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(43),
                            border: Border.all(
                                color: Colors.white.withAlpha(40), width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30000000),
                                blurRadius: 16,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Color(0xFFF1EEE7),
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Name
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFEDE5D5),
                            letterSpacing: -0.4,
                          ),
                        ),
                        // Currently reading
                        if (readingTitle != null && readingTitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.menu_book_outlined,
                                  size: 13, color: Color(0xAAF1EEE7)),
                              const SizedBox(width: 4),
                              Text(
                                readingTitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withAlpha(160),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Stats row ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: statsAsync.when(
                  data: (stats) => _StatsRow(stats: stats),
                  loading: () => const SizedBox(height: 80),
                  error: (_, __) => const SizedBox(height: 80),
                ),
              ),

              // ── Follow button (not shown for self) ───────────────────────
              if (!isMe)
                SliverToBoxAdapter(
                  child: isFollowingAsync.when(
                    data: (isFollowing) => Padding(
                      padding:
                          const EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: _followLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: MarginaliaColors.sienna,
                                  strokeWidth: 1.5))
                          : isFollowing
                              ? OutlinedButton.icon(
                                  onPressed: () => _toggleFollow(true),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Stai seguendo'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: MarginaliaColors.inkMuted,
                                    side: const BorderSide(
                                        color: MarginaliaColors.rule),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: () => _toggleFollow(false),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Segui'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: MarginaliaColors.primary,
                                    foregroundColor: const Color(0xFFF1EEE7),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                ),
                    ),
                    loading: () => const SizedBox(height: 52),
                    error: (_, __) => const SizedBox(height: 52),
                  ),
                ),

              // ── "Condivisi" section header ───────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Text('CONDIVISI NEI JAM',
                          style: MarginaliaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Divider(
                            color: MarginaliaColors.ruleFaint, height: 1),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Shared highlights grid ────────────────────────────────────
              sharedAsync.when(
                data: (items) => items.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              'Nessun highlight condiviso ancora.',
                              style: TextStyle(
                                  color: MarginaliaColors.inkMuted,
                                  fontSize: 14),
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _SharedCell(
                                item: items[i], index: i),
                            childCount: items.length,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.85,
                          ),
                        ),
                      ),
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: MarginaliaColors.sienna, strokeWidth: 1.5),
                    ),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
              color: MarginaliaColors.sienna, strokeWidth: 1.5),
        ),
        error: (_, __) => const Center(
          child: Text('Errore caricamento profilo.',
              style: TextStyle(color: MarginaliaColors.inkMuted)),
        ),
      ),
    );
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final Map<String, int> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: MarginaliaDecorations.card(),
      child: Row(
        children: [
          _StatBox(label: 'Highlight', value: stats['highlights'] ?? 0),
          _Divider(),
          _StatBox(label: 'Condivisi', value: stats['shared'] ?? 0),
          _Divider(),
          _StatBox(label: 'Seguiti', value: stats['following'] ?? 0),
          _Divider(),
          _StatBox(label: 'Follower', value: stats['followers'] ?? 0),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04, end: 0, duration: 350.ms);
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: MarginaliaColors.ruleFaint,
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: MarginaliaColors.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.inkFaint,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared highlight cell (2-col grid) ───────────────────────────────────────

class _SharedCell extends StatelessWidget {
  const _SharedCell({required this.item, required this.index});
  final Map<String, dynamic> item;
  final int index;

  String? get _content {
    try {
      return (item['highlights'] as Map?)?['content'] as String?;
    } catch (_) { return null; }
  }

  String? get _kindleColor {
    try {
      return (item['highlights'] as Map?)?['color'] as String?;
    } catch (_) { return null; }
  }

  String? get _bookTitle {
    try {
      return ((item['highlights'] as Map?)?['books'] as Map?)?['title'] as String?;
    } catch (_) { return null; }
  }

  String? get _jamTitle {
    try {
      return (item['jams'] as Map?)?['title'] as String?;
    } catch (_) { return null; }
  }

  Color _bgFor(String? color, String? title) {
    return switch (color) {
      'yellow' => const Color(0xFFD4A017),
      'blue'   => const Color(0xFF4A90BF),
      'pink'   => const Color(0xFFBF4A72),
      'orange' => const Color(0xFFBF7A34),
      _        => MarginaliaDecorations.bookCoverColor(title ?? ''),
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = _content ?? '';
    final bg = _bgFor(_kindleColor, _bookTitle);
    final dark = Color.fromARGB(255, (bg.red * 0.65).round(),
        (bg.green * 0.65).round(), (bg.blue * 0.65).round());
    final excerpt =
        content.length > 120 ? '${content.substring(0, 120)}…' : content;
    final jamTitle = _jamTitle;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Decorative quote mark
          Positioned(
            top: -6,
            left: 8,
            child: Text(
              '"',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 72,
                height: 0.8,
                color: Colors.white.withAlpha(18),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    excerpt,
                    style: MarginaliaTextStyles.highlightBodyMicro.copyWith(
                      fontSize: 11.5,
                      height: 1.65,
                      color: const Color(0xFFEDE5D5),
                    ),
                    overflow: TextOverflow.fade,
                  ),
                ),
                if (jamTitle != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      jamTitle,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withAlpha(180),
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut);
  }
}
