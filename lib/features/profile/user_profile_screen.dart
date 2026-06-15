import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../social/report_sheet.dart';
import 'posts_timeline.dart';
import 'profile_shared_widgets.dart';
import 'reviews_tab.dart';
import '../reader/book_info_screen.dart';
import '../library/book_cover.dart';

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
  // Let a failure surface as an ERROR state, not a definitive "not following".
  // The private-profile gate must be able to tell "unknown" from "confirmed not
  // a follower", or a transient network/RLS error would permanently lock a real
  // follower out of a private profile.
  final ids = await svc.fetchFollowingIds();
  return ids.contains(userId);
});

/// Whether the viewed profile is currently blocked by me — drives the
/// Block/Unblock toggle in the overflow menu. Forces a refresh so the state is
/// authoritative when the menu opens.
final _isUserBlockedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return false;
  try {
    final ids = await svc.fetchBlockedUserIds(forceRefresh: true);
    return ids.contains(userId);
  } catch (_) {
    return false;
  }
});

/// The books in [userId]'s library (id/title/author/cover_url), alphabetical.
/// Used by the visited profile's "read books" shelf.
final _userBooksProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, userId) async {
  final svc = ref.watch(supabaseServiceProvider);
  try {
    return await svc.fetchUserBooks(userId);
  } catch (_) {
    return [];
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
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _toggleBlock(bool isBlocked) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final svc = ref.read(supabaseServiceProvider);

    // Blocking is asymmetric/destructive — confirm first. Unblocking is benign,
    // so it applies immediately.
    if (!isBlocked) {
      final confirmed = await confirmBlockUser(context);
      if (!confirmed) return;
    }

    try {
      if (isBlocked) {
        await svc.unblockUser(widget.userId);
      } else {
        await svc.blockUser(widget.userId);
      }
      // Blocking severs the follow edge server-side; refresh everything that
      // depends on block/follow state so the UI reflects it without a reload.
      ref.invalidate(_isUserBlockedProvider(widget.userId));
      ref.invalidate(_isFollowingUserProvider(widget.userId));
      ref.invalidate(_userStatsProvider(widget.userId));
      ref.invalidate(_userPostsProvider(widget.userId));
      messenger.showSnackBar(
        SnackBar(content: Text(isBlocked ? l10n.userUnblocked : l10n.userBlocked)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix('$e'))),
      );
    }
  }

  Future<void> _reportProfile() async {
    await showReportSheet(
      context,
      ref,
      contentType: 'profile',
      contentId: widget.userId,
      reportedUserId: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(_publicProfileProvider(widget.userId));
    final me = ref.read(supabaseServiceProvider).userId;
    final isMe = me == widget.userId;

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return Center(child: Text(context.l10n.profileNotFound));
          }
          return _ProfileBody(
            userId: widget.userId,
            profile: profile,
            isMe: isMe,
            followLoading: _followLoading,
            onToggleFollow: _toggleFollow,
            onToggleBlock: _toggleBlock,
            onReport: _reportProfile,
            isBlockedAsync: ref.watch(_isUserBlockedProvider(widget.userId)),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
              color: ScriptaColors.sienna, strokeWidth: 1.5),
        ),
        error: (_, __) => Center(
          child: Text(context.l10n.profileErrorLoading,
              style: const TextStyle(color: ScriptaColors.inkMuted)),
        ),
      ),
    );
  }
}

