import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/utils/share_helper.dart';
import 'privacy_policy_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/export_service.dart';
import '../../core/services/clippings_importer.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/services/gender_service.dart';
import '../widget/widget_preview_screen.dart';

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
        'Reader';
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
                tooltip: 'Settings',
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
                      label: Text(context.l10n.profileEditProfile),
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
                      'I read on Marginalia\n'
                      'Come read with me!\nhttps://marginalia.app',
                      sharePositionOrigin: shareOrigin(context),
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
                  Text('IN JAMS',
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
                  Text('SETTINGS',
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
                label: 'Sync with Kindle',
                subtitle: 'Sign in to Amazon and import highlights',
                onTap: () => context.push('/sync/kindle'),
              ),
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                label: 'Import My Clippings.txt',
                subtitle: 'Manually import from your Kindle file',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final res = await pickAndImportClippings(ref);
                    if (res == null) return; // user cancelled
                    ref.invalidate(allHighlightsProvider);
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                          'Importati ${res.highlightsAdded} highlight da ${res.booksAdded} libri'),
                    ));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('Errore durante l\'import: $e')));
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.menu_book_outlined,
                label: 'Importa da Kobo',
                subtitle: 'Seleziona il file KoboReader.sqlite del tuo Kobo',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final res = await pickAndImportKobo(ref);
                    if (res == null) return; // user cancelled
                    ref.invalidate(allHighlightsProvider);
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                          'Importati ${res.highlightsAdded} highlight da ${res.booksAdded} libri'),
                    ));
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('Errore import Kobo: $e')));
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.download_outlined,
                label: 'Export as Markdown',
                subtitle: 'Download all your highlights as a .md file',
                onTap: () => _exportAllHighlights(context, ref),
              ),
              _SettingsTile(
                icon: Icons.widgets_outlined,
                label: 'iOS Widget',
                subtitle: 'Preview and update the home screen widget',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WidgetPreviewScreen(),
                  ),
                ),
              ),
              const _SettingsTile(
                icon: Icons.info_outline,
                label: 'Version',
                trailing: Text(
                  '1.0.0',
                  style: TextStyle(
                      color: MarginaliaColors.inkFaint, fontSize: 13),
                ),
              ),

              // ── PERSONALIZZAZIONE section ──────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text('PERSONALIZZAZIONE',
                        style: MarginaliaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: MarginaliaColors.rule)),
                  ],
                ),
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: 'Personalizzazione frasi',
                subtitle: _genderSubtitle(ref.watch(genderProvider)),
                onTap: () => _showCyclePersonalizationSheet(context, ref),
              ),

              // ── PRIVACY & DATA section ─────────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text('PRIVACY & DATA',
                        style: MarginaliaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: MarginaliaColors.rule)),
                  ],
                ),
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                label: 'Your Data',
                subtitle: 'What we store and how we use it',
                onTap: () => _showYourDataSheet(context),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: context.l10n.settingsPrivacyPolicy,
                onTap: () async {
                  // Route to the localized privacy page based on the
                  // user's current app locale.
                  final isIt = Localizations.localeOf(context).languageCode == 'it';
                  final url = isIt
                      ? 'https://vittoriopalpati811-ai.github.io/marginalia/privacy/it/'
                      : 'https://vittoriopalpati811-ai.github.io/marginalia/privacy/';
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
                trailing: const Icon(Icons.open_in_new,
                    size: 14, color: MarginaliaColors.inkFaint),
              ),
              _SettingsTile(
                icon: Icons.delete_forever_outlined,
                label: 'Delete Account',
                subtitle: 'Permanently delete your account and all data',
                onTap: () => _showDeleteAccountDialog(context, ref),
                trailing: const Icon(Icons.chevron_right,
                    color: Color(0xFFB54848), size: 18),
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
                  label: Text(context.l10n.settingsSignOut),
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
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(context.l10n.settingsPreparingFile),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    try {
      final shareRect = shareOrigin(context);
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
                    'No highlights to export. '
                    'Import My Clippings.txt first.'),
              ),
            );
        }
        return;
      }

      await ExportService.exportAll(highlights, sharePositionOrigin: shareRect);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('Export error: $e')),
          );
      }
    }
  }

  // ── Your Data bottom sheet (GDPR transparency) ────────────────────────────

  void _showYourDataSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).padding.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your Data',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            const SizedBox(height: 16),
            _DataRow(
              icon: Icons.email_outlined,
              title: 'Email address',
              body: 'Used for account authentication only.',
            ),
            _DataRow(
              icon: Icons.format_quote_outlined,
              title: 'Highlights & books',
              body: 'Stored in our database to sync across devices. '
                  'You can export or delete them at any time.',
            ),
            _DataRow(
              icon: Icons.favorite_border,
              title: 'Health data (steps, workouts, menstrual cycle)',
              body: 'Processed on-device only to personalise your daily '
                  'highlight. Never uploaded.',
            ),
            _DataRow(
              icon: Icons.location_on_outlined,
              title: 'Weather location',
              body: 'Used on-device only to fetch weather context for your '
                  'daily highlight. Never stored.',
            ),
            const SizedBox(height: 8),
            const Text(
              'No advertising. No tracking. No data sold.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.sienna,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Daily-phrase personalisation (gender / cycle) ─────────────────────────
  //
  // Lets users who already finished onboarding set (or change) the same
  // preference the onboarding gender step captures, so the cycle-aware tone can
  // be enabled later. The value is stored ONLY on-device (GenderService) and the
  // in-memory provider is updated so the subtitle reacts immediately.
  Future<void> _showCyclePersonalizationSheet(
      BuildContext context, WidgetRef ref) async {
    final current = ref.read(genderProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).padding.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Personalizzazione frasi',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'La frase del giorno è scelta per te. Se vuoi, può tenere conto '
              'anche del tuo ciclo mestruale: succede solo se scegli «Donna» e '
              'solo con i dati di Salute del tuo iPhone, che restano sul '
              'dispositivo e non vengono mai caricati.',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: MarginaliaColors.inkMuted),
            ),
            const SizedBox(height: 16),
            _GenderChoiceRow(
              label: 'Donna',
              hint: 'Le frasi possono tenere conto del ciclo',
              selected: current == 'female',
              onTap: () => _setGender(ctx, ref, 'female'),
            ),
            _GenderChoiceRow(
              label: 'Uomo',
              hint: null,
              selected: current == 'male',
              onTap: () => _setGender(ctx, ref, 'male'),
            ),
            _GenderChoiceRow(
              label: 'Preferisco non dirlo',
              hint: 'Nessuna frase legata al ciclo',
              selected: current == 'unspecified',
              onTap: () => _setGender(ctx, ref, 'unspecified'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setGender(
      BuildContext sheetContext, WidgetRef ref, String value) async {
    await GenderService.write(value);
    // Update the live provider so the daily subtitle (which watches it)
    // recomputes without an app restart.
    ref.read(genderProvider.notifier).state = value;
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  }

  // ── Delete account confirmation dialog ────────────────────────────────────

  Future<void> _showDeleteAccountDialog(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.settingsDeleteAccountTitle,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          context.l10n.settingsDeleteAccountBody,
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB54848)),
            child: Text(context.l10n.settingsDeleteAccountConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(supabaseServiceProvider).deleteAccount();
      // Navigate to auth screen after account deletion.
      if (context.mounted) context.go('/auth');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsDeleteAccountError(e.toString()))),
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
            Text(context.l10n.settingsEditProfileTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    letterSpacing: -0.4)),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: context.l10n.editProfileDisplayName,
                prefixIcon: const Icon(Icons.person_outline),
                labelText: context.l10n.editProfileName,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.editProfileCurrentlyReadingLabel,
              style: const TextStyle(
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
              decoration: InputDecoration(
                hintText: context.l10n.editProfileBookTitleHint,
                prefixIcon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: context.l10n.editProfileAuthorHint,
                prefixIcon: const Icon(Icons.person_outline),
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
                          SnackBar(content: Text(context.l10n.feedErrorPrefix(e.toString()))));
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(context.l10n.save),
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
        child: ListTileTheme(
          data: const ListTileThemeData(textColor: MarginaliaColors.ink),
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
              title: Text(context.l10n.profileEditProfile),
              onTap: () {
                Navigator.pop(ctx);
                _showEditProfileSheet(context, ref, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined,
                  color: MarginaliaColors.primary),
              title: Text(context.l10n.statsTitle),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/stats');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_outlined,
                  color: MarginaliaColors.primary),
              title: Text(context.l10n.settingsSyncWithKindle),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/sync/kindle');
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined,
                  color: MarginaliaColors.primary),
              title: Text(context.l10n.settingsImportClippings),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined,
                  color: MarginaliaColors.primary),
              title: Text(context.l10n.settingsPrivacyPolicy),
              trailing: const Icon(Icons.chevron_right,
                  size: 18, color: MarginaliaColors.inkFaint),
              onTap: () {
                Navigator.pop(ctx);
                final isIt =
                    Localizations.localeOf(context).languageCode == 'it';
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PrivacyPolicyScreen(isItalian: isIt),
                  ),
                );
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.logout_outlined,
                  color: Color(0xFFB54848)),
              title: Text(context.l10n.settingsSignOut,
                  style: const TextStyle(color: Color(0xFFB54848))),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(supabaseServiceProvider).signOut();
              },
            ),
            // ── Debug only: reset onboarding so devs can test the flow ────
            if (kDebugMode) ...[
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.restart_alt_outlined,
                    color: MarginaliaColors.inkMuted),
                title: const Text('[DEV] Reset onboarding',
                    style: TextStyle(color: MarginaliaColors.inkMuted, fontSize: 13)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await OnboardingService.resetComplete();
                  if (context.mounted) {
                    ref.read(onboardingCompleteProvider.notifier).state = false;
                  }
                },
              ),
            ],
          ],
        ),
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
          _StatBox(label: 'Books', value: stats['books'] ?? 0),
          _Divider(),
          _StatBox(label: 'Highlights', value: stats['highlights'] ?? 0),
          _Divider(),
          _StatBox(label: 'Jams', value: stats['jams'] ?? 0),
          _Divider(),
          _StatBox(label: 'Following', value: stats['following'] ?? 0),
          _Divider(),
          _StatBox(label: 'Followers', value: stats['followers'] ?? 0),
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
                    'CURRENTLY READING',
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
              'No shared highlights',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share a highlight in a Jam\nto see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: MarginaliaColors.inkFaint, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onShare,
              child: Text(context.l10n.editProfileGoToJams),
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

