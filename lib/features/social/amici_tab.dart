import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Profiles of users the current user follows.
final followingProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchFollowing();
  } catch (_) {
    return [];
  }
});

/// Set of user IDs the current user follows — drives button state.
final followingIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return {};
  try {
    return await svc.fetchFollowingIds();
  } catch (_) {
    return {};
  }
});

/// Jam members not yet followed — friend suggestions.
final suggestionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchFollowingSuggestions();
  } catch (_) {
    return [];
  }
});

// ─── AmiciTab ─────────────────────────────────────────────────────────────────

class AmiciTab extends ConsumerStatefulWidget {
  const AmiciTab({super.key});

  @override
  ConsumerState<AmiciTab> createState() => _AmiciTabState();
}

class _AmiciTabState extends ConsumerState<AmiciTab> {
  // userId → loading state for follow/unfollow button
  final Map<String, bool> _loadingIds = {};

  Future<void> _follow(String targetId) async {
    setState(() => _loadingIds[targetId] = true);
    try {
      await ref.read(supabaseServiceProvider).followUser(targetId);
      ref.invalidate(followingProvider);
      ref.invalidate(followingIdsProvider);
      ref.invalidate(suggestionsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(targetId));
    }
  }

  Future<void> _unfollow(String targetId) async {
    setState(() => _loadingIds[targetId] = true);
    try {
      await ref.read(supabaseServiceProvider).unfollowUser(targetId);
      ref.invalidate(followingProvider);
      ref.invalidate(followingIdsProvider);
      ref.invalidate(suggestionsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(targetId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final followingAsync = ref.watch(followingProvider);
    final followingIdsAsync = ref.watch(followingIdsProvider);
    final suggestionsAsync = ref.watch(suggestionsProvider);

    final followingIds = followingIdsAsync.asData?.value ?? {};

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Seguiti ──────────────────────────────────────────────────────
        followingAsync.when(
          data: (following) => following.isEmpty
              ? const SliverToBoxAdapter(child: SizedBox.shrink())
              : SliverList(
                  delegate: SliverChildListDelegate([
                    _SectionHeader(
                      title: 'SEGUITI',
                      count: following.length,
                    ),
                    ...following.asMap().entries.map((entry) {
                      final i = entry.key;
                      final user = entry.value;
                      final uid = user['id'] as String;
                      return _UserRow(
                        user: user,
                        isFollowing: true,
                        isLoading: _loadingIds[uid] == true,
                        onToggle: () => _unfollow(uid),
                        index: i,
                      );
                    }),
                    const SizedBox(height: 8),
                  ]),
                ),
          loading: () => const SliverToBoxAdapter(
            child: _LoadingSection(),
          ),
          error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),

        // ── Suggeriti ─────────────────────────────────────────────────────
        suggestionsAsync.when(
          data: (suggestions) => suggestions.isEmpty
              ? SliverFillRemaining(
                  child: followingAsync.maybeWhen(
                    data: (f) => f.isEmpty ? _EmptyFriends() : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                )
              : SliverList(
                  delegate: SliverChildListDelegate([
                    _SectionHeader(
                      title: 'SUGGERITI',
                      subtitle: 'Dai tuoi Jam',
                    ),
                    ...suggestions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final user = entry.value;
                      final uid = user['id'] as String;
                      final alreadyFollowing = followingIds.contains(uid);
                      return _UserRow(
                        user: user,
                        isFollowing: alreadyFollowing,
                        isLoading: _loadingIds[uid] == true,
                        onToggle: alreadyFollowing
                            ? () => _unfollow(uid)
                            : () => _follow(uid),
                        index: i,
                      );
                    }),
                    const SizedBox(height: 120),
                  ]),
                ),
          loading: () => const SliverToBoxAdapter(
            child: _LoadingSection(),
          ),
          error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
        ),
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count, this.subtitle});
  final String title;
  final int? count;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: MarginaliaTextStyles.sectionTitle),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
              ),
            ),
          ],
          const Spacer(),
          const Divider(),
        ],
      ),
    );
  }
}

// ─── User row ─────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isFollowing,
    required this.isLoading,
    required this.onToggle,
    required this.index,
  });

  final Map<String, dynamic> user;
  final bool isFollowing;
  final bool isLoading;
  final VoidCallback onToggle;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = user['display_name'] as String? ?? 'Utente';
    final readingTitle = user['currently_reading_title'] as String?;
    final readingAuthor = user['currently_reading_author'] as String?;
    final uid = user['id'] as String?;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = MarginaliaDecorations.bookCoverColor(name);
    final isReading = readingTitle != null && readingTitle.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: GestureDetector(
        onTap: uid != null ? () => context.push('/user/$uid') : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: MarginaliaDecorations.card(),
          child: Row(
          children: [
            // ── Avatar ─────────────────────────────────────────────────
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [avatarColor, MarginaliaColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFFF1EEE7),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Name + reading status ───────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (isReading) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.menu_book_outlined,
                            size: 13, color: MarginaliaColors.sienna),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            readingTitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MarginaliaColors.sienna,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (readingAuthor != null && readingAuthor.isNotEmpty)
                      Text(
                        readingAuthor.toUpperCase(),
                        style: MarginaliaTextStyles.bookAuthor
                            .copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ] else
                    const Text(
                      'Nessun libro in corso',
                      style: TextStyle(
                        fontSize: 12,
                        color: MarginaliaColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Follow / Unfollow button ────────────────────────────────
            SizedBox(
              width: 88,
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: MarginaliaColors.primary,
                        ),
                      ),
                    )
                  : isFollowing
                      ? OutlinedButton(
                          onPressed: onToggle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MarginaliaColors.inkMuted,
                            side: const BorderSide(
                                color: MarginaliaColors.rule),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Smetti'),
                        )
                      : FilledButton(
                          onPressed: onToggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: MarginaliaColors.primary,
                            foregroundColor: const Color(0xFFF1EEE7),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Segui'),
                        ),
            ),
          ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 260.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 260.ms);
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _LoadingSection extends StatelessWidget {
  const _LoadingSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: CircularProgressIndicator(
          color: MarginaliaColors.primary,
          strokeWidth: 1.5,
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFriends extends StatelessWidget {
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
              child: const Icon(Icons.people_outline,
                  size: 32, color: MarginaliaColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Nessun amico ancora',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unisciti a una Jam per trovare\naltri lettori da seguire.',
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
