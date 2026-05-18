import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/services/export_service.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final myProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return null;
  try {
    return await svc.fetchProfile();
  } catch (_) {
    return null;
  }
});

final myStatsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return {};
  try {
    return await svc.fetchMyStats();
  } catch (_) {
    return {};
  }
});

final mySharedHighlightsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchMySharedHighlights();
  } catch (_) {
    return [];
  }
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final statsAsync = ref.watch(myStatsProvider);
    final sharedHighlightsAsync = ref.watch(mySharedHighlightsProvider);

    // Derived values (with fallbacks while loading)
    final profile = profileAsync.asData?.value;
    final displayName = profile?['display_name'] as String? ??
        user?.email?.split('@').first ??
        'Lettore';
    final readingTitle = profile?['currently_reading_title'] as String?;
    final readingAuthor = profile?['currently_reading_author'] as String?;
    final stats = statsAsync.asData?.value ?? {};
    final sharedHighlights =
        sharedHighlightsAsync.asData?.value ?? [];

    if (user == null) return const _UnauthenticatedProfile();

    final initial = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : user.email?[0].toUpperCase() ?? 'L';

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Profile header ────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            stretch: true,
            backgroundColor: MarginaliaColors.primary,
            foregroundColor: const Color(0xFFF1EEE7),
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Impostazioni',
                onPressed: () => _showSettingsSheet(context, ref, profile),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              title: Text(
                displayName,
                style: const TextStyle(
                  color: Color(0xFFF1EEE7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              titlePadding:
                  const EdgeInsetsDirectional.fromSTEB(56, 0, 56, 16),
              background: Container(
                decoration: MarginaliaDecorations.gradientHeader,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Avatar ──────────────────────────────────────
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                MarginaliaDecorations.bookCoverColor(
                                    displayName),
                                MarginaliaColors.primaryDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(43),
                            border: Border.all(
                              color: const Color(0xFFF1EEE7).withAlpha(60),
                              width: 3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x40261E1D),
                                blurRadius: 20,
                                offset: Offset(0, 6),
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
                        const SizedBox(height: 14),

                        // ── Display name ────────────────────────────────
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Color(0xFFF1EEE7),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.email ?? '',
                          style: TextStyle(
                            color: const Color(0xFFF1EEE7).withAlpha(140),
                            fontSize: 12,
                          ),
                        ),

                        // ── Currently reading (bio) ──────────────────────
                        if (readingTitle != null &&
                            readingTitle.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.menu_book_outlined,
                                  size: 14, color: Color(0xAAF1EEE7)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '$readingTitle'
                                  '${(readingAuthor ?? '').isNotEmpty ? ' · $readingAuthor' : ''}',
                                  style: TextStyle(
                                    color: const Color(0xFFF1EEE7)
                                        .withAlpha(200),
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Stats row ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StatsRow(stats: stats),
          ),

          // ── Action buttons ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showEditProfileSheet(context, ref, profile),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Modifica profilo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MarginaliaColors.primary,
                        side: const BorderSide(color: MarginaliaColors.rule),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Share.share(
                      'Leggo su Marginalia 📚\n'
                      'Vieni a leggere con me!\nhttps://marginalia.app',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MarginaliaColors.primary,
                      side: const BorderSide(color: MarginaliaColors.rule),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    child: const Icon(Icons.ios_share_outlined, size: 16),
                  ),
                ],
              ),
            ),
          ),

          // ── Currently reading card (if set) ───────────────────────────
          if (readingTitle != null && readingTitle.isNotEmpty)
            SliverToBoxAdapter(
              child: _CurrentlyReadingCard(
                title: readingTitle,
                author: readingAuthor,
                onTap: () =>
                    _showEditProfileSheet(context, ref, profile),
              ),
            ),

          // ── Shared highlights grid ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Text('NELLE JAM',
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 8),
                  Text(
                    sharedHighlights.isNotEmpty
                        ? '${sharedHighlights.length}'
                        : '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: MarginaliaColors.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.rule)),
                ],
              ),
            ),
          ),

          if (sharedHighlights.isEmpty)
            SliverToBoxAdapter(
              child: _EmptySharedHighlights(
                onShare: () => context.go('/social'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _SharedHighlightCell(
                    data: sharedHighlights[i],
                    index: i,
                  ),
                  childCount: sharedHighlights.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                  childAspectRatio: 1.0,
                ),
              ),
            ),

          // ── Settings section ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Row(
                children: [
                  Text('IMPOSTAZIONI',
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.rule)),
                ],
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildListDelegate([
              _SettingsTile(
                icon: Icons.sync_outlined,
                label: 'Sincronizza con Kindle',
                subtitle: 'Accedi ad Amazon e importa gli highlight',
                onTap: () => context.push('/sync/kindle'),
              ),
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                label: 'Importa My Clippings.txt',
                subtitle: 'Importa manualmente dal file Kindle',
                onTap: () => context.go('/'),
              ),
              _SettingsTile(
                icon: Icons.download_outlined,
                label: 'Esporta in Markdown',
                subtitle: 'Scarica tutti i tuoi highlight come file .md',
                onTap: () => _exportAllHighlights(context, ref),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () {},
                trailing: const Icon(Icons.open_in_new,
                    size: 14, color: MarginaliaColors.inkFaint),
              ),
              const _SettingsTile(
                icon: Icons.info_outline,
                label: 'Versione',
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(
                      color: MarginaliaColors.inkFaint, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              // Sign out
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(supabaseServiceProvider).signOut();
                  },
                  icon: const Icon(Icons.logout_outlined, size: 16),
                  label: const Text('Esci dall\'account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB54848),
                    side: const BorderSide(color: Color(0xFFD4AAAA)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Export all highlights ─────────────────────────────────────────────────

  Future<void> _exportAllHighlights(
      BuildContext context, WidgetRef ref) async {
    // Show a loading snackbar while preparing the export
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Preparando il file…'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    try {
      // allHighlightsProvider is cross-platform (Isar on native, Supabase on
      // web) and already loads book links so bookTitle / bookAuthor are set.
      final highlights = await ref.read(allHighlightsProvider.future);

      if (highlights.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                    'Nessun highlight da esportare. '
                    'Importa prima My Clippings.txt.'),
              ),
            );
        }
        return;
      }

      await ExportService.exportAll(highlights);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('Errore durante l\'esportazione: $e')),
          );
      }
    }
  }

  // ── Edit profile sheet ────────────────────────────────────────────────────

  Future<void> _showEditProfileSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? profile,
  ) async {
    final nameController = TextEditingController(
        text: profile?['display_name'] as String? ?? '');
    final titleController = TextEditingController(
        text: profile?['currently_reading_title'] as String? ?? '');
    final authorController = TextEditingController(
        text: profile?['currently_reading_author'] as String? ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Modifica profilo',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Nome visualizzato',
                prefixIcon: Icon(Icons.person_outline),
                labelText: 'Nome',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'STO LEGGENDO',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: MarginaliaColors.inkMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Titolo del libro',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Autore (opzionale)',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final svc = ref.read(supabaseServiceProvider);
                  try {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      await svc.updateDisplayName(name);
                    }
                    final t = titleController.text.trim();
                    final a = authorController.text.trim();
                    await svc.updateCurrentlyReading(
                      title: t.isEmpty ? null : t,
                      author: a.isEmpty ? null : a,
                    );
                    ref.invalidate(myProfileProvider);
                    ref.invalidate(myStatsProvider);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Errore: $e')));
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Salva'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Settings sheet (gear icon) ────────────────────────────────────────────

  void _showSettingsSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? profile,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: MarginaliaColors.primary),
              title: const Text('Modifica profilo'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditProfileSheet(context, ref, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_outlined,
                  color: MarginaliaColors.primary),
              title: const Text('Sincronizza con Kindle'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/sync/kindle');
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined,
                  color: MarginaliaColors.primary),
              title: const Text('Importa My Clippings.txt'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/');
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.logout_outlined,
                  color: Color(0xFFB54848)),
              title: const Text('Esci dall\'account',
                  style: TextStyle(color: Color(0xFFB54848))),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(supabaseServiceProvider).signOut();
              },
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: MarginaliaDecorations.card(),
      child: Row(
        children: [
          _StatBox(label: 'Libri', value: stats['books'] ?? 0),
          _Divider(),
          _StatBox(label: 'Highlight', value: stats['highlights'] ?? 0),
          _Divider(),
          _StatBox(label: 'Jam', value: stats['jams'] ?? 0),
          _Divider(),
          _StatBox(label: 'Seguiti', value: stats['following'] ?? 0),
          _Divider(),
          _StatBox(label: 'Seguaci', value: stats['followers'] ?? 0),
        ],
      ),
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
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: MarginaliaColors.inkMuted,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: MarginaliaColors.rule,
    );
  }
}

