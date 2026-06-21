import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/utils/share_helper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import 'amici_tab.dart';

final jamsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) {
    final service = ref.watch(supabaseServiceProvider);
    if (!service.isAuthenticated) return Future.value([]);
    return service.fetchMyJams();
  },
);

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    // Rebuild to show/hide FAB when switching tabs.
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isAuthenticatedProvider)) {
      return const _UnauthenticatedState();
    }

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      floatingActionButton: _tabController.index == 0
          ? _CreateJamFab(onTap: _showCreateJamSheet)
          : null,
      body: Column(
        children: [
          // ── Gradient header with embedded TabBar ──────────────────────
          _SocialHeader(
            tabController: _tabController,
            onJoin: _showJoinJamSheet,
            onSearch: () => context.push('/search'),
          ),
          // ── Tab content ───────────────────────────────────────────────
          // The inner TabBarView's native swipe used to swallow ALL horizontal
          // drags, so the bottom-tab swipe never worked inside Jam (founder,
          // 2026-06-21). We disable its native swipe and drive horizontal flings
          // ourselves: a fling switches the inner section, but AT THE EDGE it
          // hands off to the adjacent bottom tab (section 0 → Library, section 1
          // → Home) — same fling model the other tabs already use.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v.abs() < 300) return; // deliberate fling only
                final idx = _tabController.index;
                if (v < 0) {
                  // swipe left → next inner section, else next bottom tab
                  if (idx == 0) {
                    _tabController.animateTo(1);
                  } else {
                    HapticFeedback.lightImpact();
                    context.go('/home');
                  }
                } else {
                  // swipe right → previous inner section, else previous bottom tab
                  if (idx == 1) {
                    _tabController.animateTo(0);
                  } else {
                    HapticFeedback.lightImpact();
                    context.go('/');
                  }
                }
              },
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _JamTabContent(
                    onCreateJam: _showCreateJamSheet,
                    onJoinJam: _showJoinJamSheet,
                    onShareJam: _shareInviteCode,
                  ),
                  const AmiciTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Share invite code ─────────────────────────────────────────────────────

  void _shareInviteCode(Map<String, dynamic> jam) {
    final code = jam['invite_code'] as String? ?? '';
    final name = (jam['title'] ?? jam['name']) as String? ?? 'Jam';
    if (code.isEmpty) {
      Clipboard.setData(ClipboardData(text: name));
      return;
    }
    Share.share(
      context.l10n.socialShareJamBody(name, code),
      subject: context.l10n.socialShareJamSubject(name),
      sharePositionOrigin: shareOrigin(context),
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  Future<void> _showCreateJamSheet() async {
    final nameController = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      // Present on the ROOT navigator so the sheet floats above the shell's
      // floating bottom navbar. Opened on the shell navigator it renders UNDER
      // the navbar overlay (the navbar appeared in the middle of the sheet and
      // the "Crea" button could be obscured).
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: ScriptaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CreateJamSheet(
        controller: nameController,
        onConfirm: () async {
          final title = nameController.text.trim();
          if (title.isEmpty) return;
          final service = ref.read(supabaseServiceProvider);
          try {
            await service.createJam(title);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content: Text(context.l10n.errorPrefix('$e')),
                    duration: const Duration(seconds: 10)),
              );
            }
          }
        },
      ),
    );
    if (created == true) ref.invalidate(jamsProvider);
  }

  Future<void> _showJoinJamSheet() async {
    final codeController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      // Present on the ROOT navigator so the sheet floats above the shell's
      // bottom navbar overlay. Opened on the shell navigator it would render
      // UNDER the floating navbar and the "Entra" button would be untappable.
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: ScriptaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _JoinJamSheet(
        controller: codeController,
        onConfirm: () async {
          final code = codeController.text.trim();
          if (code.isEmpty) return;
          final service = ref.read(supabaseServiceProvider);
          try {
            final jam = await service.fetchJamByInviteCode(code);
            if (jam == null) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(context.l10n.jamInvalidCode)),
                );
              }
              return;
            }
            await service.joinJam(jam['id'] as String);
            if (ctx.mounted) Navigator.pop(ctx);
            ref.invalidate(jamsProvider);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content: Text(context.l10n.errorPrefix('$e')),
                    duration: const Duration(seconds: 10)),
              );
            }
          }
        },
      ),
    );
  }
}

