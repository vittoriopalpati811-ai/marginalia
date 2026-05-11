import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';

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

class _SocialScreenState extends ConsumerState<SocialScreen> {
  @override
  Widget build(BuildContext context) {
    final isAuth = ref.watch(isAuthenticatedProvider);

    if (!isAuth) return _UnauthenticatedState();

    final jamsAsync = ref.watch(jamsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        slivers: [
          // ── App bar con gradiente ────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: MarginaliaDecorations.gradientHeader,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'Jam',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Le tue cerchie di lettura',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              titlePadding: EdgeInsets.zero,
              title: const SizedBox.shrink(),
            ),
            backgroundColor: MarginaliaColors.sienna,
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                tooltip: 'Crea Jam',
                onPressed: _showCreateJamSheet,
              ),
              IconButton(
                icon: const Icon(Icons.group_add_outlined, color: Colors.white),
                tooltip: 'Unisciti con codice',
                onPressed: _showJoinJamSheet,
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ── Contenuto ───────────────────────────────────────────────────
          jamsAsync.when(
            data: (jams) => jams.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyJams(
                      onCreateJam: _showCreateJamSheet,
                      onJoinJam: _showJoinJamSheet,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverList.builder(
                      itemCount: jams.length,
                      itemBuilder: (ctx, i) => _JamCard(
                        jam: jams[i],
                        index: i,
                        onTap: () {
                          final id = jams[i]['id'] as String? ?? '';
                          final name = jams[i]['name'] as String? ?? 'Jam';
                          context.push('/jam/$id?name=${Uri.encodeComponent(name)}');
                        },
                      ),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Errore: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateJamSheet() async {
    final nameController = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.siennaFaint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group_add_outlined,
                      color: MarginaliaColors.sienna, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Nuova Jam',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'es. "Il Nome della Rosa"',
                prefixIcon: Icon(Icons.auto_stories_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  final service = ref.read(supabaseServiceProvider);
                  await service.createJam(nameController.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Crea Jam'),
              ),
            ),
          ],
        ),
      ),
    );
    if (created == true) ref.invalidate(jamsProvider);
  }

  Future<void> _showJoinJamSheet() async {
    final codeController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.siennaFaint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.link_outlined,
                      color: MarginaliaColors.sienna, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Unisciti a una Jam',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: codeController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Incolla il codice invito',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final code = codeController.text.trim();
                  if (code.isEmpty) return;
                  final service = ref.read(supabaseServiceProvider);
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
                },
                child: const Text('Unisciti'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Jam card ─────────────────────────────────────────────────────────────────

class _JamCard extends StatelessWidget {
  const _JamCard({required this.jam, required this.index, required this.onTap});

  final Map<String, dynamic> jam;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = jam['name'] as String? ?? '';
    final code = jam['invite_code'] as String? ?? '';
    final memberCount = (jam['jam_members'] as List?)?.length ?? 0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'J';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: MarginaliaDecorations.card(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: MarginaliaTextStyles.bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '$memberCount ${memberCount == 1 ? "membro" : "membri"}',
                      style: MarginaliaTextStyles.bookAuthor,
                    ),
                  ],
                ),
              ),
              if (code.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_outlined,
                      size: 18, color: MarginaliaColors.inkFaint),
                  tooltip: 'Copia codice invito',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Codice invito copiato!')),
                    );
                  },
                ),
              const Icon(Icons.chevron_right,
                  color: MarginaliaColors.inkFaint, size: 18),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 50).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.04, end: 0, duration: 300.ms);
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
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.group_outlined, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nessuna Jam ancora',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Crea una cerchia di lettura\no unisciti a quella di un amico.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreateJam,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crea Jam'),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Unauthenticated state ────────────────────────────────────────────────────

class _UnauthenticatedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Column(
        children: [
          // Header gradient
          Container(
            width: double.infinity,
            decoration: MarginaliaDecorations.gradientHeader,
            child: SafeArea(
              bottom: false,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Text(
                  'Jam',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          // Content
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
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.lock_outline,
                          size: 32, color: MarginaliaColors.sienna),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Accedi per usare le Jam',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: MarginaliaColors.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Le cerchie di lettura richiedono\nun account Marginalia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MarginaliaColors.inkMuted,
                        height: 1.6,
                        fontSize: 14,
                      ),
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
