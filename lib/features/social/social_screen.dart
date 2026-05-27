import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: MarginaliaColors.background,
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
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
      'Join my Jam "$name" on Marginalia.\n\n'
      'Invite code: $code',
      subject: 'Marginalia Jam – $name',
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  Future<void> _showCreateJamSheet() async {
    final nameController = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surfaceElevated,
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
                    content: Text('Error: $e'),
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
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surfaceElevated,
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
                  const SnackBar(content: Text('Invalid code.')),
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
                    content: Text('Error: $e'),
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

  static const _cream = Color(0xFFF1EEE7);

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      decoration: MarginaliaDecorations.gradientHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: search icon · title · book-add icon ─────────────
          Padding(
            padding: EdgeInsets.fromLTRB(8, topPadding + 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Left: search-person icon ────────────────────────────
                _GlassIconButton(
                  onTap: onSearch,
                  child: CustomPaint(
                    size: const Size(26, 26),
                    painter: _SearchPersonPainter(color: _cream),
                  ),
                ),

                // ── Center: wordmark ────────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Jam',
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: _cream,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Right: book-add icon ────────────────────────────────
                _GlassIconButton(
                  onTap: onJoin,
                  child: CustomPaint(
                    size: const Size(26, 26),
                    painter: _BookAddPainter(color: _cream),
                  ),
                ),
              ],
            ),
          ),

          // ── TabBar ────────────────────────────────────────────────────
          TabBar(
            controller: tabController,
            labelColor: _cream,
            unselectedLabelColor: _cream.withAlpha(110),
            indicatorColor: _cream,
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
            tabs: const [
              Tab(text: 'Jams'),
              Tab(text: 'Friends'),
            ],
          ),
        ],
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
        decoration: BoxDecoration(
          color: const Color(0xFFF1EEE7).withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFF1EEE7).withAlpha(35),
            width: 1,
          ),
        ),
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

// ─── Custom icon: open book with + badge ─────────────────────────────────────

class _BookAddPainter extends CustomPainter {
  const _BookAddPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // ── Left page ─────────────────────────────────────────────────────
    final leftPage = Path()
      ..moveTo(w * 0.50, h * 0.16)
      ..cubicTo(
        w * 0.38, h * 0.14,
        w * 0.16, h * 0.20,
        w * 0.12, h * 0.26,
      )
      ..lineTo(w * 0.12, h * 0.84)
      ..cubicTo(
        w * 0.16, h * 0.78,
        w * 0.36, h * 0.74,
        w * 0.50, h * 0.76,
      )
      ..close();
    canvas.drawPath(leftPage, p);

    // ── Right page ────────────────────────────────────────────────────
    final rightPage = Path()
      ..moveTo(w * 0.50, h * 0.16)
      ..cubicTo(
        w * 0.62, h * 0.14,
        w * 0.84, h * 0.20,
        w * 0.88, h * 0.26,
      )
      ..lineTo(w * 0.88, h * 0.84)
      ..cubicTo(
        w * 0.84, h * 0.78,
        w * 0.64, h * 0.74,
        w * 0.50, h * 0.76,
      )
      ..close();
    canvas.drawPath(rightPage, p);

    // ── Spine line ────────────────────────────────────────────────────
    canvas.drawLine(Offset(w * 0.50, h * 0.16), Offset(w * 0.50, h * 0.76),
        p..strokeWidth = 1.3);

    // ── + badge (top-right area, inside right page) ───────────────────
    final px = w * 0.72;
    final py = h * 0.42;
    final arm = w * 0.11;
    p..strokeWidth = 1.7..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(px - arm, py), Offset(px + arm, py), p); // horizontal
    canvas.drawLine(Offset(px, py - arm), Offset(px, py + arm), p); // vertical
  }

  @override
  bool shouldRepaint(_BookAddPainter old) => old.color != color;
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
            color: MarginaliaColors.sienna, strokeWidth: 1.5),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
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
                  style: MarginaliaTextStyles.bookTitleLarge.copyWith(
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
                    'JAM',
                    style: MarginaliaTextStyles.sectionTitle.copyWith(
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
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MarginaliaColors.rule),
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
                                  'JAM',
                                  style: MarginaliaTextStyles.sectionTitle
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
                            style: MarginaliaTextStyles.bookTitle
                                .copyWith(fontSize: 13),
                          ),
                          if (code.isNotEmpty)
                            Text(
                              '# $code',
                              style: MarginaliaTextStyles.label.copyWith(
                                fontSize: 9.5,
                                color: MarginaliaColors.inkFaint,
                                letterSpacing: 0.8,
                              ),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onShare,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.ios_share_outlined,
                          size: 16,
                          color: MarginaliaColors.inkFaint,
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
      backgroundColor: MarginaliaColors.primary,
      foregroundColor: const Color(0xFFF1EEE7),
      elevation: 6,
      icon: const Icon(Icons.add, size: 20),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C3B3A), Color(0xFF261E1D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.group_add_outlined,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New Jam',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text('Create a new reading circle',
                      style: TextStyle(
                          fontSize: 12, color: MarginaliaColors.inkMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. "20th Century Classics"',
              prefixIcon: Icon(Icons.auto_stories_outlined),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You will receive an invite code to share with friends.',
            style: TextStyle(
                fontSize: 12, color: MarginaliaColors.inkMuted, height: 1.5),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MarginaliaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.link_outlined,
                    color: MarginaliaColors.sienna, size: 18),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.jamJoinTitle,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: context.l10n.jamJoinHint,
              prefixIcon: const Icon(Icons.tag_outlined),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4C3B3A), Color(0xFF261E1D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.group_outlined,
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
                  color: MarginaliaColors.inkMuted,
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
              icon: const Icon(Icons.link_outlined, size: 18),
              label: Text(context.l10n.jamJoinWithCode),
              style: OutlinedButton.styleFrom(
                foregroundColor: MarginaliaColors.sienna,
                side: const BorderSide(color: MarginaliaColors.sienna),
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
      backgroundColor: MarginaliaColors.background,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: MarginaliaDecorations.gradientHeader,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Text(context.l10n.socialTitle,
                    style: const TextStyle(
                        color: Color(0xFFF1EEE7),
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
                          color: MarginaliaColors.siennaFaint,
                          borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.lock_outline,
                          size: 32, color: MarginaliaColors.sienna),
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
                          color: MarginaliaColors.inkMuted,
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

