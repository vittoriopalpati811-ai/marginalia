// ─── Onboarding step: Import highlights (optional) ───────────────────────────
//
// Offered right after the (mandatory) username step. Lets a new reader bring
// their existing Kindle highlights in straight away — three OPTIONAL paths,
// each non-blocking, plus a Continue and a Skip that both simply advance:
//   • Connect Kindle  → AmazonLoginScreen (pushed via MaterialPageRoute; go_router
//                        is NOT mounted during onboarding, so we use Navigator).
//   • Import My Clippings.txt → pickAndImportClippings(ref) (same single code
//                        path Settings/Library use), with a result SnackBar.
//   • Paste highlights → PasteImportScreen (also pushed via MaterialPageRoute).
//
// Strings are inlined it/en (matching the _PermissionsStep / _GenderStep pattern
// in onboarding_screen.dart) to avoid .arb churn for an onboarding-only screen.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/providers/highlights_provider.dart';
import '../../../core/services/clippings_importer.dart';
import '../../../core/theme.dart';
import '../../import/paste_import_screen.dart';
import '../amazon_login_screen.dart';

class ImportHighlightsStep extends ConsumerStatefulWidget {
  const ImportHighlightsStep({super.key, required this.onContinue});

  /// Advances to the next onboarding step. Used by BOTH the Continue button and
  /// the Skip link — importing is entirely optional, neither blocks progress.
  final VoidCallback onContinue;

  @override
  ConsumerState<ImportHighlightsStep> createState() =>
      _ImportHighlightsStepState();
}

class _ImportHighlightsStepState extends ConsumerState<ImportHighlightsStep> {
  bool _importing = false;

  Future<void> _connectKindle() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AmazonLoginScreen()),
    );
    if (mounted) ref.invalidate(allHighlightsProvider);
  }

  // Reuses the exact pattern from settings_screen.dart (~436-451): capture the
  // messenger/l10n before the await, surface success/error via SnackBar.
  Future<void> _importClippings() async {
    if (_importing) return;
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final res = await pickAndImportClippings(ref);
      if (res == null) return; // user cancelled
      ref.invalidate(allHighlightsProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.importSuccess(res.highlightsAdded, res.booksAdded)),
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importErrorGeneric(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pasteHighlights() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PasteImportScreen()),
    );
    if (mounted) ref.invalidate(allHighlightsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final title = isIt ? 'Porta le tue\nevidenziazioni' : 'Bring your\nhighlights';
    final subtitle = isIt
        ? 'Importa subito le frasi che hai già salvato — oppure fallo più tardi.'
        : 'Import the lines you’ve already saved — or do it later.';
    final connectKindle = isIt ? 'Collega Kindle' : 'Connect Kindle';
    final connectKindleSub = isIt
        ? 'Accedi ad Amazon e sincronizza il taccuino'
        : 'Sign in to Amazon and sync your notebook';
    final importClippings = isIt ? 'Importa My Clippings' : 'Import My Clippings';
    final importClippingsSub = isIt
        ? 'Scegli il file My Clippings.txt del tuo Kindle'
        : 'Pick your Kindle’s My Clippings.txt file';
    final paste = isIt ? 'Incolla evidenziazioni' : 'Paste highlights';
    final pasteSub = isIt
        ? 'Copia e incolla le frasi da qualsiasi app'
        : 'Copy and paste lines from any app';
    final continueLabel = context.l10n.onboardingContinue;
    final skip = context.l10n.onboardingSkip;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            title,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
              height: 1.12,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 28),

          _ImportAction(
            icon: Icons.sync_outlined,
            label: connectKindle,
            subtitle: connectKindleSub,
            onTap: _importing ? null : _connectKindle,
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          const SizedBox(height: 12),

          _ImportAction(
            icon: Icons.upload_file_outlined,
            label: importClippings,
            subtitle: importClippingsSub,
            loading: _importing,
            onTap: _importing ? null : _importClippings,
          ).animate().fadeIn(delay: 130.ms, duration: 250.ms),

          const SizedBox(height: 12),

          _ImportAction(
            icon: Icons.content_paste_rounded,
            label: paste,
            subtitle: pasteSub,
            onTap: _importing ? null : _pasteHighlights,
          ).animate().fadeIn(delay: 180.ms, duration: 250.ms),

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: widget.onContinue,
              child: Text(
                continueLabel,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: widget.onContinue,
            child: Text(
              skip,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ImportAction extends StatelessWidget {
  const _ImportAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScriptaColors.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: loading
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Icon(icon, size: 24, color: ScriptaColors.primaryDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ScriptaColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: ScriptaColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: ScriptaColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
