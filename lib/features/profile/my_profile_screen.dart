import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/share_helper.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/review_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'followers_screen.dart';
import 'posts_timeline.dart';
import 'reviews_tab.dart';
import 'activity_tab.dart';
import '../social/feed_tab.dart';
import '../library/book_cover.dart';
import '../library/bookshelf_view.dart';
import '../library/shelf_poster.dart';
import '../library/book_detail_screen.dart' show editBookCoverByKey;
import '../reader/book_info_screen.dart';
import '../stats/reading_stats_card.dart';
import 'profile_shared_widgets.dart' show favCoversProvider, favCoverKey;
import 'highlights_peek_sheet.dart';

// ─── Gradient presets ─────────────────────────────────────────────────────────

class _GP {
  const _GP(this.key, this.label, this.a, this.mid, this.b);
  final String key;
  final String label;
  final Color a;   // top stop — slightly lighter than the Pantone base
  final Color mid; // the Pantone base colour itself
  final Color b;   // bottom stop — slightly darker than the Pantone base
  // Three-stop gradient (light top → Pantone → dark bottom) so the hero header
  // still reads as a gradient rather than a flat fill.
  List<Color> get colors => [a, mid, b];
}

// Pantone palette chosen by the founder. Each preset is ONE Pantone colour,
// expanded into a 3-stop gradient: a slightly-lighter top stop (`a`), the exact
// Pantone base in the middle (`mid`), and a slightly-darker bottom stop (`b`).
// The 8 keys are unchanged (sepia/forest/ocean/dusk/rose/graphite/amber/slate,
// same order) so existing saved selections still resolve — only the colours and
// labels changed. `_sectionTitleColor` derives the section-title colour from the
// top stop (`a`), and the page-background wash blends `a`/`b` at low alpha, so
// the section titles stay readable on every preset (verified: WCAG contrast
// ≥ 7.3:1 against the tinted page on the two lightest presets, Pastel Yellow and
// Coconut Milk).
const _kGradients = [
  _GP('sepia',    'Vintage Wine',  Color(0xFF694852), Color(0xFF3F1521), Color(0xFF2C0F17)),
  _GP('forest',   'Pastel Yellow', Color(0xFFF3E8B9), Color(0xFFF2E6B1), Color(0xFFCBC195)),
  _GP('ocean',    'Reseda',        Color(0xFFB0BAA3), Color(0xFFA1AD92), Color(0xFF7E8772)),
  _GP('dusk',     'Chive',         Color(0xFF686B53), Color(0xFF3E4123), Color(0xFF2B2E18)),
  _GP('rose',     'Powder Blue',   Color(0xFFA5BECD), Color(0xFF94B2C4), Color(0xFF738B99)),
  _GP('graphite', 'Navy 2965C',    Color(0xFF476173), Color(0xFF13344C), Color(0xFF0D2435)),
  _GP('amber',    'Cocoa Brown',   Color(0xFF8C766C), Color(0xFF6C5042), Color(0xFF4C382E)),
  _GP('slate',    'Coconut Milk',  Color(0xFFF2EFE8), Color(0xFFF0EDE5), Color(0xFFCAC7C0)),
];

_GP _gpFor(String key) =>
    _kGradients.firstWhere((g) => g.key == key,
        orElse: () => _kGradients.first);

// ─── Section-title colour (contrast vs. selected background) ──────────────────
//
// The shared ScriptaTextStyles.sectionTitle uses a faint grey (inkFaint)
// that, while fine on the plain cream Library/Stats pages, washes out over the
// tinted profile background — and the tint changes with every gradient preset
// (sepia, amber, ocean, …). To guarantee a readable title on EVERY preset, the
// profile derives its own title colour from the chosen gradient: take the
// gradient's main colour and darken it heavily toward ink. The result is a
// strong, on-brand label that always reads on the warm-white + tint wash,
// even for the lightest presets (Amber/Pastel-Yellow). Only the profile uses
// this — other screens keep the global faint style.
Color _sectionTitleColor(_GP gp) =>
    Color.alphaBlend(gp.a.withAlpha(0x40), ScriptaColors.ink);

