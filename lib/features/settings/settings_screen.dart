import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/share_helper.dart';
import 'blocked_users_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/export_service.dart';
import '../../core/services/clippings_importer.dart';
import '../import/paste_import_screen.dart';
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
    final avatarUrl = profile?['avatar_url'] as String?;
    final coverUrl = profile?['cover_url'] as String?;
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
                tooltip: context.l10n.profileSettings,
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
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover photo (if set) behind the header, else the gradient.
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          decoration: MarginaliaDecorations.gradientHeader),
                    )
                  else
                    Container(decoration: MarginaliaDecorations.gradientHeader),
                  // Scrim so the name/email stay legible over a photo.
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x22000000), Color(0xAA000000)],
                        ),
                      ),
                    ),
                  SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Avatar ──────────────────────────────────────
                        Container(
                          width: 86,
                          height: 86,
                          clipBehavior: Clip.antiAlias,
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
                          child: (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? Image.network(
                                  avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _AvatarInitial(initial: initial),
                                )
                              : _AvatarInitial(initial: initial),
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
                ],
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
                      context.l10n.settingsShareInvite,
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
                  Text(context.l10n.settingsInJamsSection,
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
                // Wider gaps + a slightly taller cell now that each tile is a
                // free-standing light card (soft shadow + rounded corners),
                // not a flush dark square. 3px gaps would clip the shadows.
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
              ),
            ),

          // ── Settings section ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Row(
                children: [
                  Text(context.l10n.settingsSettingsSection,
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
                label: context.l10n.settingsSyncWithKindle,
                subtitle: context.l10n.settingsSyncWithKindleSubtitle,
                onTap: () => context.push('/sync/kindle'),
              ),
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                label: context.l10n.importClippingsTile,
                subtitle: context.l10n.importClippingsSubtitle,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l10n;
                  try {
                    final res = await pickAndImportClippings(ref);
                    if (res == null) return; // user cancelled
                    ref.invalidate(allHighlightsProvider);
                    messenger.showSnackBar(SnackBar(
                      content: Text(l10n.importSuccess(
                          res.highlightsAdded, res.booksAdded)),
                    ));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(l10n.importErrorGeneric(e.toString()))));
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.content_paste_rounded,
                label: context.l10n.importPasteTile,
                subtitle: context.l10n.importPasteSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const PasteImportScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.menu_book_outlined,
                label: context.l10n.importKoboTile,
                subtitle: context.l10n.importKoboSubtitle,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l10n;
                  try {
                    final res = await pickAndImportKobo(ref);
                    if (res == null) return; // user cancelled
                    ref.invalidate(allHighlightsProvider);
                    messenger.showSnackBar(SnackBar(
                      content: Text(l10n.importSuccess(
                          res.highlightsAdded, res.booksAdded)),
                    ));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(l10n.koboImportError(e.toString()))));
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.download_outlined,
                label: context.l10n.exportMarkdownTile,
                subtitle: context.l10n.exportMarkdownSubtitle,
                onTap: () => _exportAllHighlights(context, ref),
              ),
              _SettingsTile(
                icon: Icons.table_chart_outlined,
                label: context.l10n.exportNotionTile,
                subtitle: context.l10n.exportNotionSubtitle,
                onTap: () => _exportAllHighlights(context, ref, asCsv: true),
              ),
              _SettingsTile(
                icon: Icons.widgets_outlined,
                label: context.l10n.iosWidgetTile,
                subtitle: context.l10n.iosWidgetSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WidgetPreviewScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.info_outline,
                label: context.l10n.settingsVersion,
                trailing: const Text(
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
                    Text(context.l10n.personalizationSection,
                        style: MarginaliaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: MarginaliaColors.rule)),
                  ],
                ),
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: context.l10n.personalizationTile,
                subtitle: _genderSubtitle(context, ref.watch(genderProvider)),
                onTap: () => _showCyclePersonalizationSheet(context, ref),
              ),

              // ── PRIVACY & DATA section ─────────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(context.l10n.settingsPrivacyDataSection,
                        style: MarginaliaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: MarginaliaColors.rule)),
                  ],
                ),
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                label: context.l10n.settingsYourData,
                subtitle: context.l10n.settingsYourDataSubtitle,
                onTap: () => _showYourDataSheet(context),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: context.l10n.settingsPrivacyPolicy,
                // Open the privacy policy as an IN-APP screen (bundled HTML, no
                // external GitHub link) — reached only from this button.
                onTap: () {
                  final isIt =
                      Localizations.localeOf(context).languageCode == 'it';
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PrivacyPolicyScreen(isItalian: isIt),
                  ));
                },
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: MarginaliaColors.inkFaint),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: context.l10n.settingsTermsOfService,
                // Terms of Service / EULA as an IN-APP screen (bundled HTML),
                // shown as a clickable line directly UNDER the Privacy Policy.
                onTap: () {
                  final isIt =
                      Localizations.localeOf(context).languageCode == 'it';
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TermsOfServiceScreen(isItalian: isIt),
                  ));
                },
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: MarginaliaColors.inkFaint),
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                label: context.l10n.blockedUsersTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BlockedUsersScreen(),
                )),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: MarginaliaColors.inkFaint),
              ),
              _SettingsTile(
                icon: Icons.delete_forever_outlined,
                label: context.l10n.settingsDeleteAccount,
                subtitle: context.l10n.settingsDeleteAccountSubtitle,
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
      BuildContext context, WidgetRef ref,
      {bool asCsv = false}) async {
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
              SnackBar(
                content: Text(context.l10n.settingsNothingToExport),
              ),
            );
        }
        return;
      }

      if (asCsv) {
        await ExportService.exportAllCsv(highlights,
            sharePositionOrigin: shareRect);
      } else {
        await ExportService.exportAll(highlights,
            sharePositionOrigin: shareRect);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
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
            Text(
              ctx.l10n.settingsYourData,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            const SizedBox(height: 16),
            _DataRow(
              icon: Icons.email_outlined,
              title: ctx.l10n.settingsDataEmailTitle,
              body: ctx.l10n.settingsDataEmailBody,
            ),
            _DataRow(
              icon: Icons.format_quote_outlined,
              title: ctx.l10n.settingsDataHighlightsTitle,
              body: ctx.l10n.settingsDataHighlightsBody,
            ),
            _DataRow(
              icon: Icons.favorite_border,
              title: ctx.l10n.settingsDataHealthTitle,
              body: ctx.l10n.settingsDataHealthBody,
            ),
            _DataRow(
              icon: Icons.location_on_outlined,
              title: ctx.l10n.settingsDataWeatherTitle,
              body: ctx.l10n.settingsDataWeatherBody,
            ),
            const SizedBox(height: 8),
            Text(
              ctx.l10n.settingsDataPledge,
              style: const TextStyle(
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
            Text(
              ctx.l10n.personalizationTile,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            const SizedBox(height: 8),
            Text(
              ctx.l10n.personalizationBody,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: MarginaliaColors.inkMuted),
            ),
            const SizedBox(height: 16),
            _GenderChoiceRow(
              label: ctx.l10n.genderWoman,
              hint: ctx.l10n.genderCycleHint,
              selected: current == 'female',
              onTap: () => _setGender(ctx, ref, 'female'),
            ),
            _GenderChoiceRow(
              label: ctx.l10n.genderMan,
              hint: null,
              selected: current == 'male',
              onTap: () => _setGender(ctx, ref, 'male'),
            ),
            _GenderChoiceRow(
              label: ctx.l10n.genderPreferNot,
              hint: ctx.l10n.genderNoCycleHint,
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
                filled: true,
                fillColor: MarginaliaColors.surfaceElevated,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: MarginaliaColors.primaryDark, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
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
                filled: true,
                fillColor: MarginaliaColors.surfaceElevated,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: MarginaliaColors.primaryDark, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: authorController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: context.l10n.editProfileAuthorHint,
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: MarginaliaColors.surfaceElevated,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: MarginaliaColors.primaryDark, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
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
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final l10n = context.l10n;
                Navigator.pop(ctx);
                try {
                  final res = await pickAndImportClippings(ref);
                  if (res == null) return; // user cancelled
                  ref.invalidate(allHighlightsProvider);
                  messenger.showSnackBar(SnackBar(
                    content: Text(l10n.importSuccess(
                        res.highlightsAdded, res.booksAdded)),
                  ));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(l10n.importErrorGeneric(e.toString()))));
                }
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

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFFF1EEE7),
            fontSize: 36,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

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
          _StatBox(label: context.l10n.profileBooksStat, value: stats['books'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileHighlightsStat, value: stats['highlights'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.socialTabJams, value: stats['jams'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileFollowing, value: stats['following'] ?? 0),
          _Divider(),
          _StatBox(label: context.l10n.profileFollowers, value: stats['followers'] ?? 0),
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
                  Text(
                    context.l10n.settingsCurrentlyReading,
                    style: const TextStyle(
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

// Shared-highlight tile, rebuilt as a clean light card in the app's house
// style (cf. the book cells and recommendation cards): a white surface with a
// soft shadow + rounded corners, the highlight set in dark EB Garamond serif
// with quotation marks, a thin accent spine carrying the highlight's colour,
// and the Jam name as a small sage chip pinned to the BOTTOM — clearly
// separated from the quote rather than floating over it. Replaces the old
// dark-maroon block with white-on-dark text and an overlapping "Jam di…" tag.
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

    final accent  = _accentFor(color, bookTitle);
    final excerpt = content.length > 90
        ? '${content.substring(0, 90).trimRight()}…'
        : content;

    return Container(
      decoration: MarginaliaDecorations.quietCard(radius: 14),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent spine — keeps the highlight's colour identity, quietly.
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Highlight — dark serif with quotation marks.
                    Expanded(
                      child: Text(
                        '“$excerpt”',
                        style: GoogleFonts.ebGaramond(
                          color: MarginaliaColors.ink,
                          fontSize: 13.5,
                          fontStyle: FontStyle.italic,
                          height: 1.45,
                        ),
                        overflow: TextOverflow.fade,
                      ),
                    ),
                    if (bookTitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        bookTitle.toUpperCase(),
                        style: const TextStyle(
                          color: MarginaliaColors.inkMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Jam chip — separated at the bottom, never overlapping.
                    if (jamTitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MarginaliaColors.primaryFaint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.groups_outlined,
                                size: 11,
                                color: MarginaliaColors.primaryDark),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                jamTitle,
                                style: const TextStyle(
                                  color: MarginaliaColors.primaryDark,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 220.ms, curve: Curves.easeOut);
  }

  // Accent colour for the spine — derived from the Kindle highlight colour,
  // falling back to the book's procedural cover colour. Saturated enough to
  // read as a thin coloured rule against the white card.
  Color _accentFor(String? color, String bookTitle) => switch (color) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaDecorations.bookCoverColor(bookTitle),
      };
}

// ─── Empty shared highlights ──────────────────────────────────────────────────

class _EmptySharedHighlights extends StatelessWidget {
  const _EmptySharedHighlights({required this.onShare});
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              MarginaliaColors.primary.withOpacity(0.06),
              MarginaliaColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MarginaliaColors.rule.withOpacity(0.6)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: MarginaliaColors.primary.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_stories_outlined,
                  size: 24, color: MarginaliaColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.profileNoSharedTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.profileNoSharedBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, color: MarginaliaColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.groups_outlined, size: 17),
              label: Text(context.l10n.editProfileGoToJams),
              style: FilledButton.styleFrom(
                backgroundColor: MarginaliaColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
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
String _genderSubtitle(BuildContext context, String? gender) {
  final l10n = context.l10n;
  switch (gender) {
    case 'female':
      return l10n.genderSubFemale;
    case 'male':
      return l10n.genderSubMale;
    case 'unspecified':
      return l10n.genderSubUnspecified;
    default:
      return l10n.genderSubUnset;
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
          // Dark gradient header bleeds under the status bar; force light
          // system icons so the iOS clock/battery don't disappear into it.
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: MarginaliaDecorations.lightStatusBar,
            child: Container(
            width: double.infinity,
            decoration: MarginaliaDecorations.gradientHeader,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                child: Text(context.l10n.commonProfile,
                    style: const TextStyle(
                        color: Color(0xFFF1EEE7),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6)),
              ),
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
                    Text(
                      context.l10n.settingsSignInPromoBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