// ─── Gradient header with Jam/Amici TabBar ────────────────────────────────────

class _SocialHeader extends StatelessWidget {
  const _SocialHeader({
    required this.tabController,
    required this.onJoin,
    required this.onSearch,
  });
  final TabController tabController;
  final VoidCallback onJoin;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    // No more green gradient bar: the header now sits directly on the page
    // background, so the system status-bar icons must be DARK (matches the
    // global default for light/cream content screens).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
      color: ScriptaColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: search icon · title · book-add icon ─────────────
          Padding(
            padding: EdgeInsets.fromLTRB(8, topPadding + 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Left: clean magnifying glass (Phosphor) ────────────
                _GlassIconButton(
                  onTap: onSearch,
                  child: Icon(
                    PhosphorIconsRegular.magnifyingGlass,
                    color: ScriptaColors.ink,
                    size: 24,
                  ),
                ),

                // ── Center: wordmark ────────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        context.l10n.jamTitle,
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: ScriptaColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Right: hashtag "join jam" icon ──────────────────────
                _GlassIconButton(
                  onTap: onJoin,
                  child: const Icon(
                    PhosphorIconsRegular.hash,
                    size: 26,
                    color: ScriptaColors.ink,
                  ),
                ),
              ],
            ),
          ),

          // ── TabBar ────────────────────────────────────────────────────
          TabBar(
            controller: tabController,
            labelColor: ScriptaColors.ink,
            unselectedLabelColor: ScriptaColors.inkFaint,
            indicatorColor: ScriptaColors.primaryDark,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2.5,
            dividerColor: Colors.transparent,
            labelStyle: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
            unselectedLabelStyle: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
            tabs: [
              Tab(text: context.l10n.socialTabJams),
              Tab(text: context.l10n.socialTabFriends),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ── Glass icon button ─────────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        // Transparent: the icons now float cleanly over the page background
        // (no green bar) instead of sitting in tinted glass chips.
        color: Colors.transparent,
        child: Center(child: child),
      ),
    );
  }
}

// ─── Custom icon: magnifying glass with person silhouette ────────────────────

class _SearchPersonPainter extends CustomPainter {
  const _SearchPersonPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width * 0.41;
    final cy = size.height * 0.41;
    final lensR = size.width * 0.295; // outer lens radius

    // ── Magnifying glass circle ────────────────────────────────────────
    canvas.drawCircle(Offset(cx, cy), lensR, p);

    // ── Handle ────────────────────────────────────────────────────────
    final handleAngle = math.pi * 0.77; // ~139°
    final hx0 = cx + lensR * math.cos(handleAngle);
    final hy0 = cy + lensR * math.sin(handleAngle);
    canvas.drawLine(
      Offset(hx0, hy0),
      Offset(size.width * 0.88, size.height * 0.88),
      p..strokeWidth = 1.9,
    );

    // ── Person: head circle ────────────────────────────────────────────
    p..strokeWidth = 1.5;
    final headR = lensR * 0.30;
    final headCy = cy - lensR * 0.14;
    canvas.drawCircle(Offset(cx, headCy), headR, p);

    // ── Person: shoulder arc (clipped inside lens) ─────────────────────
    final shoulderRect = Rect.fromCenter(
      center: Offset(cx, headCy + headR + lensR * 0.32),
      width: lensR * 1.10,
      height: lensR * 0.76,
    );
    canvas.save();
    canvas.clipRect(Rect.fromCircle(center: Offset(cx, cy), radius: lensR - 0.5));
    canvas.drawArc(shoulderRect, math.pi, math.pi, false, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SearchPersonPainter old) => old.color != color;
}

// ─── Jam tab content ──────────────────────────────────────────────────────────

class _JamTabContent extends ConsumerWidget {
  const _JamTabContent({
    required this.onCreateJam,
    required this.onJoinJam,
    required this.onShareJam,
  });

  final VoidCallback onCreateJam;
  final VoidCallback onJoinJam;
  final void Function(Map<String, dynamic>) onShareJam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jamsAsync = ref.watch(jamsProvider);

