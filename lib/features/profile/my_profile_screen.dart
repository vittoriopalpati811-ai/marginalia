import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import 'package:google_fonts/google_fonts.dart';

import 'followers_screen.dart';
import '../social/feed_tab.dart';
import '../library/book_cover.dart';

// ─── Gradient presets ─────────────────────────────────────────────────────────

class _GP {
  const _GP(this.key, this.label, this.a, this.b);
  final String key;
  final String label;
  final Color a;
  final Color b;
  List<Color> get colors => [a, b];
}

const _kGradients = [
  _GP('sepia',    'Seppia',   Color(0xFF6B4C3B), Color(0xFF2C1810)),
  _GP('forest',   'Foresta',  Color(0xFF2D5A3D), Color(0xFF132A1E)),
  _GP('ocean',    'Oceano',   Color(0xFF1A3A5C), Color(0xFF09141F)),
  _GP('dusk',     'Tramonto', Color(0xFF6B3A7A), Color(0xFF1A0B26)),
  _GP('rose',     'Rosa',     Color(0xFF7A3A4E), Color(0xFF2E1020)),
  _GP('graphite', 'Grafite',  Color(0xFF3C3C3C), Color(0xFF141414)),
  _GP('amber',    'Ambra',    Color(0xFF7A4E1A), Color(0xFF2C1A06)),
  _GP('slate',    'Ardesia',  Color(0xFF2A3A4E), Color(0xFF0D141E)),
];

_GP _gpFor(String key) =>
    _kGradients.firstWhere((g) => g.key == key,
        orElse: () => _kGradients.first);

// ─── Pattern keys ─────────────────────────────────────────────────────────────

const _kPatterns = ['none', 'dots', 'lines', 'grid', 'circles'];
const _kPatternLabels = {
  'none':    'Nessuno',
  'dots':    'Punti',
  'lines':   'Linee',
  'grid':    'Griglia',
  'circles': 'Cerchi',
};

// ─── Providers ────────────────────────────────────────────────────────────────

final _myProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return null;
  try { return await svc.fetchPublicProfile(svc.userId!); } catch (_) { return null; }
});

final _myStatsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return {};
  try { return await svc.fetchUserStats(svc.userId!); } catch (_) { return {}; }
});

final _myBooksProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return [];
  try { return await svc.fetchMyBooks(); } catch (_) { return []; }
});

final _mySpotlightProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return null;
  try { return await svc.fetchMyHighlightSpotlight(); } catch (_) { return null; }
});

final _gradientKeyProvider = StateProvider<String>((ref) => 'sepia');
final _patternKeyProvider   = StateProvider<String>((ref) => 'none');

/// Locally selected favourite books (up to 6). Prefilled from profile on load.
/// Each entry: {title, author}.
final _favBooksProvider = StateProvider<List<Map<String, String>>>((ref) => []);

final _myPostsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return [];
  try { return await svc.fetchUserPosts(svc.userId!); } catch (_) { return []; }
});

