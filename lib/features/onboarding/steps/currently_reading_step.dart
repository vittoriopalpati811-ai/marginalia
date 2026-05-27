// ─── Onboarding step: currently reading ─────────────────────────────────────
//
// Two compact fields (title + optional author). The author field reveals
// once a title is typed (AnimatedSize). No book-API search yet — shipping
// the schema and UX now; lookup integration is a follow-up.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
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
  bool get _hasTitle => widget.titleCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
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

          const Spacer(),

          OnboardingPrimaryPill(
            label: context.l10n.onboardingCurrentlyReadingNext,
            onPressed: _hasTitle ? widget.onContinue : null,
          ),
          const SizedBox(height: 10),
          OnboardingSecondaryPill(
            label: context.l10n.onboardingCurrentlyReadingNothing,
            onPressed: widget.onSkip,
          ),
        ],
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
