import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/subscription_provider.dart';

// ─── PaywallScreen ────────────────────────────────────────────────────────────
//
// Shown when the user tries to access a premium-only feature.
// Can be pushed as a full-screen route (/paywall) or displayed as a modal.
//
// Usage (route push):
//   context.push('/paywall');
//
// Usage (modal):
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (_) => const PaywallScreen(modal: true),
//   );

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.modal = false});

  /// When true, wraps in a DraggableScrollableSheet instead of a full Scaffold.
  final bool modal;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _purchasing = false;
  bool _restoring  = false;

  Future<void> _purchase() async {
    setState(() => _purchasing = true);
    try {
      final ok = await ref.read(subscriptionProvider.notifier).purchase();
      if (!mounted) return;
      if (ok) {
        _showSuccess('Benvenuto in Marginalia Premium! 🎉');
        if (widget.modal) Navigator.of(context).pop(true);
        else context.pop(true);
      } else {
        _showError('Acquisto non riuscito. Riprova.');
      }
    } catch (_) {
      if (mounted) _showError('Acquisto non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final ok = await ref.read(subscriptionProvider.notifier).restore();
      if (!mounted) return;
      if (ok) {
        _showSuccess('Acquisto ripristinato!');
        if (widget.modal) Navigator.of(context).pop(true);
        else context.pop(true);
      } else {
        _showError('Nessun acquisto da ripristinare.');
      }
    } catch (_) {
      if (mounted) _showError('Ripristino non riuscito. Riprova.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: MarginaliaColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFB03A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _PaywallBody(
      purchasing: _purchasing,
      restoring: _restoring,
      onPurchase: _purchase,
      onRestore: _restore,
      onDismiss: widget.modal
          ? () => Navigator.of(context).pop(false)
          : () => context.pop(false),
    );

    if (widget.modal) {
      return Container(
        decoration: const BoxDecoration(
          color: MarginaliaColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: body,
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _PaywallBody extends StatelessWidget {
  const _PaywallBody({
    required this.purchasing,
    required this.restoring,
    required this.onPurchase,
    required this.onRestore,
    required this.onDismiss,
  });

  final bool purchasing;
  final bool restoring;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // ── Hero header ─────────────────────────────────────────────────────
          SizedBox(
            height: 320 + top,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A3A22), Color(0xFF0D2114)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

                // Subtle pattern overlay
                CustomPaint(painter: _DotPatternPainter()),

                // Content
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // M badge
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withAlpha(30), width: 1),
                          ),
                          child: Center(
                            child: Text(
                              'M',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFF1EEE7),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ).animate()
                            .fadeIn(duration: 400.ms)
                            .scale(begin: const Offset(0.85, 0.85),
                                   end: const Offset(1, 1),
                                   duration: 400.ms,
                                   curve: Curves.easeOutBack),
                        const SizedBox(height: 20),
                        Text(
                          'Marginalia\nPremium',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFF1EEE7),
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                        ).animate(delay: 80.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.05, end: 0, duration: 400.ms),
                        const SizedBox(height: 8),
                        Text(
                          'Sblocca il pieno potenziale della tua lettura',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withAlpha(160),
                            height: 1.5,
                          ),
                        ).animate(delay: 140.ms)
                            .fadeIn(duration: 400.ms),
                      ],
                    ),
                  ),
                ),

                // Close button
                Positioned(
                  top: top + 12,
                  right: 16,
                  child: GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Feature list ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.all_inclusive_rounded,
                  title: 'Highlight illimitati da Kindle',
                  subtitle: 'Fino a 100 highlight nel piano free',
                  premium: true,
                  index: 0,
                ),
                _FeatureRow(
                  icon: Icons.groups_rounded,
                  title: 'Crea e partecipa a Jam illimitate',
                  subtitle: 'Solo visualizzazione nel piano free',
                  premium: true,
                  index: 1,
                ),
                _FeatureRow(
                  icon: Icons.widgets_rounded,
                  title: 'Widget iOS attivi',
                  subtitle: 'Non disponibile nel piano free',
                  premium: true,
                  index: 2,
                ),
              ],
            ),
          ),

          // ── Price card ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A22), Color(0xFF0D2114)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '€19,99/anno',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFF1EEE7),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Meno di un caffè al mese',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withAlpha(25), width: 1),
                    ),
                    child: Text(
                      '~€1,67/mese',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withAlpha(180),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ).animate(delay: 200.ms).fadeIn(duration: 350.ms).slideY(begin: 0.04, end: 0),

          // ── CTA ─────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: purchasing || restoring ? null : onPurchase,
                style: FilledButton.styleFrom(
                  backgroundColor: MarginaliaColors.primary,
                  foregroundColor: const Color(0xFFF1EEE7),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.barlow(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                child: purchasing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Sblocca Marginalia Premium'),
              ),
            ),
          ).animate(delay: 260.ms).fadeIn(duration: 350.ms),

          // ── Restore ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: restoring
                ? const SizedBox(
                    height: 32,
                    child: Center(
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: MarginaliaColors.inkMuted),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: purchasing || restoring ? null : onRestore,
                    child: const Text(
                      'Ripristina acquisto',
                      style: TextStyle(
                        fontSize: 13,
                        color: MarginaliaColors.inkMuted,
                      ),
                    ),
                  ),
          ),

          // ── Terms ────────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(32, 8, 32, bottom + 24),
            child: Text(
              'Rinnovo automatico annuale. Cancella in qualsiasi momento da Impostazioni → Abbonamenti.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature row ──────────────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.premium,
    required this.index,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool premium;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: premium
                  ? MarginaliaColors.primaryFaint
                  : MarginaliaColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: premium
                  ? MarginaliaColors.primary
                  : MarginaliaColors.inkFaint,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'PREMIUM',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: MarginaliaColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MarginaliaColors.inkMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: (80 + index * 60).ms)
        .fadeIn(duration: 320.ms, curve: Curves.easeOut)
        .slideX(begin: 0.03, end: 0, duration: 320.ms);
  }
}

// ─── Dot pattern painter ──────────────────────────────────────────────────────

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(12)
      ..style = PaintingStyle.fill;
    const spacing = 24.0;
    const r = 1.2;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPatternPainter _) => false;
}