// Profile section-title style: the shared section-title shape (size / weight /
// tracking) with the contrast colour applied.
TextStyle _profileSectionTitle(_GP gp) =>
    ScriptaTextStyles.sectionTitle.copyWith(color: _sectionTitleColor(gp));


// Render-time localized label for a gradient, keyed by the stable gradient id.
// The const _kGradients list above cannot use context.l10n, so the display
// label is resolved here at build time.
String _gradientLabel(BuildContext context, String key) => switch (key) {
      'sepia'    => context.l10n.gradientSepia,
      'forest'   => context.l10n.gradientForest,
      'ocean'    => context.l10n.gradientOcean,
      'dusk'     => context.l10n.gradientDusk,
      'rose'     => context.l10n.gradientRose,
      'graphite' => context.l10n.gradientGraphite,
      'amber'    => context.l10n.gradientAmber,
      'slate'    => context.l10n.gradientSlate,
      _          => context.l10n.gradientSepia,
    };

// ─── Pattern keys ─────────────────────────────────────────────────────────────

const _kPatterns = ['none', 'dots', 'lines', 'grid', 'circles'];

// Render-time localized label for a pattern, keyed by the stable pattern id.
String _patternLabel(BuildContext context, String key) => switch (key) {
      'none'    => context.l10n.patternNone,
      'dots'    => context.l10n.patternDots,
      'lines'   => context.l10n.patternLines,
      'grid'    => context.l10n.patternGrid,
      'circles' => context.l10n.patternCircles,
      _         => context.l10n.patternNone,
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

/// Highlight count for a book row, as returned by the embedded
/// `highlights(count)` aggregate. Older cached rows simply have none, and a
/// book with no count is drawn as a thin spine rather than not at all.
int _marksOf(Map<String, dynamic> book) {
  final hl = book['highlights'];
  if (hl is List && hl.isNotEmpty) {
    final first = hl.first;
    if (first is Map) return (first['count'] as num?)?.toInt() ?? 0;
  }
  if (hl is Map) return (hl['count'] as num?)?.toInt() ?? 0;
  return 0;
}

final _gradientKeyProvider = StateProvider<String>((ref) => 'sepia');
final _patternKeyProvider   = StateProvider<String>((ref) => 'none');

/// Which profile tab is active: 0 = Profilo, 1 = Recensioni, 2 = Attività.
final _profileTabProvider = StateProvider.autoDispose<int>((ref) => 0);

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
    final name = profile?['display_name'] as String? ?? 'Scripta';
    // Share a WEB invite link (not an in-app deep link): it opens a public
    // landing page that greets the recipient with "Unisciti a <name> su
    // Scripta!" and a download CTA. The page (web/u/index.html) reads the
    // name from the ?u= query param. NOTE: the get-scripta.app domain must be
    // pointed at GitHub Pages for this to resolve (see launch notes); until
    // then the same page is reachable at the github.io URL.
    final link =
        'https://get-scripta.app/u/?u=${Uri.encodeComponent(name)}';
    Share.share(
      'Unisciti a $name su Scripta!\n\n$link',
      subject: 'Scripta – $name',
      sharePositionOrigin: shareOrigin(context),
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
    final activeTab    = ref.watch(_profileTabProvider);

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

    // Blend the gradient colors into the cream background so the whole page
    // reads as gently tinted by the chosen preset. A previous pass pushed this
    // to alpha 104/168, which made the wash so saturated (e.g. the gold/amber
    // preset) that grey section labels and the spotlight box lost contrast and
    // became hard to read. Dialled back to a subtle tint — a touch warmer than
    // the original 28/45 so the colour is still present, but light enough that
    // muted-grey labels stay legible. Text still lives on solid white cards
    // (ScriptaDecorations.card) and reads perfectly.
    final bgTop    = Color.alphaBlend(gp.a.withAlpha(46), ScriptaColors.background);
    final bgBottom = Color.alphaBlend(gp.b.withAlpha(80), ScriptaColors.background);

    return Scaffold(
      backgroundColor: ScriptaColors.background,
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

          // (Full-page pattern overlay removed — it painted thousands of
          // primitives behind every other widget on every frame, which
          // hung the profile on iOS Safari WebView. The same pattern
          // still renders inside the cover image below, where it belongs
          // visually and where the canvas size is bounded.)

          // ── Scrollable content ───────────────────────────────────────────
          RefreshIndicator(
            color: ScriptaColors.sienna,
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
                streak: ref.watch(reviewStateProvider).asData?.value
                        .currentStreak ??
                    0,
                onFollowers: () => showProfileList(context,
                    userId: uid,
                    type: ProfileListType.followers,
                    count: stats['followers'] ?? 0,
                    onChanged: () => ref.invalidate(_myStatsProvider)),
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

          // ── Tab switcher (Profilo · Recensioni) ──────────────────────────
          // The profile gained a second face: book reviews. A quiet segmented
          // control sits under the shared identity block (header + stats) and
          // swaps the body below it, so "who you are" stays constant while the
          // content (your library/posts vs. your reviews) changes.
          SliverToBoxAdapter(
            child: _ProfileTabBar(
              active: activeTab,
              onChanged: (i) =>
                  ref.read(_profileTabProvider.notifier).state = i,
            ),
          ),

          // ════════════════ TAB 1 · RECENSIONI ════════════════════════════
          if (activeTab == 1)
            const SliverToBoxAdapter(child: ReviewsTab()),

          // ════════════════ TAB 2 · ATTIVITÀ (Activity) ═══════════════════
          if (activeTab == 2)
            SliverToBoxAdapter(
              child: ActivityTab(
                displayName:
                    profileAsync.asData?.value?['display_name'] as String?,
                // Heatmap ramp + share-card header derive from the profile's
                // chosen background colour, so the Activity tab stays coherent
                // with the rest of the profile.
                seedColor: gp.mid,
                headerColors: gp.colors,
              ),
            ),

          // ════════════════ TAB 0 · PROFILO ═══════════════════════════════
          if (activeTab == 0) ...[

          // ── Reading stats card (annual goal + 3 quick metrics) ──────────
          // Promoted from a one-line text link to a full hero card so
          // reading goals + streak + monthly minutes get the visibility
          // they deserve. Tap → full breakdown at /stats.
          const SliverToBoxAdapter(child: ReadingStatsCard()),

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
              gp: gp,
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
                  Text(context.l10n.profilePostsSection, style: _profileSectionTitle(gp)),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: ScriptaColors.ruleFaint)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      // Present above the floating navbar so the composer +
                      // its keyboard aren't clipped by the shell's bottom bar.
                      useRootNavigator: true,
                      backgroundColor: Colors.transparent,
                      // Keep the feed visible behind the composer (founder).
                      barrierColor: Colors.black.withOpacity(0.12),
                      builder: (_) => CreatePostSheet(
                        onCreated: () => ref.invalidate(_myPostsProvider),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ScriptaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: ScriptaColors.primary.withAlpha(50),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        context.l10n.profileWriteButton,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: ScriptaColors.primaryDark,
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
                  color: ScriptaColors.sienna, strokeWidth: 1.5)),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (posts) => posts.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Text(
                        context.l10n.feedMyPostsNoPostsYet,
                        style: GoogleFonts.manrope(
                          color: ScriptaColors.inkMuted, fontSize: 13),
                      ),
                    ),
                  )
                : SliverToBoxAdapter(
                    child: PostsTimeline(
                      posts: posts,
                      profile: profileAsync.value,
                      // The owner still sees their own hidden like counts
                      // (with a visibility-off hint) on their own timeline.
                      isOwnProfile: true,
                      onTapPost: (post) =>
                          context.push('/post/${post['id']}'),
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
                              Text(context.l10n.profileLibrarySection,
                                  style: _profileSectionTitle(gp)),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Divider(
                                      color: ScriptaColors.ruleFaint)),
                              const SizedBox(width: 12),
                              // Hands the shelf to the system share sheet —
                              // which is how it reaches Instagram — as a 4:5
                              // poster signed bottom-right.
                              _ShelfShareButton(
                                entries: [
                                  for (final b in books)
                                    ShelfEntry(
                                      title:  (b['title']  as String?) ?? '',
                                      author: (b['author'] as String?) ?? '',
                                      highlightCount: _marksOf(b),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // The shelf, not a grid of cards. A profile answers
                        // "what has this person read?", and forty spines say
                        // that in one glance where forty cards need a minute
                        // of scrolling. The cover art still has its home in
                        // the Library's grid view.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: BookshelfView(
                            entries: [
                              for (final b in books)
                                ShelfEntry(
                                  title:  (b['title']  as String?) ?? '',
                                  author: (b['author'] as String?) ?? '',
                                  highlightCount: _marksOf(b),
                                ),
                            ],
                            onTap: (_, e) => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BookInfoScreen(
                                  title:  e.title,
                                  author: e.author,
                                ),
                              ),
                            ),
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
                      color: ScriptaColors.sienna, strokeWidth: 1.5),
                ),
              ),
            ),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Libri consigliati ────────────────────────────────────────────
          // Removed from the profile: "libri consigliati" now lives ONLY in
          // the Library, per the founder's request.
          ], // end TAB 0 · PROFILO

          // ── Bottom padding for nav bar ────────────────────────────────────
          // The shell (app.dart) augments MediaQuery's bottom padding by the
          // floating nav-bar inset. Consume it here so the last section clears
          // the navbar instead of hiding behind it. +16 for breathing room.
          SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 16),
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
    final avatarTint = ScriptaDecorations.bookCoverColor(name);

    // The hero header is a dark gradient/cover that bleeds under the status
    // bar. A plain Container header (no AppBar) doesn't auto-correct the
    // system icons, so without this the iOS clock/battery render dark-on-dark
    // and read as a graphic overlap at the very top. Force light status-bar
    // icons while this dark header sits at the top of the screen.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ScriptaDecorations.lightStatusBar,
      child: SizedBox(
      height: 290 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: cover photo OR gradient (square corners) ──────────
          // The hero banner is a plain rectangle — the Stack clips its children
          // to its rectangular bounds, so the bottom edge is a clean square cut.
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

              // Cover pattern overlay removed — personalization with
              // dots/lines/circles was dropped at the founder's request.
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
                // ── Avatar (long-press → peek your recent highlights) ───────
                Consumer(
                  builder: (context, ref, _) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => HighlightsPeekSheet.show(
                      context,
                      title:
                          Localizations.localeOf(context).languageCode == 'it'
                              ? 'I tuoi highlight recenti'
                              : 'Your recent highlights',
                    ),
                    child: Container(
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
                        name.isEmpty ? context.l10n.profileYourProfile : name,
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
                            color: Colors.white.withAlpha(200),
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
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
                    tooltip: context.l10n.profileEditProfile),
                const SizedBox(width: 8),
                _IconBtn(
                    icon: Icons.ios_share_outlined,
                    onTap: onShare,
                    tooltip: context.l10n.profileShareProfile),
                const SizedBox(width: 8),
                _IconBtn(
                    icon: Icons.settings_outlined,
                    onTap: onSettings,
                    tooltip: context.l10n.profileSettings),
              ],
            ),
          ),
        ],
      ),
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
    required this.streak,
    required this.onFollowers,
    required this.onFollowing,
    required this.onBooks,
  });
  final Map<String, int> stats;
  final int booksCount;
  final int streak;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;
  final VoidCallback onBooks;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: ScriptaDecorations.card(),
      child: Row(
        children: [
          _StatBox(label: context.l10n.profileBooksStat, value: booksCount, onTap: onBooks),
          _Div(),
          _StatBox(label: context.l10n.profileHighlightsStat, value: stats['highlights'] ?? 0),
          _Div(),
          // Ripasso streak — a flame glyph instead of a label, since it reads as
          // a personal achievement next to the social counts.
          _StreakStatBox(streak: streak),
          _Div(),
          _StatBox(label: context.l10n.profileFollowing, value: stats['following'] ?? 0, onTap: onFollowing),
          _Div(),
          _StatBox(label: context.l10n.profileFollowers, value: stats['followers'] ?? 0, onTap: onFollowers),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.04, end: 0, duration: 350.ms);
  }
}

