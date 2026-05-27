// ─── Onboarding pill buttons (shared) ────────────────────────────────────────
//
// Fable-inspired primary/secondary pill CTAs reused across the onboarding
// steps. Keep these dumb and props-driven: caller decides label/enabled/onTap.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

class OnboardingPrimaryPill extends StatelessWidget {
  const OnboardingPrimaryPill({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String           label;
  final VoidCallback?    onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor:
              enabled ? MarginaliaColors.ink : MarginaliaColors.inkFaint,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class OnboardingSecondaryPill extends StatelessWidget {
  const OnboardingSecondaryPill({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String        label;
  final VoidCallback  onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: MarginaliaColors.surfaceElevated,
          foregroundColor: MarginaliaColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
