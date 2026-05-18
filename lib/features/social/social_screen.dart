import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';
import 'amici_tab.dart';
import 'feed_tab.dart';

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
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
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
      // FAB: Post on Feed (index 0), new Jam on Jam (index 1)
      floatingActionButton: _tabController.index == 1
          ? _CreateJamFab(onTap: _showCreateJamSheet)
          : _tabController.index == 0
              ? _CreatePostFab(onTap: _showCreatePostSheet)
              : null,
      body: Column(
        children: [
          // ── Gradient header with embedded TabBar ──────────────────────
          _SocialHeader(
            tabController: _tabController,
            onJoin: _showJoinJamSheet,
          ),
          // ── Tab content ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const FeedTab(),
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
      '📚 Unisciti alla mia Jam "$name" su Marginalia!\n\n'
      'Codice invito: $code',
      subject: 'Marginalia Jam – $name',
    );
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  Future<void> _showCreatePostSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => CreatePostSheet(
        onCreated: () => ref.invalidate(postsProvider),
      ),
    );
  }

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
                    content: Text('Errore: $e'),
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
                  const SnackBar(content: Text('Codice non valido.')),
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
                    content: Text('Errore: $e'),
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
  const _SocialHeader({required this.tabController, required this.onJoin});
  final TabController tabController;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      decoration: MarginaliaDecorations.gradientHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top row: title + join button ──────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding + 16, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Jam',
                        style: TextStyle(
                          color: Color(0xFFF1EEE7),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Feed, Jam e amici lettori',
                        style: TextStyle(
                          color: const Color(0xFFF1EEE7).withAlpha(160),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.link_outlined,
                      size: 15, color: Color(0xFFF1EEE7)),
                  label: const Text(
                    'Unisciti',
                    style: TextStyle(color: Color(0xFFF1EEE7), fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFF1EEE7).withAlpha(25),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),

          // ── TabBar ────────────────────────────────────────────────────
          TabBar(
            controller: tabController,
            labelColor: const Color(0xFFF1EEE7),
            unselectedLabelColor:
                const Color(0xFFF1EEE7).withAlpha(110),
            indicatorColor: const Color(0xFFF1EEE7),
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2.5,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Feed'),
              Tab(text: 'Jam'),
              Tab(text: 'Amici'),
            ],
          ),
        ],
      ),
    );
  }
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
      error: (e, _) => Center(child: Text('Errore: $e')),
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
    final name = (jam['title'] ?? jam['name']) as String? ?? '';
    final code = jam['invite_code'] as String? ?? '';

    final colors = [
      [const Color(0xFF4C3B3A), const Color(0xFF261E1D)],
      [const Color(0xFF7F785B), const Color(0xFF4C3B3A)],
      [const Color(0xFF5C4A40), const Color(0xFF261E1D)],
      [const Color(0xFF6B5D54), const Color(0xFF4C3B3A)],
    ];
    final palette = colors[name.hashCode.abs() % colors.length];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'J';

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
              child: Container(
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
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'JAM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                              style: const TextStyle(
                                fontSize: 10,
                                color: MarginaliaColors.inkFaint,
                                letterSpacing: 0.5,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 96),
      child: FloatingActionButton.extended(
        onPressed: onTap,
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        elevation: 6,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Nuova Jam',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}

// ─── Post FAB ─────────────────────────────────────────────────────────────────

class _CreatePostFab extends StatelessWidget {
  const _CreatePostFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 96),
      child: FloatingActionButton.extended(
        onPressed: onTap,
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        elevation: 6,
        icon: const Icon(Icons.edit_outlined, size: 20),
        label: const Text('Nuovo post',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
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
                  Text('Nuova Jam',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text('Crea una nuova Jam',
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
              hintText: 'es. "Classici del Novecento"',
              prefixIcon: Icon(Icons.auto_stories_outlined),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Riceverai un codice invito da condividere con gli amici.',
            style: TextStyle(
                fontSize: 12, color: MarginaliaColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onConfirm,
              child: const Text('Crea Jam'),
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
              const Text('Unisciti a una Jam',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Codice invito (es. ABC123)',
              prefixIcon: Icon(Icons.tag_outlined),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: onConfirm, child: const Text('Unisciti')),
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
            const Text('Nessuna Jam ancora',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
            const SizedBox(height: 10),
            const Text(
              'Crea una Jam o\nunisciti a quella di un amico.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: MarginaliaColors.inkMuted,
                  height: 1.6,
                  fontSize: 14),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreateJam,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crea la prima Jam'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onJoinJam,
              icon: const Icon(Icons.link_outlined, size: 18),
              label: const Text('Unisciti con codice'),
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
              child: const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Text('Sociale',
                    style: TextStyle(
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
                    const Text('Accedi per le Jam',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    const Text(
                      'Le Jam e il feed sociale\nrichiedono un account Marginalia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: MarginaliaColors.inkMuted,
                          height: 1.6,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => context.push('/auth'),
                      child: const Text('Accedi o Registrati'),
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