/// A stat cell that shows the Ripasso streak: the count over a small flame +
/// "streak" label. Lit (sage) when the streak is active, muted at zero.
class _StreakStatBox extends StatelessWidget {
  const _StreakStatBox({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final active = streak > 0;
    final color = active ? ScriptaColors.primaryDark : ScriptaColors.inkFaint;
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? PhosphorIconsFill.flame : PhosphorIconsRegular.flame,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 3),
              Text(
                '$streak',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: active ? ScriptaColors.ink : ScriptaColors.inkFaint,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.profileStreakStat,
            style: TextStyle(
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

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: ScriptaColors.ruleFaint);
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
                    ? ScriptaColors.primaryDark
                    : ScriptaColors.ink,
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
                    ? ScriptaColors.primaryDark
                    : ScriptaColors.inkFaint,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile tab bar (Profilo · Recensioni) ──────────────────────────────────
//
// A quiet pill-style segmented control. Lives on the cream page so it uses the
// surface/sage tokens (not the dark hero palette). The selected segment gets a
// white card + sage label; the other stays muted ink. Minimal, on-brand.

class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({required this.active, required this.onChanged});
  final int active;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScriptaColors.ruleFaint, width: 0.8),
      ),
      child: Row(
        children: [
          _Segment(
            label: context.l10n.profileTabPosts,
            icon: Icons.person_outline_rounded,
            selected: active == 0,
            onTap: () => onChanged(0),
          ),
          _Segment(
            label: context.l10n.profileTabReviews,
            icon: Icons.rate_review_outlined,
            selected: active == 1,
            onTap: () => onChanged(1),
          ),
          _Segment(
            label: context.l10n.profileTabActivity,
            icon: Icons.grid_view_rounded,
            selected: active == 2,
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? ScriptaColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const [
                    BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 6,
                        offset: Offset(0, 1)),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? ScriptaColors.primaryDark
                    : ScriptaColors.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? ScriptaColors.ink
                      : ScriptaColors.inkMuted,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
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
        decoration: ScriptaDecorations.card(),
        // Vertical padding replaces the height the left colour spine
        // previously contributed, so the card keeps its 72px feel.
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
                    context.l10n.editProfileCurrentlyReadingLabel,
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
                      style: ScriptaTextStyles.bookAuthor
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
                Text(context.l10n.profileSpotlight,
                    style: _profileSectionTitle(gp)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Divider(color: ScriptaColors.ruleFaint)),
              ],
            ),
          ),
          // Light surface instead of a saturated coloured fill. The previous
          // version filled the whole box with the highlight's accent colour
          // and set the quote in pale cream — which washed out badly on the
          // brighter accents (gold/amber especially). Now the box is a white
          // card in the app's house style: the accent survives as a left
          // spine + the coloured book-title label + a faint decorative quote,
          // and the quote itself is dark ink, so it reads on any accent.
          Container(
            decoration: ScriptaDecorations.card(radius: 18),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Accent spine — keeps the highlight's colour identity.
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Stack(
                      children: [
                        // Faint decorative quote in the accent colour.
                        Positioned(
                          top: -6, left: 8,
                          child: Text(
                            '"',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 78,
                              height: 0.8,
                              color: accent.withAlpha(26),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null && title.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: accent,
                                          letterSpacing: 0.3,
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
                                          color: ScriptaColors.inkFaint,
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
                                  color: ScriptaColors.ink,
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
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 80.ms);
  }
}

// ─── Book cell (3-col grid) — cover + title + author in a single card ────────
//
// User feedback on the geometric-cover redesign: in the profile grid the
// shapes alone weren't enough to recognise a book at a glance. The library
// view already pairs the cover with title + author below, and the profile
// "LIBRARY" section should follow the same pattern — one card, cover on
// top, title and author underneath. Without it the profile reads as
// "anonymous art tiles," which is the opposite of what a library should
// communicate.

class _ShelfShareButton extends ConsumerWidget {
  const _ShelfShareButton({required this.entries});

  final List<ShelfEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final name = ref.watch(myDisplayNameProvider).asData?.value ?? '';

    return Semantics(
      button: true,
      label: context.l10n.shareImageCta,
      child: GestureDetector(
        onTap: () => showShelfImageShareSheet(
          context,
          entries: entries,
          userName: name,
        ),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: ScriptaColors.primaryFaint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.ios_share,
              size: 15, color: ScriptaColors.primaryDark),
        ),
      ),
    );
  }
}

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
    final isQuote  = (body == null || body.trim().isEmpty) && hlContent != null;
    final preview  = isQuote ? hlContent!.trim() : (body?.trim() ?? '');

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: hasImage
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: ScriptaColors.surface),
              )
            : Container(
                decoration: BoxDecoration(
                  color: ScriptaColors.surface,
                  border: Border.all(
                      color: ScriptaColors.ruleFaint, width: 0.8),
                ),
                padding: const EdgeInsets.all(7),
                alignment: Alignment.topLeft,
                child: Text(
                  preview,
                  style: isQuote
                      ? GoogleFonts.ebGaramond(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: ScriptaColors.ink,
                          height: 1.4,
                        )
                      : GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: ScriptaColors.ink,
                          height: 1.4,
                        ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
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
        color: ScriptaColors.surface,
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
              color: ScriptaColors.rule,
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
        color: ScriptaColors.surface,
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
              color: ScriptaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              context.l10n.profileCustomise,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ScriptaColors.ink,
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
                        context.l10n.editProfilePreviewLabel,
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
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.profileBackgroundLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.inkFaint,
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

          // Gradient labels — give them room for two lines so longer names
          // (e.g. "Crepuscolo") never get their second row clipped.
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: _kGradients.length,
              itemBuilder: (_, i) {
                final g   = _kGradients[i];
                final sel = g.key == _grad;
                return SizedBox(
                  width: 56,
                  child: Text(
                    _gradientLabel(context, g.key),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.15,
                      fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel
                          ? ScriptaColors.ink
                          : ScriptaColors.inkFaint,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // (Cover pattern picker removed — personalization with
          // dots/lines/circles was dropped at the founder's request.)

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
                  backgroundColor: ScriptaColors.primary,
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
                    : Text(context.l10n.save,
                        style: const TextStyle(
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
      backgroundColor: ScriptaColors.background,
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
                  color: ScriptaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.person_outline,
                    size: 32, color: ScriptaColors.siennaLight),
              ),
              const SizedBox(height: 20),
              Text(
                context.l10n.profileLoginRequired,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.profileLoginBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ScriptaColors.inkMuted,
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

  String _timeAgo(BuildContext context, String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return context.l10n.timeNow;
    if (diff.inMinutes < 60) return context.l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24)   return context.l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7)     return context.l10n.timeDaysAgo(diff.inDays);
    return context.l10n.timeWeeksAgo((diff.inDays / 7).round());
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
          color: ScriptaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ScriptaColors.ruleFaint, width: 0.8),
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
                      _timeAgo(context, createdAt),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: ScriptaColors.inkFaint,
                      ),
                    ),
                  // Body text
                  if (body != null && body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        color: ScriptaColors.ink,
                        height: 1.6,
                      ),
                    ),
                  ],
                  // Attached highlight
                  if (hlContent != null && hlContent.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: ScriptaColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: ScriptaColors.ruleFaint, width: 0.8),
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
                                color: ScriptaColors.inkMuted,
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
                              color: ScriptaColors.ink,
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
                      size: 14, color: ScriptaColors.inkFaint),
                  const SizedBox(width: 4),
                  Text(
                    '$likes',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: ScriptaColors.inkFaint,
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
    required this.gp,
    required this.favBooks,
    required this.allBooks,
    required this.onEdit,
  });

  final _GP gp;
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
              Text(context.l10n.profileFavouriteBooksSection, style: _profileSectionTitle(gp)),
              const SizedBox(width: 12),
              const Expanded(child: Divider(color: ScriptaColors.ruleFaint)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ScriptaColors.primaryFaint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ScriptaColors.primary.withAlpha(50),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    favBooks.isEmpty ? context.l10n.profileChooseButton : context.l10n.profileEditButton,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.primaryDark,
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
    final n = favBooks.length.clamp(0, 6);
    if (n == 0) return const SizedBox.shrink();

    const gap   = 6.0;
    const row1H = 200.0;
    const row2H = 118.0;

    final row1 = favBooks.take(3).toList();
    final row2 = n > 3
        ? favBooks.skip(3).take(3).toList()
        : <Map<String, String>>[];

    return Column(
      children: [
        // ── Row 1: large left + up to two stacked mediums ─────────────────
        SizedBox(
          height: row1H,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: row1.length >= 2 ? 55 : 100,
                child: _FavBookTile(book: row1[0], size: _TileSize.large),
              ),
              if (row1.length >= 2) ...[
                const SizedBox(width: gap),
                Expanded(
                  flex: 45,
                  child: row1.length >= 3
                      ? Column(
                          children: [
                            Expanded(
                              child: _FavBookTile(
                                  book: row1[1], size: _TileSize.medium),
                            ),
                            const SizedBox(height: gap),
                            Expanded(
                              child: _FavBookTile(
                                  book: row1[2], size: _TileSize.medium),
                            ),
                          ],
                        )
                      : _FavBookTile(book: row1[1], size: _TileSize.medium),
                ),
              ],
            ],
          ),
        ),
        // ── Row 2: 1–3 small tiles (only when books 4–6 exist) ────────────
        if (row2.isNotEmpty) ...[
          const SizedBox(height: gap),
          SizedBox(
            height: row2H,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < row2.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: _FavBookTile(
                        book: row2[i], size: _TileSize.small),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Single tile ──────────────────────────────────────────────────────────────

class _FavBookTile extends ConsumerWidget {
  const _FavBookTile({required this.book, required this.size});
  final Map<String, String> book;
  final _TileSize size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title  = book['title']  ?? '';
    final author = book['author'] ?? '';

    // Custom per-user cover (also shown to anyone who visits this profile).
    final coverUrl = title.isEmpty
        ? null
        : ref
            .watch(favCoversProvider(null))
            .asData
            ?.value[favCoverKey(title, author)];

    // Pencil action: edit this favourite's cover by title/author. Works even
    // when the book isn't an exact library row; writes the per-user cover store
    // (shown on favourites, reviews, library and to anyone visiting the profile)
    // and mirrors to the local library book when one matches.
    void editCover() => editBookCoverByKey(context, ref, title, author);

    // Empty placeholder
    if (title.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: ScriptaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ScriptaColors.ruleFaint),
        ),
        child: const Center(
          child: Icon(Icons.add_outlined,
              size: 22, color: ScriptaColors.inkFaint),
        ),
      );
    }

    final double titleSize = switch (size) {
      _TileSize.large  => 13.0,
      _TileSize.medium => 11.5,
      _TileSize.small  => 9.5,
    };
    // Title is now capped tighter on small/medium so the author byline below
    // has a guaranteed row to itself. Previously only the large tile showed
    // the author, which felt inconsistent — the user reported "i 6 preferiti
    // non hanno tutti titolo e autore" after the geometric covers shipped.
    final int maxLines = switch (size) {
      _TileSize.large  => 3,
      _TileSize.medium => 2,
      _TileSize.small  => 1,
    };
    final double authorSize = switch (size) {
      _TileSize.large  => 8.5,
      _TileSize.medium => 7.5,
      _TileSize.small  => 7.0,
    };
    final double gradH = switch (size) {
      _TileSize.large  => 96.0,
      _TileSize.medium => 78.0,
      _TileSize.small  => 64.0,
    };

    // Favourites store only {title, author} (migration 024). Tapping opens the
    // keyless BookInfoScreen (cover + plot) — consistent with the library grid
    // and others' profiles, with no fragile local Isar lookup.
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              BookInfoScreen(title: title, author: author, coverUrl: coverUrl),
        ),
      ),
      // Long-press → peek this book's highlights (like the library book sheet).
      onLongPress: () => HighlightsPeekSheet.show(context,
          bookTitle: title, title: title, subtitle: author),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Editorial cover ─────────────────────────────────────────────
          BookEditorialCover(title: title, author: author, coverUrl: coverUrl),

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
                // Author byline — now shown on every size, not just large.
                // Tighter font + slightly lower opacity on the smaller tiles
                // so it stays a quiet secondary line under the title.
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    author.toUpperCase(),
                    style: TextStyle(
                      fontSize: authorSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0x99EDE5D5),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // ── Edit-cover pencil (own favourites only) ─────────────────────
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: editCover,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(102),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_outlined,
                    size: 13, color: Color(0xFFEDE5D5)),
              ),
            ),
          ),
        ],
      ),
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
          color: ScriptaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ScriptaColors.ruleFaint),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_border,
                size: 22, color: ScriptaColors.inkFaint),
            const SizedBox(height: 8),
            Text(
              context.l10n.profileChooseFavouritesPrompt,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                color: ScriptaColors.inkMuted,
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
    // Present above the floating navbar so the sheet (and its Save action at
    // the bottom) isn't hidden behind the shell's floating bottom bar.
    useRootNavigator: true,
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
    final mq = MediaQuery.of(context);
    // Pad below the Save action by the safe-area inset PLUS any keyboard inset,
    // so the button is never clipped by the home indicator or an open keyboard.
    final bottom = mq.padding.bottom + mq.viewInsets.bottom;
    final maxH   = mq.size.height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: ScriptaColors.surface,
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
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Title + counter ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Text(
                    context.l10n.profileFavouriteBooksTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ScriptaColors.ink,
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
                            ? ScriptaColors.primary
                            : ScriptaColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: ScriptaColors.ruleFaint, height: 1),

            // ── Book list ─────────────────────────────────────────────────
            Flexible(
              child: widget.allBooks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text(
                        context.l10n.profileAddBooksBeforeFavourites,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          color: ScriptaColors.inkMuted,
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
                                              ? ScriptaColors.inkFaint
                                              : ScriptaColors.ink,
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
                                                ? ScriptaColors.inkFaint
                                                : ScriptaColors.inkMuted,
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
                                        ? ScriptaColors.primary
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: sel
                                          ? ScriptaColors.primary
                                          : maxed
                                              ? ScriptaColors.ruleFaint
                                              : ScriptaColors.rule,
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

            const Divider(color: ScriptaColors.ruleFaint, height: 1),

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
                    backgroundColor: ScriptaColors.primary,
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
                      : Text(
                          context.l10n.save,
                          style: const TextStyle(
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