// ─── Profile body (cover behind + draggable panel in front) ──────────────────
//
// Restyled to match the book-detail screen and the own-profile hierarchy: the
// cover photo / gradient bleeds full-bleed behind the upper ~40% of the screen,
// and a white rounded DraggableScrollableSheet panel sits in front carrying the
// identity + content. The back button floats over the cover, top-left.

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.userId,
    required this.profile,
    required this.isMe,
    required this.followLoading,
    required this.onToggleFollow,
    required this.onToggleBlock,
    required this.onReport,
    required this.isBlockedAsync,
  });

  final String userId;
  final Map<String, dynamic> profile;
  final bool isMe;
  final bool followLoading;
  final Future<void> Function(bool isFollowing) onToggleFollow;
  final Future<void> Function(bool isBlocked) onToggleBlock;
  final Future<void> Function() onReport;
  final AsyncValue<bool> isBlockedAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_userStatsProvider(userId));
    final postsAsync = ref.watch(_userPostsProvider(userId));
    final isFollowingAsync = ref.watch(_isFollowingUserProvider(userId));

    final name =
        profile['display_name'] as String? ?? context.l10n.profileUserFallback;
    final bio = (profile['bio'] as String?)?.trim();
    final readingTitle = (profile['currently_reading_title'] as String?)?.trim();
    final readingAuthor =
        (profile['currently_reading_author'] as String?)?.trim();
    final avatarUrl = profile['avatar_url'] as String?;
    final coverUrl = profile['cover_url'] as String?;
    final isPrivate = profile['is_private'] == true;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = ScriptaDecorations.bookCoverColor(name);

    // Private gating: hide reading / favourites / posts from non-owners who
    // don't already follow this private profile. The follow button + header
    // (avatar, name, bio, stats) stay visible so they can request access.
    //
    // Gate ONLY when we positively KNOW the viewer is not a follower
    // (asData == false). While the follow check is loading OR if it errors,
    // asData is null → NOT gated, so a real follower is never flashed the
    // "private — follow to see more" lock by a transient unknown. The v1 gate
    // is a soft UX courtesy (profiles stay readable server-side), so erring
    // toward showing content on 'unknown' is the right trade-off.
    final gated =
        isPrivate && !isMe && isFollowingAsync.asData?.value == false;

    final screenH = MediaQuery.of(context).size.height;
    final coverH = screenH * 0.42;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ScriptaDecorations.lightStatusBar,
      child: Stack(
        children: [
          // ── Cover photo / gradient, full-bleed behind the panel ───────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: coverH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl != null && coverUrl.isNotEmpty)
                  Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        decoration: ScriptaDecorations.gradientHeader),
                  )
                else
                  Container(decoration: ScriptaDecorations.gradientHeader),
                // Soft dark scrim at the bottom so the panel edge reads as
                // overlapping the cover, and any text stays legible over photos.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22000000), Color(0x55000000)],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Foreground panel (DraggableScrollableSheet, like book detail) ──
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: 0.66,
              minChildSize: 0.66,
              maxChildSize: 1.0,
              builder: (ctx, scrollCtrl) {
                return Container(
                  decoration: const BoxDecoration(
                    color: ScriptaColors.background,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x20261E1D),
                        blurRadius: 20,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: CustomScrollView(
                    controller: scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // Grab handle
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: ScriptaColors.rule,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),

                      // (1) Avatar + display name
                      SliverToBoxAdapter(
                        child: _IdentityBlock(
                          name: name,
                          avatarUrl: avatarUrl,
                          initial: initial,
                          avatarColor: avatarColor,
                        ),
                      ),

                      // (2) Bio directly under the name
                      if (bio != null && bio.isNotEmpty)
                        SliverToBoxAdapter(child: _BioBlock(bio: bio)),

                      // (3) Stats banner: Highlight | Condivisi | Seguiti | Follower
                      SliverToBoxAdapter(
                        child: statsAsync.when(
                          data: (stats) => _StatsRow(stats: stats),
                          loading: () => const SizedBox(height: 80),
                          error: (_, __) => const SizedBox(height: 80),
                        ),
                      ),

                      // (4) Follow / Following button (not shown for self)
                      if (!isMe)
                        SliverToBoxAdapter(
                          child: isFollowingAsync.when(
                            data: (following) => _FollowButton(
                              isFollowing: following,
                              loading: followLoading,
                              onToggle: onToggleFollow,
                            ),
                            loading: () => const SizedBox(height: 52),
                            error: (_, __) => const SizedBox(height: 52),
                          ),
                        ),

                      // Private-profile gate: stop here for non-followers.
                      if (gated)
                        const SliverToBoxAdapter(child: _PrivateLockRow())
                      else ...[
                        // (5) Currently reading card (when set)
                        if (readingTitle != null && readingTitle.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _CurrentlyReadingCard(
                              title: readingTitle,
                              author: readingAuthor,
                            ),
                          ),

                        // (6) Libri del cuore favourites grid
                        SliverToBoxAdapter(
                          child: _FavouritesSection(
                              profile: profile, userId: userId),
                        ),

                        // (6b) Read books — their library, as a horizontal
                        // shelf; each cover taps through to the book details
                        // (plot, genres…). Wears the owner's custom covers.
                        SliverToBoxAdapter(
                          child: _ReadBooksSection(userId: userId),
                        ),

                        // (6c) Reviews this reader has written (read-only).
                        SliverToBoxAdapter(
                          child: UserReviewsList(userId: userId),
                        ),

                        // (7) Posts timeline
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                            child: Row(
                              children: [
                                Text(context.l10n.profilePostsSection,
                                    style: ScriptaTextStyles.sectionTitle),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Divider(
                                      color: ScriptaColors.ruleFaint, height: 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        postsAsync.when(
                          data: (posts) => posts.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 8, 20, 120),
                                    child: Text(
                                      context.l10n.feedNoPostsYet,
                                      style: GoogleFonts.manrope(
                                          color: ScriptaColors.inkMuted,
                                          fontSize: 13),
                                    ),
                                  ),
                                )
                              : SliverToBoxAdapter(
                                  child: PostsTimeline(
                                    posts: posts,
                                    profile: profile,
                                    // Viewing your OWN profile via /user/:id
                                    // (from notifications, search, chat header…)
                                    // still shows your own hidden like counts.
                                    isOwnProfile: isMe,
                                    onTapPost: (post) =>
                                        context.push('/post/${post['id']}'),
                                  ),
                                ),
                          loading: () => const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: ScriptaColors.sienna,
                                    strokeWidth: 1.5),
                              ),
                            ),
                          ),
                          error: (_, __) =>
                              const SliverToBoxAdapter(child: SizedBox()),
                        ),
                      ],

                      SliverToBoxAdapter(
                        child: SizedBox(
                            height:
                                MediaQuery.of(context).padding.bottom + 32),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Back button (floating, top-left over the cover) ───────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // ── Overflow menu (block / report), top-right over the cover ──────
          if (!isMe)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: _ProfileOverflowMenu(
                isBlockedAsync: isBlockedAsync,
                onToggleBlock: onToggleBlock,
                onReport: onReport,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Identity block (avatar + name) ──────────────────────────────────────────

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.name,
    required this.avatarUrl,
    required this.initial,
    required this.avatarColor,
  });

  final String name;
  final String? avatarUrl;
  final String initial;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(43),
              border: Border.all(color: Colors.white.withAlpha(60), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(43),
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AvatarFallback(
                        initial: initial,
                        color: avatarColor,
                      ),
                    )
                  : _AvatarFallback(initial: initial, color: avatarColor),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }
}