// ─── MyProfileScreen ──────────────────────────────────────────────────────────

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  // ── Navigate to edit profile page ─────────────────────────────────────────

  void _openEditProfile(Map<String, dynamic>? profile, String gradKey, String patKey) {
    context.push('/edit-profile', extra: {
      'profile':  profile,
      'gradient': gradKey,
      'pattern':  patKey,
      'onSaved':  () {
        ref.invalidate(_myProfileProvider);
        ref.invalidate(_myBooksProvider);
      },
    });
  }

  // ── Share profile ─────────────────────────────────────────────────────────

  void _shareProfile(Map<String, dynamic>? profile) {
    final name = profile?['display_name'] as String? ?? 'Marginalia';
    final uid  = ref.read(supabaseServiceProvider).userId ?? '';
    Share.share(
      '📚 Segui $name su Marginalia!\n\nhttps://marginalia.app/user/$uid',
      subject: 'Profilo Marginalia – $name',
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(supabaseServiceProvider);
    if (!svc.isAuthenticated) return const _NotLoggedIn();

    final profileAsync = ref.watch(_myProfileProvider);
    final statsAsync   = ref.watch(_myStatsProvider);
    final booksAsync   = ref.watch(_myBooksProvider);
    final spotAsync    = ref.watch(_mySpotlightProvider);
    final postsAsync   = ref.watch(_myPostsProvider);
    final gradKey      = ref.watch(_gradientKeyProvider);
    final patKey       = ref.watch(_patternKeyProvider);

    // Sync appearance from Supabase profile whenever the profile data arrives.
    // Using ref.listen so it fires on every load (initial + after invalidation),
    // immediately updating the StateProviders without a microtask delay.
    ref.listen<AsyncValue<Map<String, dynamic>?>>(_myProfileProvider,
        (_, next) {
      next.whenData((p) {
        if (p == null || !mounted) return;
        final newGrad = p['gradient_preset'] as String? ?? 'sepia';
        final newPat  = p['pattern_preset']  as String? ?? 'none';
        if (ref.read(_gradientKeyProvider) != newGrad) {
          ref.read(_gradientKeyProvider.notifier).state = newGrad;
        }
        if (ref.read(_patternKeyProvider) != newPat) {
          ref.read(_patternKeyProvider.notifier).state = newPat;
        }
        // Seed favourite books from profile (migration 024).
        final raw = p['favorite_books'];
        if (raw is List && ref.read(_favBooksProvider).isEmpty) {
          final favs = raw
              .whereType<Map>()
              .map((e) => {
                    'title':  e['title']?.toString()  ?? '',
                    'author': e['author']?.toString() ?? '',
                  })
              .where((m) => m['title']!.isNotEmpty)
              .take(6)
              .toList();
          if (favs.isNotEmpty) {
            ref.read(_favBooksProvider.notifier).state = favs;
          }
        }
      });
    });

    final gp    = _gpFor(gradKey);
    final uid   = svc.userId ?? '';
    final stats = statsAsync.asData?.value ?? {};

    // Blend the gradient colors very subtly into the cream background so the
    // whole page feels cohesive while text on cards stays perfectly readable.
    final bgTop    = Color.alphaBlend(gp.a.withAlpha(28), MarginaliaColors.background);
    final bgBottom = Color.alphaBlend(gp.b.withAlpha(45), MarginaliaColors.background);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Subtle full-page gradient background ─────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [bgTop, bgBottom],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // ── Very faint pattern tint (only where no card is on top) ──────
          if (patKey != 'none')
            CustomPaint(
              painter: _PatternPainter(patKey, color: gp.a.withAlpha(14)),
            ),

          // ── Scrollable content ───────────────────────────────────────────
          RefreshIndicator(
            color: MarginaliaColors.sienna,
            onRefresh: () async {
              ref.invalidate(_myProfileProvider);
              ref.invalidate(_myBooksProvider);
              ref.invalidate(_myStatsProvider);
              ref.invalidate(_myPostsProvider);
              ref.invalidate(_mySpotlightProvider);
              ref.read(_favBooksProvider.notifier).state = [];
            },
            child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [

          // ── Gradient hero header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _ProfileHeader(
              profileAsync: profileAsync,
              gp: gp,
              patternKey: patKey,
              onEditProfile: () =>
                  _openEditProfile(profileAsync.asData?.value, gradKey, patKey),
              onSettings: () => context.push('/account'),
              onShare: () => _shareProfile(profileAsync.asData?.value),
            ),
          ),

          // ── Stats row ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: statsAsync.when(
              data: (s) => _StatsRow(
                stats: s,
                booksCount: booksAsync.asData?.value?.length ?? 0,
                onFollowers: () => showProfileList(context,
                    userId: uid,
                    type: ProfileListType.followers,
                    count: stats['followers'] ?? 0),
                onFollowing: () => showProfileList(context,
                    userId: uid,
                    type: ProfileListType.following,
                    count: stats['following'] ?? 0),
                onBooks: () => showProfileList(context,
                    userId: uid,
                    type: ProfileListType.books,
                    count: booksAsync.asData?.value?.length ?? 0),
              ),
              loading: () => const SizedBox(height: 80),
              error: (_, __) => const SizedBox(height: 80),
            ),
          ),

          // ── Currently reading ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: profileAsync.when(
              data: (p) {
                final title  = p?['currently_reading_title']  as String?;
                final author = p?['currently_reading_author'] as String?;
                if (title == null || title.isEmpty) return const SizedBox.shrink();
                return _CurrentlyReadingCard(title: title, author: author, gp: gp);
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          // ── Spotlight highlight ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: spotAsync.when(
              data: (hl) => hl == null
                  ? const SizedBox.shrink()
                  : _SpotlightCard(highlight: hl, gp: gp),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          // ── Libri del cuore ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _FavoriteBooksSection(
              favBooks: ref.watch(_favBooksProvider),
              allBooks: booksAsync.asData?.value ?? [],
              onEdit: () => _openFavBooksSheet(
                context,
                allBooks: booksAsync.asData?.value ?? [],
                current: ref.read(_favBooksProvider),
                onSave: (picked) async {
                  ref.read(_favBooksProvider.notifier).state = picked;
                  try {
                    await ref
                        .read(supabaseServiceProvider)
                        .updateFavoriteBooks(picked);
                  } catch (_) {} // silent — migration may not be applied yet
                },
              ),
            ),
          ),

          // ── I miei post ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Row(
                children: [
                  Text('POST', style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.ruleFaint)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CreatePostSheet(
                        onCreated: () => ref.invalidate(_myPostsProvider),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: MarginaliaColors.primary.withAlpha(50),
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        'Scrivi',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: MarginaliaColors.primary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          postsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna, strokeWidth: 1.5)),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (posts) => posts.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Text(
                        'Non hai ancora pubblicato nessun post.',
                        style: GoogleFonts.manrope(
                          color: MarginaliaColors.inkMuted, fontSize: 13),
                      ),
                    ),
                  )
                : SliverToBoxAdapter(
                    child: _PostsGrid(
                      posts: posts,
                    ),
                  ),
          ),

          // ── Libreria header + books grid (single booksAsync.when to avoid
          //    duplicate render when the provider rebuilds) ──────────────────
          booksAsync.when(
            data: (books) => books.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                          child: Row(
                            children: [
                              Text('LIBRERIA',
                                  style: MarginaliaTextStyles.sectionTitle),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Divider(
                                      color: MarginaliaColors.ruleFaint)),
                            ],
                          ),
                        ),
                        // Grid (shrinkWrap inside SliverToBoxAdapter is fine for
                        // the small number of books on a profile page)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          child: GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.62,
                            children: books
                                .asMap()
                                .entries
                                .map((e) =>
                                    _BookCell(book: e.value, index: e.key))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: CircularProgressIndicator(
                      color: MarginaliaColors.sienna, strokeWidth: 1.5),
                ),
              ),
            ),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      ), // CustomScrollView
          ), // RefreshIndicator
        ], // Stack children
      ), // Stack
    );
  }

}

