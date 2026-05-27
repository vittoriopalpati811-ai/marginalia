import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import 'posts_timeline.dart';
import 'profile_shared_widgets.dart';

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

final _userPostsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  try {
    return await svc.fetchUserPosts(userId);
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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(_publicProfileProvider(widget.userId));
    final statsAsync = ref.watch(_userStatsProvider(widget.userId));
    final postsAsync = ref.watch(_userPostsProvider(widget.userId));
    final isFollowingAsync = ref.watch(_isFollowingUserProvider(widget.userId));
    final me = ref.read(supabaseServiceProvider).userId;
    final isMe = me == widget.userId;

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(child: Text(context.l10n.profileNotFound));
          }
          final name = profile['display_name'] as String? ?? 'User';
          final readingTitle = profile['currently_reading_title'] as String?;
          final readingAuthor = profile['currently_reading_author'] as String?;
          final avatarUrl = profile['avatar_url'] as String?;
          final coverUrl  = profile['cover_url']  as String?;
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
                  collapseMode: CollapseMode.parallax,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Cover photo or gradient
                      if (coverUrl != null && coverUrl.isNotEmpty)
                        Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: MarginaliaDecorations.gradientHeader,
                          ),
                        )
                      else
                        Container(decoration: MarginaliaDecorations.gradientHeader),
                      // Dark scrim so text stays readable over photos
                      Container(color: const Color(0x55000000)),
                      // Content column: avatar + name + reading status
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Avatar
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(43),
                              border: Border.all(
                                  color: Colors.white.withAlpha(60), width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x40000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(43),
                              child: avatarUrl != null && avatarUrl.isNotEmpty
                                  ? Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _AvatarFallback(
                                        initial: initial,
                                        color: avatarColor,
                                      ),
                                    )
                                  : _AvatarFallback(
                                      initial: initial,
                                      color: avatarColor,
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
                                Flexible(
                                  child: Text(
                                    readingTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withAlpha(160),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ],
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
                                  label: Text(context.l10n.profileFollowingButton),
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
                                  label: Text(context.l10n.profileFollowButton),
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

              // ── Libri del cuore (read-only) ──────────────────────────────
              SliverToBoxAdapter(
                child: Builder(
                  builder: (_) {
                    final raw = profile['favorite_books'];
                    if (raw is! List || (raw as List).isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final favs = raw
                        .whereType<Map>()
                        .map((e) => <String, String>{
                              'title':  e['title']?.toString()  ?? '',
                              'author': e['author']?.toString() ?? '',
                            })
                        .where((m) => m['title']!.isNotEmpty)
                        .take(6)
                        .toList();
                    if (favs.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('LIBRI DEL CUORE',
                                  style: MarginaliaTextStyles.sectionTitle),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Divider(
                                      color: MarginaliaColors.ruleFaint)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FavBooksGrid(favBooks: favs),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Post section header ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Text('POST', style: MarginaliaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Divider(
                            color: MarginaliaColors.ruleFaint, height: 1),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Posts list (Twitter-style) ────────────────────────────────
              postsAsync.when(
                data: (posts) => posts.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                          child: Text(
                            'No posts yet.',
                            style: GoogleFonts.manrope(
                                color: MarginaliaColors.inkMuted, fontSize: 13),
                          ),
                        ),
                      )
                    : SliverToBoxAdapter(
                        child: PostsTimeline(
                          posts: posts,
                          profile: profile,
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
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
              color: MarginaliaColors.sienna, strokeWidth: 1.5),
        ),
        error: (_, __) => Center(
          child: Text(context.l10n.profileErrorLoading,
              style: const TextStyle(color: MarginaliaColors.inkMuted)),
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
          _StatBox(label: context.l10n.profileHighlightsStat, value: stats['highlights'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileSharedStat, value: stats['shared'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileFollowing, value: stats['following'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileFollowers, value: stats['followers'] ?? 0),
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

// ─── Avatar fallback (gradient + initial) ────────────────────────────────────

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initial, required this.color});
  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, MarginaliaColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFFF1EEE7),
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

