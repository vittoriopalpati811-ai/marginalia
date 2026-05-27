// ─── Onboarding step: currently reading ─────────────────────────────────────
//
// Two compact fields (title + optional author), plus an ISBN/barcode entry
// at the bottom that pre-fills the fields from Open Library lookup.
//
// Barcode camera scan: stub today (shows a friendly "use iPhone app" hint
// on web; will be wired up to `mobile_scanner` for the iOS build).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/services/book_lookup_service.dart';
import '../../../core/theme.dart';
import '../shared/onboarding_pill_button.dart';

class CurrentlyReadingStep extends StatefulWidget {
  const CurrentlyReadingStep({
    super.key,
    required this.titleCtrl,
    required this.authorCtrl,
    required this.onContinue,
    required this.onSkip,
  });

  final TextEditingController titleCtrl;
  final TextEditingController authorCtrl;
  final VoidCallback          onContinue;
  final VoidCallback          onSkip;

  @override
  State<CurrentlyReadingStep> createState() => _CurrentlyReadingStepState();
}

class _CurrentlyReadingStepState extends State<CurrentlyReadingStep> {
  final _isbnCtrl = TextEditingController();
  bool   _looking = false;
  String? _lookupError;

  bool get _hasTitle => widget.titleCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _isbnCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupIsbn() async {
    final raw = _isbnCtrl.text.trim();
    final normalized = BookLookupService.normalizeIsbn(raw);
    if (normalized == null) {
      setState(() => _lookupError = context.l10n.onboardingIsbnInvalid);
      return;
    }
    setState(() {
      _looking = true;
      _lookupError = null;
    });
    final book = await BookLookupService.byIsbn(normalized);
    if (!mounted) return;
    setState(() => _looking = false);
    if (book == null) {
      setState(() => _lookupError = context.l10n.onboardingIsbnNotFound);
      return;
    }
    widget.titleCtrl.text  = book.title;
    widget.authorCtrl.text = book.author ?? '';
    setState(() {});
  }

  void _scanBarcode() {
    // Web stub. The mobile_scanner package only works reliably on iOS/Android;
    // on web the camera bridge is flaky. We'll wire the native flow in the
    // iOS Codemagic build.
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.onboardingScanWebUnsupported),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    // TODO(native): show MobileScanner here; on detect, populate _isbnCtrl
    // and call _lookupIsbn().
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.onboardingScanWebUnsupported),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            Text(
              context.l10n.onboardingCurrentlyReadingTitle,
              style: GoogleFonts.ebGaramond(
                fontSize: 38,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
                letterSpacing: -1.0,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 28),

            _SearchPill(
              controller: widget.titleCtrl,
              hint: context.l10n.onboardingCurrentlyReadingHint,
              icon: Icons.search,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _hasTitle
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _SearchPill(
                        controller: widget.authorCtrl,
                        hint: context.l10n.editProfileAuthorHint,
                        icon: Icons.person_outline,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            // ── Divider with "oppure" ──────────────────────────────────────
            Row(
              children: [
                const Expanded(
                  child: Divider(color: MarginaliaColors.rule, height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    context.l10n.authOrDivider,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MarginaliaColors.inkFaint,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Expanded(
                  child: Divider(color: MarginaliaColors.rule, height: 1),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Scan barcode button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _looking ? null : _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: Text(context.l10n.onboardingScanBarcode),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MarginaliaColors.ink,
                  side: const BorderSide(color: MarginaliaColors.rule),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Manual ISBN entry ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: MarginaliaColors.rule),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tag_rounded, size: 18, color: MarginaliaColors.inkMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _isbnCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9X\-\s]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      onSubmitted: (_) => _lookupIsbn(),
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: MarginaliaColors.ink,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        hintText: context.l10n.onboardingIsbnHint,
                        hintStyle: GoogleFonts.manrope(
                          fontSize: 13,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _looking ? null : _lookupIsbn,
                    style: TextButton.styleFrom(
                      foregroundColor: MarginaliaColors.primary,
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: _looking
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: MarginaliaColors.primary),
                          )
                        : Text(
                            context.l10n.onboardingIsbnLookup,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            if (_lookupError != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _lookupError!,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: const Color(0xFFB54848),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            OnboardingPrimaryPill(
              label: context.l10n.onboardingCurrentlyReadingNext,
              onPressed: _hasTitle ? widget.onContinue : null,
            ),
            const SizedBox(height: 10),
            OnboardingSecondaryPill(
              label: context.l10n.onboardingCurrentlyReadingNothing,
              onPressed: widget.onSkip,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
  });

  final TextEditingController controller;
  final String                hint;
  final IconData              icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MarginaliaColors.rule),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: MarginaliaColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: MarginaliaColors.ink,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: hint,
                hintStyle: GoogleFonts.manrope(
                  fontSize: 15,
                  color: MarginaliaColors.inkFaint,
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