// ─── Profile header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profileAsync,
    required this.gp,
    required this.patternKey,
    required this.onEditProfile,
    required this.onSettings,
    required this.onShare,
  });

  final AsyncValue<Map<String, dynamic>?> profileAsync;
  final _GP gp;
  final String patternKey;
  final VoidCallback onEditProfile;
  final VoidCallback onSettings;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final top       = MediaQuery.of(context).padding.top;
    final p         = profileAsync.asData?.value;
    final name      = p?['display_name'] as String? ?? '';
    final bio       = p?['bio'] as String?;
    final avatarUrl = p?['avatar_url'] as String?;
    final coverUrl  = p?['cover_url'] as String?;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarTint = MarginaliaDecorations.bookCoverColor(name);

    return SizedBox(
      height: 290 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: cover photo OR gradient ───────────────────────────
          Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                Image.network(coverUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gp.colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ))
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gp.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

              // Pattern overlay
              if (patternKey != 'none')
                CustomPaint(painter: _PatternPainter(patternKey)),
            ],
          ),

          // Bottom fade
          Positioned(
            left: 0, right: 0, bottom: 0, height: 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withAlpha(55)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Avatar + text
          Positioned(
            left: 24, right: 24, bottom: 28,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Avatar ─────────────────────────────────────────────────
                Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [avatarTint, gp.b],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(39),
                          border: Border.all(
                              color: Colors.white.withAlpha(60), width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x45000000),
                                blurRadius: 20,
                                offset: Offset(0, 4)),
                          ],
                        ),
                        child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      width: 78,
                                      height: 78,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(initial,
                                            style: const TextStyle(
                                              color: Color(0xFFF1EEE7),
                                              fontSize: 30,
                                              fontWeight: FontWeight.w800,
                                            )),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(initial,
                                        style: const TextStyle(
                                          color: Color(0xFFF1EEE7),
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        )),
                                  ),
                        ),
                const SizedBox(width: 16),

                // Name + bio
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.isEmpty ? 'Il tuo profilo' : name,
                        style: const TextStyle(
                          color: Color(0xFFEDE5D5),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bio,
                          style: TextStyle(
                            color: Colors.white.withAlpha(160),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Top-right buttons (modifica · share · settings)
          Positioned(
            top: top + 8,
            right: 14,
            child: Row(
              children: [
                _IconBtn(
                    icon: Icons.edit_outlined,
                    onTap: onEditProfile,
                    tooltip: 'Modifica profilo'),
                const SizedBox(width: 8),
                _IconBtn(
                    icon: Icons.ios_share_outlined,
                    onTap: onShare,
                    tooltip: 'Condividi profilo'),
                const SizedBox(width: 8),
                _IconBtn(
                    icon: Icons.settings_outlined,
                    onTap: onSettings,
                    tooltip: 'Impostazioni'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: Icon(icon, color: Colors.white.withAlpha(210), size: 17),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.booksCount,
    required this.onFollowers,
    required this.onFollowing,
    required this.onBooks,
  });
  final Map<String, int> stats;
  final int booksCount;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;
  final VoidCallback onBooks;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: MarginaliaDecorations.card(),
      child: Row(
        children: [
          _StatBox(label: 'Libri', value: booksCount, onTap: onBooks),
          _Div(),
          _StatBox(label: 'Highlight', value: stats['highlights'] ?? 0),
          _Div(),
          _StatBox(label: 'Seguiti', value: stats['following'] ?? 0, onTap: onFollowing),
          _Div(),
          _StatBox(label: 'Follower', value: stats['followers'] ?? 0, onTap: onFollowers),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04, end: 0, duration: 350.ms);
  }
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: MarginaliaColors.ruleFaint);
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: onTap != null
                    ? MarginaliaColors.sienna
                    : MarginaliaColors.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: onTap != null
                    ? MarginaliaColors.siennaLight
                    : MarginaliaColors.inkFaint,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Currently reading card ───────────────────────────────────────────────────

class _CurrentlyReadingCard extends StatelessWidget {
  const _CurrentlyReadingCard(
      {required this.title, required this.author, required this.gp});
  final String title;
  final String? author;
  final _GP gp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: MarginaliaDecorations.card(),
        child: Row(
          children: [
            // Colour spine
            Container(
              width: 4,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: gp.colors,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14)),
              ),
            ),
            const SizedBox(width: 14),
            const Icon(Icons.menu_book_outlined,
                size: 20, color: MarginaliaColors.sienna),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IN LETTURA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.inkFaint,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.ink,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (author != null && author!.isNotEmpty)
                    Text(
                      author!.toUpperCase(),
                      style: MarginaliaTextStyles.bookAuthor
                          .copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }
}

// ─── Spotlight highlight card ─────────────────────────────────────────────────

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.highlight, required this.gp});
  final Map<String, dynamic> highlight;
  final _GP gp;

  Color _accentFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => gp.a,
      };

  @override
  Widget build(BuildContext context) {
    final content = highlight['content'] as String? ?? '';
    final color   = highlight['color']   as String?;
    final books   = highlight['books']   as Map?;
    final title   = books?['title']  as String?;
    final author  = books?['author'] as String?;
    final accent  = _accentFor(color);
    final dark    = Color.fromARGB(255, (accent.red * 0.55).round(),
        (accent.green * 0.55).round(), (accent.blue * 0.55).round());
    final excerpt =
        content.length > 200 ? '${content.substring(0, 200)}…' : content;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text('HIGHLIGHT IN EVIDENZA',
                    style: MarginaliaTextStyles.sectionTitle),
                const SizedBox(width: 12),
                const Expanded(
                    child: Divider(color: MarginaliaColors.ruleFaint)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [accent, dark], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                // Decorative quote
                Positioned(
                  top: -4, left: 10,
                  child: Text(
                    '"',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 80,
                      height: 0.8,
                      color: Colors.white.withAlpha(14),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
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
                                  color: Color(0xFFEDE5D5),
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (author != null && author.isNotEmpty)
                              Text(
                                ' · ${author.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.white.withAlpha(160),
                                  letterSpacing: 0.3,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        excerpt,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFFEDE5D5),
                          height: 1.75,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 80.ms);
  }
}

// ─── Book cell (3-col grid) — uses editorial cover ────────────────────────────

class _BookCell extends StatelessWidget {
  const _BookCell({required this.book, required this.index});
  final Map<String, dynamic> book;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title  = book['title']  as String? ?? '';
    final author = book['author'] as String? ?? '';

    return GestureDetector(
      onTap: () {/* TODO: navigate to book detail */},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BookEditorialCover(title: title, author: author),
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 260.ms, curve: Curves.easeOut);
  }
}