// ─── Currently reading card ───────────────────────────────────────────────────

class _CurrentlyReadingCard extends StatelessWidget {
  const _CurrentlyReadingCard({
    required this.title,
    this.author,
    required this.onTap,
  });
  final String title;
  final String? author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final coverColor = MarginaliaDecorations.bookCoverColor(title);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: MarginaliaDecorations.card(),
        child: Row(
          children: [
            // Mini book cover
            Container(
              width: 44,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [coverColor, MarginaliaColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x22261E1D),
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: const Center(
                child: Icon(Icons.menu_book_outlined,
                    size: 18, color: Color(0xCCF1EEE7)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STO LEGGENDO',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: MarginaliaColors.sienna,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: MarginaliaTextStyles.bookTitle
                        .copyWith(fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((author ?? '').isNotEmpty)
                    Text(
                      (author!).toUpperCase(),
                      style: MarginaliaTextStyles.bookAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 16, color: MarginaliaColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

// ─── Shared highlight cell (Instagram-style grid) ─────────────────────────────

class _SharedHighlightCell extends StatelessWidget {
  const _SharedHighlightCell({required this.data, required this.index});
  final Map<String, dynamic> data;
  final int index;

  @override
  Widget build(BuildContext context) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final content = highlight?['content'] as String? ?? '';
    final book = highlight?['books'] as Map<String, dynamic>?;
    final bookTitle = book?['title'] as String? ?? '';
    final jam = data['jams'] as Map<String, dynamic>?;
    final jamTitle = jam?['title'] as String? ?? '';
    final color = highlight?['color'] as String?;

    final bgColor = _bgFor(color, bookTitle);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor, _darken(bgColor)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Content
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    content.length > 80
                        ? '${content.substring(0, 80)}…'
                        : content,
                    style: const TextStyle(
                      color: Color(0xEEF1EEE7),
                      fontSize: 11,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.fade,
                  ),
                ),
                const SizedBox(height: 4),
                if (bookTitle.isNotEmpty)
                  Text(
                    bookTitle,
                    style: const TextStyle(
                      color: Color(0xAAF1EEE7),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Jam badge (top-right)
          if (jamTitle.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  jamTitle.length > 8
                      ? '${jamTitle.substring(0, 8)}…'
                      : jamTitle,
                  style: const TextStyle(
                    color: Color(0xDDF1EEE7),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 220.ms, curve: Curves.easeOut);
  }

  Color _bgFor(String? color, String bookTitle) => switch (color) {
        'yellow' => const Color(0xFFB8860B),
        'blue' => const Color(0xFF3A6B8A),
        'pink' => const Color(0xFF8A3A5A),
        'orange' => const Color(0xFF8A5A28),
        _ => MarginaliaDecorations.bookCoverColor(bookTitle),
      };

  Color _darken(Color c) => Color.fromARGB(
        255,
        (c.red * 0.65).round(),
        (c.green * 0.65).round(),
        (c.blue * 0.65).round(),
      );
}

// ─── Empty shared highlights ──────────────────────────────────────────────────

class _EmptySharedHighlights extends StatelessWidget {
  const _EmptySharedHighlights({required this.onShare});
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MarginaliaColors.rule),
        ),
        child: Column(
          children: [
            const Icon(Icons.share_outlined,
                size: 28, color: MarginaliaColors.inkFaint),
            const SizedBox(height: 10),
            const Text(
              'Nessun highlight condiviso',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Condividi un highlight in una Jam\nper vederlo qui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: MarginaliaColors.inkFaint, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onShare,
              child: const Text('Vai alle Jam'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: MarginaliaColors.primary, size: 22),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(
                  fontSize: 12, color: MarginaliaColors.inkMuted))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right,
                  color: MarginaliaColors.inkFaint, size: 18)
              : null),
      onTap: onTap,
    );
  }
}

// ─── Unauthenticated state ────────────────────────────────────────────────────

class _UnauthenticatedProfile extends StatelessWidget {
  const _UnauthenticatedProfile();

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
                padding: EdgeInsets.fromLTRB(20, 20, 20, 36),
                child: Text('Profilo',
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
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.person_outline,
                          size: 32, color: MarginaliaColors.primary),
                    ),
                    const SizedBox(height: 24),
                    const Text('Accedi per vedere il profilo',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    const Text(
                      'Tieni traccia dei tuoi libri,\nhighlight e connessioni.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: MarginaliaColors.inkMuted,
                          height: 1.65,
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
