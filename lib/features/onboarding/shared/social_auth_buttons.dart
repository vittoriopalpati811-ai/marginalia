// ─── Social auth buttons (shared) ──────────────────────────────────────────
//
// Currently only Google. Apple and Phone are temporarily disabled —
// Apple awaits Apple Developer enrollment, Phone removed entirely to
// avoid SMS provider costs at launch.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/motion/airbnb_motion.dart';
import '../../../core/theme.dart';

class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    super.key,
    required this.onGoogle,
    required this.googleLabel,
    this.loading = false,
  });

  final VoidCallback onGoogle;
  final String       googleLabel;
  final bool         loading;

  @override
  Widget build(BuildContext context) {
    // Single Google pill — white-background per Google's brand guide,
    // with the multicolor G mark on the leading edge.
    return StaggeredListItem(
      index: 0,
      child: _AuthPill(
        onPressed: loading ? null : onGoogle,
        background: Colors.white,
        foreground: const Color(0xFF1F1F1F),
        border: ScriptaColors.rule,
        iconBuilder: () => const _GoogleMark(),
        label: googleLabel,
      ),
    );
  }
}

class _AuthPill extends StatelessWidget {
  const _AuthPill({
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.iconBuilder,
    required this.label,
    this.border,
  });

  final VoidCallback?    onPressed;
  final Color            background;
  final Color            foreground;
  final Widget Function() iconBuilder;
  final String           label;
  final Color?           border;

  @override
  Widget build(BuildContext context) {
    return PressableSpring(
      onPressed: onPressed ?? () {},
      enabled: onPressed != null,
      child: Container(
        height: 52,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(28),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Row(
          children: [
            SizedBox(width: 24, height: 24, child: Center(child: iconBuilder())),
            Expanded(
              child: Center(
                child: Padding(
                  // Pull the label slightly left to optically center it
                  // accounting for the brand mark on the leading side.
                  padding: const EdgeInsets.only(right: 24),
                  child: Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Brand marks (inline SVG-equivalent via shapes) ─────────────────────────

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();
  @override
  Widget build(BuildContext context) {
    // A minimal multi-colored G mark drawn with CustomPaint so we don't
    // need to ship an SVG asset for this one icon.
    return CustomPaint(
      size: const Size(18, 18),
      painter: _GooglePainter(),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Brand colors
    const blue   = Color(0xFF4285F4);
    const red    = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green  = Color(0xFF34A853);

    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 0.5;
    final inner = r * 0.45;

    // 4 quarter-ring sectors
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r - inner
      ..strokeCap = StrokeCap.butt;

    // Sweep angles in radians (12 o'clock = -pi/2)
    void arc(double startDeg, double sweepDeg, Color col) {
      paint.color = col;
      canvas.drawArc(
        rect.deflate((r - inner) / 2),
        startDeg * 3.1415926 / 180,
        sweepDeg * 3.1415926 / 180,
        false,
        paint,
      );
    }

    arc(-90,   90, red);     // top-right
    arc(  0,   90, yellow);  // bottom-right
    arc( 90,   90, green);   // bottom-left
    arc(180,   90, blue);    // top-left

    // Inner "G" bar
    final barPaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTWH(
      c.dx,
      c.dy - 1.4,
      r - 1.5,
      2.8,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