// ─── Instagram-style posts grid ───────────────────────────────────────────────

// Muted dark-toned backgrounds for text-only post tiles
const _kPostBgColors = [
  Color(0xFF3D5A4E), // sage
  Color(0xFF4A3D5A), // plum
  Color(0xFF5A4A3D), // umber
  Color(0xFF3D4A5A), // slate
  Color(0xFF5A3D4A), // dusty rose
  Color(0xFF4A5A3D), // olive
  Color(0xFF5A3D3D), // terracotta
  Color(0xFF3D3D5A), // indigo
];

class _PostsGrid extends StatelessWidget {
  const _PostsGrid({required this.posts});
  final List<Map<String, dynamic>> posts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1.0, // square tiles
        ),
        itemCount: posts.length,
        itemBuilder: (_, i) => _PostGridTile(
          post: posts[i],
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _PostDetailSheet(post: posts[i]),
          ),
        ),
      ),
    );
  }
}

class _PostGridTile extends StatelessWidget {
  const _PostGridTile({required this.post, required this.onTap});
  final Map<String, dynamic> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final body      = post['body']       as String?;
    final imageUrl  = post['image_url']  as String?;
    final highlight = post['highlights'] as Map?;
    final hlContent = highlight?['content'] as String?;

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    // Show body first; fall back to highlight snippet
    final isQuote  = (body == null || body.trim().isEmpty) && hlContent != null;
    final preview  = isQuote
        ? hlContent!.trim()
        : (body?.trim() ?? '');
    final hash     = preview.hashCode.abs();
    final bgColor  = _kPostBgColors[hash % _kPostBgColors.length];

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background ──────────────────────────────────────────────
            if (hasImage)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(color: bgColor),
              )
            else
              ColoredBox(color: bgColor),

            // ── Bottom gradient scrim ─────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(hasImage ? 170 : 110),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),
            ),

            // ── Preview text ──────────────────────────────────────────
            if (preview.isNotEmpty)
              Positioned(
                left: 7, right: 18, bottom: 7,
                child: Text(
                  preview,
                  style: isQuote
                      ? GoogleFonts.ebGaramond(
                          fontSize: 8.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                          height: 1.3,
                        )
                      : GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // ── "More" chevron ────────────────────────────────────────
            const Positioned(
              bottom: 4, right: 4,
              child: Icon(
                Icons.chevron_right_rounded,
                color: Color(0xCCFFFFFF),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Post detail bottom sheet ─────────────────────────────────────────────────

class _PostDetailSheet extends StatelessWidget {
  const _PostDetailSheet({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Full post card (reuses existing layout)
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottom + 20),
              child: _ProfilePostCard(post: post),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Appearance sheet (kept for reference — replaced by EditProfileScreen) ────
// ignore: unused_element
class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet({
    required this.initialGradient,
    required this.initialPattern,
    required this.onSave,
  });
  final String initialGradient;
  final String initialPattern;
  final Future<void> Function(String gradient, String pattern) onSave;

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  late String _grad;
  late String _pat;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _grad = widget.initialGradient;
    _pat  = widget.initialPattern;
  }

  @override
  Widget build(BuildContext context) {
    final gp = _gpFor(_grad);

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          0, 0, 0, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Personalizza profilo',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),

          // Live preview
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gp.colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    if (_pat != 'none')
                      CustomPaint(painter: _PatternPainter(_pat)),
                    Center(
                      child: Text(
                        'Anteprima',
                        style: TextStyle(
                          color: Colors.white.withAlpha(180),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Gradient label
          const Padding(
            padding: EdgeInsets.only(left: 20, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SFONDO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          // Gradient swatches
          SizedBox(
            height: 60,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: _kGradients.length,
              itemBuilder: (_, i) {
                final g   = _kGradients[i];
                final sel = g.key == _grad;
                return GestureDetector(
                  onTap: () => setState(() => _grad = g.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: g.colors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel
                            ? Colors.white
                            : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                  color: g.a.withAlpha(100),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]
                          : null,
                    ),
                    child: sel
                        ? const Center(
                            child: Icon(Icons.check,
                                color: Colors.white, size: 16))
                        : null,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Gradient labels
          SizedBox(
            height: 22,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: _kGradients.length,
              itemBuilder: (_, i) {
                final g   = _kGradients[i];
                final sel = g.key == _grad;
                return SizedBox(
                  width: 52,
                  child: Text(
                    g.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel
                          ? MarginaliaColors.ink
                          : MarginaliaColors.inkFaint,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Pattern label
          const Padding(
            padding: EdgeInsets.only(left: 20, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PATTERN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          // Pattern swatches
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: _kPatterns.length,
              itemBuilder: (_, i) {
                final pk  = _kPatterns[i];
                final sel = pk == _pat;
                return GestureDetector(
                  onTap: () => setState(() => _pat = pk),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 64,
                    decoration: BoxDecoration(
                      color: sel
                          ? MarginaliaColors.primaryFaint
                          : MarginaliaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel
                            ? MarginaliaColors.primary
                            : MarginaliaColors.rule,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (pk == 'none')
                            const Icon(Icons.block,
                                size: 16,
                                color: MarginaliaColors.inkFaint)
                          else
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CustomPaint(
                                  painter: _PatternPainter(pk,
                                      color: MarginaliaColors.primary
                                          .withAlpha(120))),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Pattern labels
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 20),
            child: SizedBox(
              height: 18,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: _kPatterns.length,
                itemBuilder: (_, i) {
                  final pk  = _kPatterns[i];
                  final sel = pk == _pat;
                  return SizedBox(
                    width: 64,
                    child: Text(
                      _kPatternLabels[pk] ?? pk,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel
                            ? MarginaliaColors.primary
                            : MarginaliaColors.inkFaint,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        await widget.onSave(_grad, _pat);
                        if (mounted) Navigator.of(context).pop();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: MarginaliaColors.primary,
                  foregroundColor: const Color(0xFFF1EEE7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Color(0xFFF1EEE7)))
                    : const Text('Salva',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pattern painter ──────────────────────────────────────────────────────────

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, {this.color});
  final String pattern;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to bounds so patterns don't bleed outside their container.
    canvas.clipRect(Offset.zero & size);

    final paint = Paint()
      ..color = (color ?? Colors.white).withAlpha(color != null ? 255 : 20)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    switch (pattern) {
      case 'dots':
        _dots(canvas, size, paint..style = PaintingStyle.fill);
      case 'lines':
        _lines(canvas, size, paint);
      case 'grid':
        _grid(canvas, size, paint);
      case 'circles':
        _circles(canvas, size, paint);
    }
  }

  void _dots(Canvas canvas, Size size, Paint paint) {
    const spacing = 22.0;
    const r = 1.4;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  void _lines(Canvas canvas, Size size, Paint paint) {
    const spacing = 20.0;
    final diag = size.width + size.height;
    for (double d = -size.height; d < size.width; d += spacing) {
      canvas.drawLine(Offset(d, 0), Offset(d + diag, diag), paint);
    }
  }

  void _grid(Canvas canvas, Size size, Paint paint) {
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _circles(Canvas canvas, Size size, Paint paint) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    const step = 36.0;
    final maxR = math.sqrt(cx * cx + cy * cy) + step;
    for (double r = step; r < maxR; r += step) {
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.color != color;
}

// ─── Not logged in ────────────────────────────────────────────────────────────

class _NotLoggedIn extends StatelessWidget {
  const _NotLoggedIn();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(40, top, 40, 40),
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
                child: const Icon(Icons.person_outline,
                    size: 32, color: MarginaliaColors.siennaLight),
              ),
              const SizedBox(height: 20),
              const Text(
                'Accedi per vedere il profilo',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: MarginaliaColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.profileLoginBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: MarginaliaColors.inkMuted,
                    fontSize: 14,
                    height: 1.6),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/auth'),
                icon: const Icon(Icons.login, size: 16),
                label: Text(context.l10n.profileLoginCta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Profile post card (compact, Twitter-style) ───────────────────────────────

class _ProfilePostCard extends StatelessWidget {
  const _ProfilePostCard({required this.post});
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
    final body      = post['body']       as String?;
    final imageUrl  = post['image_url']  as String?;
    final createdAt = post['created_at'] as String?;
    final likes     = post['likes_count'] as int? ?? 0;
    final highlight = post['highlights'] as Map?;
    final hlContent = highlight?['content'] as String?;
    final hlBook    = highlight?['books']   as Map?;
    final hlTitle   = hlBook?['title']  as String?;

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.ruleFaint, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp
                  if (createdAt != null)
                    Text(
                      _timeAgo(createdAt),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: MarginaliaColors.inkFaint,
                      ),
                    ),
                  // Body text
                  if (body != null && body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        color: MarginaliaColors.ink,
                        height: 1.6,
                      ),
                    ),
                  ],
                  // Attached highlight
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
            // Image full-width (clipped to card's bottom corners)
            if (hasImage) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(13),
                  bottomRight: Radius.circular(13),
                ),
                child: Image.network(
                  imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            // Like count
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.favorite_border,
                      size: 14, color: MarginaliaColors.inkFaint),
                  const SizedBox(width: 4),
                  Text(
                    '$likes',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: MarginaliaColors.inkFaint,
                      fontWeight: FontWeight.w600,
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

// ─── Favourite books section ──────────────────────────────────────────────────

class _FavoriteBooksSection extends StatelessWidget {
  const _FavoriteBooksSection({
    required this.favBooks,
    required this.allBooks,
    required this.onEdit,
  });

  final List<Map<String, String>> favBooks;
  final List<Map<String, dynamic>> allBooks;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────────────────────
          Row(
            children: [
              Text('LIBRI DEL CUORE', style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(child: Divider(color: MarginaliaColors.ruleFaint)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.primaryFaint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MarginaliaColors.primary.withAlpha(50),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    favBooks.isEmpty ? 'Scegli' : 'Modifica',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Grid or empty state ─────────────────────────────────────────
          if (favBooks.isEmpty)
            _EmptyFavBooks(onEdit: onEdit)
          else
            _FavBooksGrid(favBooks: favBooks),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 60.ms);
  }
}

// ─── Pinterest masonry grid (2 rows) ──────────────────────────────────────────

enum _TileSize { large, medium, small }

class _FavBooksGrid extends StatelessWidget {
  const _FavBooksGrid({required this.favBooks});
  final List<Map<String, String>> favBooks;

  @override
  Widget build(BuildContext context) {
    // Always work with exactly 6 slots (pad with empty entries).
    final books = List<Map<String, String>>.from(favBooks);
    while (books.length < 6) {
      books.add({'title': '', 'author': ''});
    }

    const gap  = 6.0;
    const row1 = 200.0; // large left + two medium rights
    const row2 = 118.0; // three small equal tiles

    return Column(
      children: [
        // ── Row 1 ────────────────────────────────────────────────────────
        SizedBox(
          height: row1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Book 1 — big left tile (55% width)
              Expanded(
                flex: 55,
                child: _FavBookTile(book: books[0], size: _TileSize.large),
              ),
              const SizedBox(width: gap),
              // Books 2 + 3 — right column (45% width, stacked)
              Expanded(
                flex: 45,
                child: Column(
                  children: [
                    Expanded(
                      child: _FavBookTile(book: books[1], size: _TileSize.medium),
                    ),
                    const SizedBox(height: gap),
                    Expanded(
                      child: _FavBookTile(book: books[2], size: _TileSize.medium),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: gap),
        // ── Row 2 ────────────────────────────────────────────────────────
        SizedBox(
          height: row2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FavBookTile(book: books[3], size: _TileSize.small)),
              const SizedBox(width: gap),
              Expanded(child: _FavBookTile(book: books[4], size: _TileSize.small)),
              const SizedBox(width: gap),
              Expanded(child: _FavBookTile(book: books[5], size: _TileSize.small)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Single tile ──────────────────────────────────────────────────────────────

class _FavBookTile extends StatelessWidget {
  const _FavBookTile({required this.book, required this.size});
  final Map<String, String> book;
  final _TileSize size;

  @override
  Widget build(BuildContext context) {
    final title  = book['title']  ?? '';
    final author = book['author'] ?? '';

    // Empty placeholder
    if (title.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MarginaliaColors.ruleFaint),
        ),
        child: const Center(
          child: Icon(Icons.add_outlined,
              size: 22, color: MarginaliaColors.inkFaint),
        ),
      );
    }

    final double titleSize = switch (size) {
      _TileSize.large  => 13.0,
      _TileSize.medium => 11.5,
      _TileSize.small  => 9.5,
    };
    final int maxLines = switch (size) {
      _TileSize.large  => 3,
      _TileSize.medium => 2,
      _TileSize.small  => 2,
    };
    final double gradH = switch (size) {
      _TileSize.large  => 90.0,
      _TileSize.medium => 72.0,
      _TileSize.small  => 60.0,
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Editorial cover ─────────────────────────────────────────────
          BookEditorialCover(title: title, author: author),

          // ── Gradient for text legibility ────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0, height: gradH,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xCC000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // ── Title (+ author on large) ───────────────────────────────────
          Positioned(
            left: 8, right: 8, bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFEDE5D5),
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                if (size == _TileSize.large && author.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    author.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Color(0x99EDE5D5),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFavBooks extends StatelessWidget {
  const _EmptyFavBooks({required this.onEdit});
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MarginaliaColors.ruleFaint),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_border,
                size: 22, color: MarginaliaColors.inkFaint),
            const SizedBox(height: 8),
            Text(
              'Scegli i tuoi sei libri preferiti',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                color: MarginaliaColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Favourite books bottom-sheet picker ──────────────────────────────────────

Future<void> _openFavBooksSheet(
  BuildContext context, {
  required List<Map<String, dynamic>> allBooks,
  required List<Map<String, String>> current,
  required Future<void> Function(List<Map<String, String>>) onSave,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FavBooksSheet(
      allBooks: allBooks,
      current: current,
      onSave: onSave,
    ),
  );
}

class _FavBooksSheet extends StatefulWidget {
  const _FavBooksSheet({
    required this.allBooks,
    required this.current,
    required this.onSave,
  });
  final List<Map<String, dynamic>> allBooks;
  final List<Map<String, String>> current;
  final Future<void> Function(List<Map<String, String>>) onSave;

  @override
  State<_FavBooksSheet> createState() => _FavBooksSheetState();
}

class _FavBooksSheetState extends State<_FavBooksSheet> {
  late final List<Map<String, String>> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.current);
  }

  bool _isSelected(Map<String, dynamic> book) {
    final t = book['title'] as String? ?? '';
    return _selected.any((s) => s['title'] == t);
  }

  void _toggle(Map<String, dynamic> book) {
    final t = book['title']  as String? ?? '';
    final a = book['author'] as String? ?? '';
    setState(() {
      if (_isSelected(book)) {
        _selected.removeWhere((s) => s['title'] == t);
      } else if (_selected.length < 6) {
        _selected.add({'title': t, 'author': a});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final maxH   = MediaQuery.of(context).size.height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          // mainAxisSize.max so Flexible(ListView) gets remaining space
          // up to the ConstrainedBox(maxHeight) boundary.
          children: [

            // ── Handle ────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Title + counter ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  const Text(
                    'Libri del cuore',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MarginaliaColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      '${_selected.length}/6',
                      key: ValueKey(_selected.length),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _selected.length >= 6
                            ? MarginaliaColors.primary
                            : MarginaliaColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: MarginaliaColors.ruleFaint, height: 1),

            // ── Book list ─────────────────────────────────────────────────
            Flexible(
              child: widget.allBooks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        'Aggiungi libri alla tua libreria prima di scegliere i preferiti.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          color: MarginaliaColors.inkMuted,
                          height: 1.6,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: widget.allBooks.length,
                      itemBuilder: (_, i) {
                        final book   = widget.allBooks[i];
                        final title  = book['title']  as String? ?? '';
                        final author = book['author'] as String? ?? '';
                        final sel    = _isSelected(book);
                        final maxed  = _selected.length >= 6 && !sel;

                        return InkWell(
                          onTap: maxed ? null : () => _toggle(book),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            child: Row(
                              children: [
                                // Mini editorial cover
                                SizedBox(
                                  width: 36, height: 50,
                                  child: BookEditorialCover(
                                    title: title,
                                    author: author,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Title + author
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: maxed
                                              ? MarginaliaColors.inkFaint
                                              : MarginaliaColors.ink,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (author.isNotEmpty)
                                        Text(
                                          author.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            letterSpacing: 0.4,
                                            fontWeight: FontWeight.w500,
                                            color: maxed
                                                ? MarginaliaColors.inkFaint
                                                : MarginaliaColors.inkMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Circle checkbox
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: sel
                                        ? MarginaliaColors.primary
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: sel
                                          ? MarginaliaColors.primary
                                          : maxed
                                              ? MarginaliaColors.ruleFaint
                                              : MarginaliaColors.rule,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: sel
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 13)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(color: MarginaliaColors.ruleFaint, height: 1),

            // ── Save button ───────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, bottom + 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await widget.onSave(_selected);
                          if (mounted) Navigator.of(context).pop();
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: MarginaliaColors.primary,
                    foregroundColor: const Color(0xFFF1EEE7),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFF1EEE7)))
                      : const Text(
                          'Salva',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

