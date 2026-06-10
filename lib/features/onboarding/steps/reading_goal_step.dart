// ─── Onboarding step: annual reading goal ───────────────────────────────────
//
// Fable-style screen: large editorial heading with the year, a number field,
// motivational subtitle that updates with the chosen goal, primary "Set goal"
// CTA + secondary "I'll set my goal later".

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme.dart';
import '../shared/onboarding_pill_button.dart';

class ReadingGoalStep extends StatefulWidget {
  const ReadingGoalStep({
    super.key,
    required this.goalCtrl,
    required this.onContinue,
    required this.onSkip,
  });

  final TextEditingController goalCtrl;
  final VoidCallback          onContinue;
  final VoidCallback          onSkip;

  @override
  State<ReadingGoalStep> createState() => _ReadingGoalStepState();
}

class _ReadingGoalStepState extends State<ReadingGoalStep> {
  int get _goal => int.tryParse(widget.goalCtrl.text.trim()) ?? 0;

  String _motivation(BuildContext context) {
    final g = _goal;
    if (g <= 6)  return context.l10n.onboardingGoalLow;
    if (g <= 15) return context.l10n.onboardingGoalMedium;
    return context.l10n.onboardingGoalCommitted;
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),

          Text(
            context.l10n.onboardingGoalTitle(year),
            style: GoogleFonts.ebGaramond(
              fontSize: 38,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -1.0,
              height: 1.05,
            ),
          )
              .animate()
              .fadeIn(duration: 380.ms)
              .slideY(begin: -0.05, end: 0, duration: 380.ms),
          const SizedBox(height: 16),
          Text(
            context.l10n.onboardingGoalSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 90.ms, duration: 360.ms),
          const SizedBox(height: 28),

          Text(
            context.l10n.onboardingGoalFieldLabel,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ScriptaColors.ink,
              letterSpacing: 0.2,
            ),
          ).animate().fadeIn(delay: 160.ms, duration: 360.ms),
          const SizedBox(height: 8),

          Container(
            // Comfortable inner gutter so the "15" doesn't kiss the left
            // border and the "Libri" suffix doesn't kiss the right.
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ScriptaColors.rule),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.goalCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.ebGaramond(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.ink,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.onboardingGoalSuffix,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: ScriptaColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(delay: 220.ms, duration: 360.ms)
              .scale(
                begin: const Offset(0.97, 0.97),
                end: const Offset(1, 1),
                delay: 220.ms,
                duration: 380.ms,
                curve: Curves.easeOutQuart,
              ),
          const SizedBox(height: 14),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              _motivation(context),
              key: ValueKey(_motivation(context)),
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: ScriptaColors.inkMuted,
                height: 1.5,
              ),
            ),
          ),

          const Spacer(),

          OnboardingPrimaryPill(
            label: context.l10n.onboardingGoalCta,
            onPressed: _goal > 0 ? widget.onContinue : null,
          ),
          const SizedBox(height: 10),
          OnboardingSecondaryPill(
            label: context.l10n.onboardingGoalSkip,
            onPressed: widget.onSkip,
          ),
        ],
      ),
    );
  }
}
