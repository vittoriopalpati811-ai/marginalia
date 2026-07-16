import 'package:flutter/material.dart';
import '../../core/errors.dart';
import 'package:flutter/services.dart';
import '../../core/utils/share_helper.dart';
import 'blocked_users_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/export_service.dart';
import '../../core/services/clippings_importer.dart';
import '../import/paste_import_screen.dart';
import '../../core/services/gender_service.dart';
import '../widget/widget_preview_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Real app version + build number from the platform bundle (shown in Settings
/// instead of the old hardcoded "1.0.0"). Cached for the app's lifetime.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber;
  return build.isEmpty ? 'v${info.version}' : 'v${info.version} ($build)';
});

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

// ─── Screen ───────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Optimistic overrides for the two privacy controls. Null means "use the
  // value from the loaded profile"; set only while a write is in flight or has
  // just landed, so the switch/selector react instantly without waiting for the
  // provider to re-emit.
  bool? _privateOverride;
  bool _privacyBusy = false;

  Future<void> _setPrivate(bool value) async {
    setState(() {
      _privateOverride = value;
      _privacyBusy = true;
    });
    try {
      await ref.read(supabaseServiceProvider).updateProfilePrivacy(value);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _privateOverride = !value);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.safeError(e))));
      }
    } finally {
      if (mounted) setState(() => _privacyBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(myProfileProvider);

    final profile = profileAsync.asData?.value;

    // Effective privacy value: optimistic override wins, else the profile.
    final isPrivate = _privateOverride ?? (profile?['is_private'] == true);

    if (user == null) return const _UnauthenticatedProfile();

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App bar ───────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: ScriptaColors.background,
            foregroundColor: ScriptaColors.ink,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            title: Text(
              context.l10n.profileSettings,
              style: const TextStyle(
                color: ScriptaColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
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
                      style: ScriptaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: ScriptaColors.rule)),
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
                      // gen-l10n param order is ALPHABETICAL: (books, highlights).
                      content: Text(l10n.importSuccess(
                          res.booksAdded, res.highlightsAdded)),
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
                      // gen-l10n param order is ALPHABETICAL: (books, highlights).
                      content: Text(l10n.importSuccess(
                          res.booksAdded, res.highlightsAdded)),
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
                trailing: Consumer(
                  builder: (context, ref, _) {
                    final v = ref.watch(appVersionProvider);
                    return Text(
                      v.asData?.value ?? '…',
                      style: const TextStyle(
                          color: ScriptaColors.inkFaint, fontSize: 13),
                    );
                  },
                ),
              ),

              // ── PERSONALIZZAZIONE section ──────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(context.l10n.personalizationSection,
                        style: ScriptaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: ScriptaColors.rule)),
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
                        style: ScriptaTextStyles.sectionTitle),
                    const SizedBox(width: 12),
                    const Expanded(child: Divider(color: ScriptaColors.rule)),
                  ],
                ),
              ),

              // ── Private profile toggle (followers-only visibility) ─────
              Builder(builder: (context) {
                final it =
                    Localizations.localeOf(context).languageCode == 'it';
                return SwitchListTile(
                  value: isPrivate,
                  onChanged: _privacyBusy ? null : _setPrivate,
                  activeColor: ScriptaColors.primary,
                  secondary: const Icon(Icons.lock_outline_rounded,
                      color: ScriptaColors.primary, size: 22),
                  title: Text(it ? 'Profilo privato' : 'Private profile',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    it
                        ? 'Solo chi ti segue può vedere libri, preferiti e post.'
                        : 'Only your followers can see your books, favourites and posts.',
                    style: const TextStyle(
                        fontSize: 12, color: ScriptaColors.inkMuted),
                  ),
                );
              }),


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
                    size: 18, color: ScriptaColors.inkFaint),
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
                    size: 18, color: ScriptaColors.inkFaint),
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                label: context.l10n.blockedUsersTitle,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BlockedUsersScreen(),
                )),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: ScriptaColors.inkFaint),
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
            SnackBar(content: Text(context.safeError(e))),
          );
      }
    }
  }

  // ── Your Data bottom sheet (GDPR transparency) ────────────────────────────

  void _showYourDataSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ScriptaColors.background,
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
                  color: ScriptaColors.rule,
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
            SizedBox(
              width: double.infinity,
              child: Text(
                ctx.l10n.settingsDataPledge,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.sienna,
                ),
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
      backgroundColor: ScriptaColors.background,
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
                  color: ScriptaColors.rule,
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
                  fontSize: 13, height: 1.5, color: ScriptaColors.inkMuted),
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
    // Single gender source of truth: mirror to profiles.gender so the jam
    // Ripasso leaderboard can gender its titles ("Il primo"/"La prima").
    // female→'f', male→'m', anything else→null. Best-effort, never blocks.
    try {
      final g = value == 'female' ? 'f' : (value == 'male' ? 'm' : null);
      await ref.read(supabaseServiceProvider).updateProfileGender(g);
    } catch (_) {/* best-effort */}
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
      leading: Icon(icon, color: ScriptaColors.primary, size: 22),
      title: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(
                  fontSize: 12, color: ScriptaColors.inkMuted))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right,
                  color: ScriptaColors.inkFaint, size: 18)
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
                ? ScriptaColors.primary.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? ScriptaColors.primary : ScriptaColors.rule,
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
                            color: ScriptaColors.ink)),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(hint!,
                          style: const TextStyle(
                              fontSize: 12, color: ScriptaColors.inkMuted)),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? ScriptaColors.primary
                    : ScriptaColors.inkFaint,
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
      backgroundColor: ScriptaColors.background,
      body: Column(
        children: [
          // Dark gradient header bleeds under the status bar; force light
          // system icons so the iOS clock/battery don't disappear into it.
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: ScriptaDecorations.lightStatusBar,
            child: Container(
            width: double.infinity,
            decoration: ScriptaDecorations.gradientHeader,
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
                        color: ScriptaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.person_outline,
                          size: 32, color: ScriptaColors.primary),
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
                          color: ScriptaColors.inkMuted,
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
          Icon(icon, size: 18, color: ScriptaColors.sienna),
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
                    color: ScriptaColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ScriptaColors.inkMuted,
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
