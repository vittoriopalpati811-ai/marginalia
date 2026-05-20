import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final postsAsync = ref.watch(_userPostsProvider(widget.userId));
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
                            'Nessun post ancora.',
                            style: GoogleFonts.barlow(
                                color: MarginaliaColors.inkMuted, fontSize: 13),
                          ),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _UserProfilePostCard(post: posts[i]),
                          childCount: posts.length,
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
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
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

// ─── User profile post card (compact Twitter-style) ───────────────────────────

class _UserProfilePostCard extends StatelessWidget {
  const _UserProfilePostCard({required this.post});
  final Map<String, dynamic> post;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24)   return '${diff.inHours}h fa';
    if (diff.inDays < 7)     return '${diff.inDays}g fa';
    return '${(diff.inDays / 7).round()}sett fa';
  }

  @override
  Widget build(BuildContext context) {
    final body      = post['body']        as String?;
    final imageUrl  = post['image_url']   as String?;
    final createdAt = post['created_at']  as String?;
    final likes     = post['likes_count'] as int? ?? 0;
    final highlight = post['highlights']  as Map?;
    final hlContent = highlight?['content'] as String?;
    final hlBook    = highlight?['books']   as Map?;
    final hlTitle   = hlBook?['title']  as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (createdAt != null)
                Text(
                  _timeAgo(createdAt),
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    color: MarginaliaColors.inkFaint,
                  ),
                ),
              if (body != null && body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.barlow(
                    fontSize: 14.5,
                    color: MarginaliaColors.ink,
                    height: 1.6,
                  ),
                ),
              ],
              if (hlContent != null && hlContent.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: MarginaliaColors.ruleFaint, width: 0.8),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hlTitle != null && hlTitle.isNotEmpty)
                        Text(
                          hlTitle.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.inkMuted,
                            letterSpacing: 1.1,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        hlContent.length > 180
                            ? '${hlContent.substring(0, 180)}…'
                            : hlContent,
                        style: const TextStyle(
                          fontSize: 13,
                          color: MarginaliaColors.ink,
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          Image.network(
            imageUrl,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.favorite_border,
                  size: 14, color: MarginaliaColors.inkFaint),
              const SizedBox(width: 4),
              Text(
                '$likes',
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  color: MarginaliaColors.inkFaint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(
          height: 0.5,
          thickness: 0.5,
          color: MarginaliaColors.ruleFaint,
        ),
      ],
    );
  }
}