    return jamsAsync.when(
      data: (jams) => jams.isEmpty
          ? _EmptyJams(onCreateJam: onCreateJam, onJoinJam: onJoinJam)
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _JamGridCard(
                        jam: jams[i],
                        index: i,
                        onTap: () {
                          final id = jams[i]['id'] as String? ?? '';
                          final name = (jams[i]['title'] ?? jams[i]['name'])
                                  as String? ??
                              'Jam';
                          context.push(
                              '/jam/$id?name=${Uri.encodeComponent(name)}');
                        },
                        onShare: () => onShareJam(jams[i]),
                      ),
                      childCount: jams.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                  ),
                ),
              ],
            ),
      loading: () => const Center(
        child: CircularProgressIndicator(
            color: ScriptaColors.primaryDark, strokeWidth: 1.5),
      ),
      error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
    );
  }
}

// ─── Jam grid card (playlist Spotify style) ───────────────────────────────────

class _JamGridCard extends StatelessWidget {
  const _JamGridCard({
    required this.jam,
    required this.index,
    required this.onTap,
    required this.onShare,
  });

  final Map<String, dynamic> jam;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final name     = (jam['title'] ?? jam['name']) as String? ?? '';
    final code     = jam['invite_code'] as String? ?? '';
    final coverUrl = jam['cover_url']   as String?;

    final colors = [
      [const Color(0xFF4C3B3A), const Color(0xFF261E1D)],
      [const Color(0xFF7F785B), const Color(0xFF4C3B3A)],
      [const Color(0xFF5C4A40), const Color(0xFF261E1D)],
      [const Color(0xFF6B5D54), const Color(0xFF4C3B3A)],
    ];
    final palette = colors[name.hashCode.abs() % colors.length];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'J';

    // Reusable gradient fallback (no cover photo)
    Widget gradientTop = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: -20,
            right: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(12),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  initial,
                  style: ScriptaTextStyles.bookTitleLarge.copyWith(
                    fontSize: 46,
                    color: Colors.white,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    context.l10n.jamBadge,
                    style: ScriptaTextStyles.sectionTitle.copyWith(
                      color: Colors.white.withAlpha(200),
                      fontSize: 8,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: ScriptaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ScriptaColors.rule),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0E261E1D),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 65,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => gradientTop,
                          ),
                          // Subtle dark scrim so the JAM badge stays readable
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Color(0x66000000)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(60),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  context.l10n.jamBadge,
                                  style: ScriptaTextStyles.sectionTitle
                                      .copyWith(
                                    color: Colors.white.withAlpha(220),
                                    fontSize: 8,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : gradientTop,
              ),
            ),
            Expanded(
              flex: 35,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ScriptaTextStyles.bookTitle
                                .copyWith(fontSize: 13),
                          ),
                          if (code.isNotEmpty)
                            Text(
                              '# $code',
                              style: ScriptaTextStyles.label.copyWith(
                                fontSize: 9.5,
                                color: ScriptaColors.inkFaint,
                                letterSpacing: 0.8,
                              ),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onShare,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.ios_share_rounded,
                          size: 16,
                          color: ScriptaColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 60).ms)
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}

// ─── FAB ─────────────────────────────────────────────────────────────────────

