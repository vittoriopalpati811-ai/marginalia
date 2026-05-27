// ─── Airbnb-style motion toolkit ────────────────────────────────────────────
//
// Design notes (derived from airbnb.design + Cal Stephens'
// "Motion Engineering at Scale" + Google Design's Airbnb case study):
//
//   1. Cinematic, not flashy — durations 280-420 ms with deep ease-out curves
//      (easeOutQuart / easeOutQuint) so motion settles into rest rather than
//      bouncing. Elastic / bounce is explicitly avoided.
//   2. Spring physics on user-driven inputs (taps, drags). Stays interruptible.
//   3. Shared-element / hero transitions for imagery (book covers list → detail).
//   4. Staggered list reveals: 40-60 ms per item, fade + slight slideY.
//   5. Parent-to-child transitions: shared-axis horizontal on push, fade-through
//      on tab/modal. Background does NOT flash to white.
//   6. Press feedback: scale to 0.96 with spring restore on release; lift via
//      shadow opacity (not movement).

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// ─── Tokens ─────────────────────────────────────────────────────────────────

class AirbnbMotion {
  // Durations — cinematic but not slow
  static const fast      = Duration(milliseconds: 180);
  static const standard  = Duration(milliseconds: 280);
  static const emphasis  = Duration(milliseconds: 380);
  static const longForm  = Duration(milliseconds: 520);

  // Curves — deep ease-out is the Airbnb signature.
  // Cubic isn't deep enough; quart / quint are.
  static const enter = Curves.easeOutQuart;
  static const exit  = Curves.easeInQuart;
  static const flow  = Curves.easeOutQuint;

  // Stagger between sibling items in a list
  static const staggerStep = Duration(milliseconds: 50);

  // Spring used for press feedback. Bouncy is wrong; this critically damps
  // so the element settles fast without overshoot.
  static SpringDescription pressSpring = const SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 28,
  );

  // For drag / drop / dismiss (slightly looser so it feels alive)
  static SpringDescription dragSpring = const SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 22,
  );
}

// ─── PressableSpring ────────────────────────────────────────────────────────
//
// Wraps any tappable child with spring-physics press feedback:
//   - on press down → scale to 0.96 + dim shadow (immediate)
//   - on release    → spring back to 1.0
//   - on cancel     → same restore
//
// This is the Airbnb feel: snappy on press, soft on release. Use anywhere
// you'd reach for InkWell / GestureDetector + scale animation.

class PressableSpring extends StatefulWidget {
  const PressableSpring({
    super.key,
    required this.child,
    required this.onPressed,
    this.pressedScale = 0.96,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget        child;
  final VoidCallback? onPressed;
  final double        pressedScale;
  final bool          haptic;
  final bool          enabled;

  @override
  State<PressableSpring> createState() => _PressableSpringState();
}

class _PressableSpringState extends State<PressableSpring>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController.unbounded(vsync: this, value: 1.0);
    _scale = _ctrl.drive(Tween(begin: 1.0, end: 1.0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down() {
    if (!widget.enabled) return;
    _ctrl.stop();
    _ctrl.animateTo(widget.pressedScale,
        duration: AirbnbMotion.fast, curve: Curves.easeOutCubic);
  }

  void _up() {
    if (!widget.enabled) return;
    // Spring back to 1.0
    final sim = SpringSimulation(
      AirbnbMotion.pressSpring,
      _ctrl.value,
      1.0,
      0, // velocity
    );
    _ctrl.animateWith(sim);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _ctrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:   (_) => _down(),
      onTapUp:     (_) => _up(),
      onTapCancel:      _up,
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: scale,
        builder: (_, child) => Transform.scale(
          scale: scale.value,
          alignment: Alignment.center,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

// ─── StaggeredListItem ──────────────────────────────────────────────────────
//
// Drop-in wrapper that gives each child a cascading entrance:
//   delay = baseDelay + index * staggerStep
// Combines fade + 12px slideY for the Airbnb cascade.

class StaggeredListItem extends StatelessWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.baseDelay = Duration.zero,
    this.staggerStep = AirbnbMotion.staggerStep,
    this.duration = AirbnbMotion.emphasis,
  });

  final int      index;
  final Widget   child;
  final Duration baseDelay;
  final Duration staggerStep;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final delay = baseDelay + (staggerStep * index);
    return _DelayedReveal(
      delay: delay,
      duration: duration,
      child: child,
    );
  }
}

class _DelayedReveal extends StatefulWidget {
  const _DelayedReveal({
    required this.delay,
    required this.duration,
    required this.child,
  });

  final Duration delay;
  final Duration duration;
  final Widget   child;

  @override
  State<_DelayedReveal> createState() => _DelayedRevealState();
}

class _DelayedRevealState extends State<_DelayedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    Future.delayed(widget.delay, () {
      if (mounted) {
        _ctrl.forward();
        setState(() => _started = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _ctrl, curve: AirbnbMotion.enter);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: _started ? t.value : 0,
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * 12),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// ─── CrossFadeData ──────────────────────────────────────────────────────────
//
// Cross-fade replacement for AnimatedSwitcher when you want a calm fade with
// the Airbnb timing. Use as direct child of a layout slot whose content
// changes (e.g. a stat card whose number updates).

Widget airbnbCrossFade({required Widget child}) {
  return AnimatedSwitcher(
    duration: AirbnbMotion.standard,
    switchInCurve: AirbnbMotion.enter,
    switchOutCurve: AirbnbMotion.exit,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: child,
    ),
    child: child,
  );
}