// ─── Bio block ────────────────────────────────────────────────────────────────

class _BioBlock extends StatelessWidget {
  const _BioBlock({required this.bio});
  final String bio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      child: Text(
        bio,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: ScriptaColors.inkMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 40.ms);
  }
}

// ─── Follow button ────────────────────────────────────────────────────────────

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.isFollowing,
    required this.loading,
    required this.onToggle,
  });

  final bool isFollowing;
  final bool loading;
  final Future<void> Function(bool isFollowing) onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: ScriptaColors.sienna, strokeWidth: 1.5))
          : isFollowing
              ? OutlinedButton.icon(
                  onPressed: () => onToggle(true),
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(context.l10n.profileFollowingButton),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ScriptaColors.inkMuted,
                    side: const BorderSide(color: ScriptaColors.rule),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                )
              : FilledButton.icon(
                  onPressed: () => onToggle(false),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(context.l10n.profileFollowButton),
                  style: FilledButton.styleFrom(
                    backgroundColor: ScriptaColors.primary,
                    foregroundColor: const Color(0xFFF1EEE7),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                ),
    );
  }
}

// ─── Private-profile lock row ─────────────────────────────────────────────────

class _PrivateLockRow extends StatelessWidget {
  const _PrivateLockRow();

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 30, color: ScriptaColors.inkFaint),
          const SizedBox(height: 12),
          Text(
            it
                ? 'Profilo privato — segui per vedere di più'
                : 'Private profile — follow to see more',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: ScriptaColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Currently reading card ──────────────────────────────────────────────────

class _CurrentlyReadingCard extends StatelessWidget {
  const _CurrentlyReadingCard({required this.title, this.author});
  final String title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: ScriptaDecorations.card(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            const Icon(Icons.menu_book_outlined,
                size: 20, color: ScriptaColors.primaryDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it ? 'STA LEGGENDO' : 'READING',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.inkFaint,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.ink,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (author != null && author!.isNotEmpty)
                    Text(
                      author!.toUpperCase(),
                      style:
                          ScriptaTextStyles.bookAuthor.copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }
}

// ─── Libri del cuore (read-only favourites grid) ─────────────────────────────

class _FavouritesSection extends StatelessWidget {
  const _FavouritesSection({required this.profile, required this.userId});
  final Map<String, dynamic> profile;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final raw = profile['favorite_books'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final favs = raw
        .whereType<Map>()
        .map((e) => <String, String>{
              'title': e['title']?.toString() ?? '',
              'author': e['author']?.toString() ?? '',
            })
        .where((m) => m['title']!.isNotEmpty)
        .take(6)
        .toList();
    if (favs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.l10n.profileFavouriteBooksSection,
                  style: ScriptaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(child: Divider(color: ScriptaColors.ruleFaint)),
            ],
          ),
          const SizedBox(height: 14),
          // ownerUserId = this profile's user, so visitors see THAT reader's
          // custom favourite covers.
          FavBooksGrid(favBooks: favs, ownerUserId: userId),
        ],
      ),
    );
  }
}