class _CreateJamFab extends StatelessWidget {
  const _CreateJamFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // No bottom padding — nav bar is now a flat bar, not a floating pill.
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: ScriptaColors.primary,
      foregroundColor: const Color(0xFFF1EEE7),
      elevation: 6,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text(context.l10n.jamCreate,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}

// ─── Create Jam sheet ─────────────────────────────────────────────────────────

class _CreateJamSheet extends StatelessWidget {
  const _CreateJamSheet({required this.controller, required this.onConfirm});
  final TextEditingController controller;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Reserve the floating navbar height (64) + the device safe-area bottom so
    // the "Crea" button always clears the navbar overlay. Keep the sheet
    // bottom-anchored and calm: with no autofocus it opens low and only lifts
    // via `viewInsets` once the user taps the field (previously it auto-focused
    // and climbed up toward the notch, making the section unusable).
    const navBarHeight = 64.0;
    final navInset = navBarHeight + safeBottom;
    return Padding(
      padding:
          EdgeInsets.fromLTRB(24, 28, 24, math.max(viewInsets, navInset) + 28),
      // Scrollable so the field + header + hint + button stay fully visible
      // above the keyboard (and the top can't clip on short screens).
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle for a clearly bottom-anchored, non-fullscreen sheet.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      ScriptaColors.primaryDark,
                      ScriptaColors.primary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.group_add_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.socialNewJamTitle,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(context.l10n.socialNewJamSubtitle,
                      style: const TextStyle(
                          fontSize: 12, color: ScriptaColors.inkMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            autofocus: false,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: context.l10n.socialJamNameHint,
              prefixIcon: const Icon(Icons.auto_stories_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.socialJamCreateHint,
            style: const TextStyle(
                fontSize: 12, color: ScriptaColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onConfirm,
              child: Text(context.l10n.jamCreate),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ─── Join Jam sheet ───────────────────────────────────────────────────────────

class _JoinJamSheet extends StatelessWidget {
  const _JoinJamSheet({required this.controller, required this.onConfirm});
  final TextEditingController controller;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // Reserve the floating navbar height (64) + the device safe-area bottom so
    // the "Entra" button always clears the navbar overlay, even on the rare
    // path where this sheet is shown on the shell navigator. `navInset` is the
    // same convention route content uses (64 + MediaQuery.padding.bottom).
    const navBarHeight = 64.0;
    final navInset = navBarHeight + safeBottom;
    // Keep the sheet short and anchored to the BOTTOM of the screen so the
    // title + invite-code field + "Entra" button sit comfortably in the
    // lower-middle (previously the sheet climbed up toward the notch because
    // the field auto-focused on open and the sheet grew to clear the
    // keyboard). We no longer autofocus: the sheet opens low and calm, and
    // only lifts via `viewInsets` once the user taps the field. The bottom
    // padding is the max of the keyboard inset and the navbar inset so the CTA
    // is never obscured by either.
    return Padding(
      padding:
          EdgeInsets.fromLTRB(24, 28, 24, math.max(viewInsets, navInset) + 28),
      // Scrollable so the field + "Entra" button stay above the keyboard once
      // it opens, with no top clipping on short screens.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grab handle for a clearly bottom-anchored, non-fullscreen sheet.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ScriptaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  PhosphorIconsRegular.hash,
                  size: 20,
                  color: ScriptaColors.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.jamJoinTitle,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.ink)),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            autofocus: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: context.l10n.jamJoinHint,
              prefixIcon: const Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: onConfirm, child: Text(context.l10n.jamJoinCta)),
          ),
        ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyJams extends StatelessWidget {
  const _EmptyJams({required this.onCreateJam, required this.onJoinJam});
  final VoidCallback onCreateJam;
  final VoidCallback onJoinJam;

  @override
  Widget build(BuildContext context) {
    // Reserve the floating navbar inset (64 + safe-area bottom) as extra bottom
    // padding so the centered column — in particular the "Unisciti con codice"
    // button at the very bottom — is pushed comfortably ABOVE the navbar
    // overlay and stays fully tappable instead of falling into the bottom 64px.
    final navInset = 64.0 + MediaQuery.of(context).padding.bottom;
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(40, 40, 40, 40 + navInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    ScriptaColors.primaryDark,
                    ScriptaColors.primary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.group_rounded,
                  size: 36, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(context.l10n.jamNoJams,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
            const SizedBox(height: 10),
            Text(
              context.l10n.jamNoJamsBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: ScriptaColors.inkMuted,
                  height: 1.6,
                  fontSize: 14),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreateJam,
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.jamCreateFirst),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onJoinJam,
              icon: const Icon(
                PhosphorIconsRegular.hash,
                size: 18,
                color: ScriptaColors.primaryDark,
              ),
              label: Text(context.l10n.jamJoinWithCode),
              style: OutlinedButton.styleFrom(
                foregroundColor: ScriptaColors.primaryDark,
                side: const BorderSide(color: ScriptaColors.primaryDark),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Unauthenticated ──────────────────────────────────────────────────────────

class _UnauthenticatedState extends StatelessWidget {
  const _UnauthenticatedState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      body: Column(
        children: [
          // Cream header (matches the signed-in _SocialHeader and the Library
          // look) — replaces the old dark forest-green gradient bar.
          Container(
            width: double.infinity,
            color: ScriptaColors.background,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Text(context.l10n.socialTitle,
                    style: const TextStyle(
                        color: ScriptaColors.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6)),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                          color: ScriptaColors.siennaFaint,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.lock_rounded,
                          size: 32, color: ScriptaColors.primaryDark),
                    ),
                    const SizedBox(height: 24),
                    Text(context.l10n.profileLoginRequired,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.profileLoginBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: ScriptaColors.inkMuted,
                          height: 1.6,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => context.push('/auth'),
                      child: Text(context.l10n.profileLoginCta),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