// ─── Daily-phrase personalisation helpers ─────────────────────────────────────

/// One-line summary of the current gender/cycle preference for the settings tile.
String _genderSubtitle(String? gender) {
  switch (gender) {
    case 'female':
      return 'Donna · le frasi possono includere il ciclo';
    case 'male':
      return 'Uomo';
    case 'unspecified':
      return 'Preferisci non specificare';
    default:
      return 'Calibra la frase del giorno per te';
  }
}

/// A selectable option row used inside the personalisation bottom sheet.
class _GenderChoiceRow extends StatelessWidget {
  const _GenderChoiceRow({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? MarginaliaColors.primary.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? MarginaliaColors.primary : MarginaliaColors.rule,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: MarginaliaColors.ink)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!,
                          style: const TextStyle(
                              fontSize: 12, color: MarginaliaColors.inkMuted)),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? MarginaliaColors.primary
                    : MarginaliaColors.inkFaint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
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
                child: Text('Profile',
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
                    Text(context.l10n.profileLoginRequired,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    const Text(
                      'Track your books,\nhighlights and connections.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: MarginaliaColors.inkMuted,
                          height: 1.65,
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

// ─── Data row widget (used in "Your Data" GDPR sheet) ────────────────────────

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: MarginaliaColors.sienna),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MarginaliaColors.inkMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