// ─── Read books shelf (their library, horizontal) ────────────────────────────

class _ReadBooksSection extends ConsumerWidget {
  const _ReadBooksSection({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(_userBooksProvider(userId));
    return booksAsync.maybeWhen(
      data: (books) {
        if (books.isEmpty) return const SizedBox.shrink();
        final it = Localizations.localeOf(context).languageCode == 'it';
        // Watch the owner's custom covers ONCE here (during build), not inside
        // the lazy itemBuilder — ref.watch outside build asserts in Riverpod.
        final covers = ref.watch(favCoversProvider(userId)).asData?.value ??
            const <String, String>{};
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(
                  children: [
                    Text(it ? 'LIBRI LETTI' : 'READ BOOKS',
                        style: ScriptaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Divider(color: ScriptaColors.ruleFaint)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: books.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final b = books[i];
                    final title = b['title']?.toString() ?? '';
                    final author = b['author']?.toString() ?? '';
                    if (title.isEmpty) return const SizedBox.shrink();
                    // The owner's custom cover wins, else the stored cover_url,
                    // else the procedural cover — same resolution as everywhere.
                    final custom = covers[favCoverKey(title, author)];
                    final cover = (custom != null && custom.isNotEmpty)
                        ? custom
                        : b['cover_url']?.toString();
                    return _ReadBookTile(
                        title: title, author: author, coverUrl: cover);
                  },
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ReadBookTile extends StatelessWidget {
  const _ReadBookTile(
      {required this.title, required this.author, this.coverUrl});
  final String title;
  final String author;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BookInfoScreen(title: title, author: author, coverUrl: coverUrl),
        ),
      ),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 96,
                height: 132,
                child: BookEditorialCover(
                    title: title, author: author, coverUrl: coverUrl),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.ink,
                height: 1.2,
              ),
            ),
          ],
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: ScriptaDecorations.card(),
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
      color: ScriptaColors.ruleFaint,
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
              color: ScriptaColors.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.inkFaint,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overflow menu (block / unblock / report) ────────────────────────────────

class _ProfileOverflowMenu extends StatelessWidget {
  const _ProfileOverflowMenu({
    required this.isBlockedAsync,
    required this.onToggleBlock,
    required this.onReport,
  });

  final AsyncValue<bool> isBlockedAsync;
  final Future<void> Function(bool isBlocked) onToggleBlock;
  final Future<void> Function() onReport;

  @override
  Widget build(BuildContext context) {
    // Default to "not blocked" while the state loads so the menu is usable.
    final isBlocked = isBlockedAsync.asData?.value ?? false;
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
      ),
      color: ScriptaColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'block') {
          onToggleBlock(isBlocked);
        } else if (v == 'report') {
          onReport();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'block',
          child: Row(
            children: [
              Icon(isBlocked ? Icons.lock_open_outlined : Icons.block,
                  size: 18, color: const Color(0xFFB54848)),
              const SizedBox(width: 10),
              Text(
                isBlocked ? context.l10n.unblockUser : context.l10n.blockUser,
                style: const TextStyle(
                    fontSize: 14, color: ScriptaColors.ink),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'report',
          child: Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 18, color: ScriptaColors.inkMuted),
              const SizedBox(width: 10),
              Text(
                context.l10n.reportUser,
                style: const TextStyle(
                    fontSize: 14, color: ScriptaColors.ink),
              ),
            ],
          ),
        ),
      ],
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
          colors: [color, ScriptaColors.primaryDark],
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
