import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../core/review/sm2.dart';
import '../../core/models/highlight.dart';

// ─── Review deck — custom swipe stack, NO new package ─────────────────────────
//
// A Stack of up to three cards. The top card is draggable (GestureDetector pan
// + AnimatedBuilder); two cards peek behind it at scale 0.94 / 0.88, offset down
// 14 / 28px, giving real physical depth (Airbnb-lift). Dragging tilts the card
// up to ±10° and washes a faint intent colour onto its edge (rose = forgot,
// amber = hard, sage = good). Releasing past the threshold flings the card off
// and fires the matching grade; swipe is an optional accelerator — the three
// buttons below the deck remain the primary, accessible grading surface.

/// Maps a fling direction to a grade. Left = forgot, up = hard, right = good.
typedef GradeCallback = void Function(ReviewGrade grade);

class ReviewDeck extends StatefulWidget {
  const ReviewDeck({
    super.key,
    required this.deck,
    required this.index,
    required this.onGrade,
  });

  /// The full session deck. Only [index] and the next two are ever painted.
  final List<Highlight> deck;

  /// Index of the current top card within [deck].
  final int index;

  /// Fired when the top card is flung past threshold.
  final GradeCallback onGrade;

  @override
  State<ReviewDeck> createState() => _ReviewDeckState();
}

class _ReviewDeckState extends State<ReviewDeck>
    with SingleTickerProviderStateMixin {
  // Live drag offset of the top card.
  Offset _drag = Offset.zero;

  // Fling-out animation: from the release offset to off-screen, then we notify.
  late final AnimationController _flingCtrl;
  Animation<Offset>? _flingAnim;
  ReviewGrade? _pendingGrade;

  @override
  void initState() {
    super.initState();
    _flingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final grade = _pendingGrade;
          _pendingGrade = null;
          _flingAnim = null;
          _drag = Offset.zero;
          _flingCtrl.reset();
          if (grade != null) widget.onGrade(grade);
        }
      });
  }

  @override
  void dispose() {
    _flingCtrl.dispose();
    super.dispose();
  }

  bool get _isFlinging => _flingCtrl.isAnimating;

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isFlinging) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d, Size size) {
    if (_isFlinging) return;
    final velocity = d.velocity.pixelsPerSecond;
    final dx = _drag.dx;
    final dy = _drag.dy;

    // Thresholds: a horizontal commitment, an upward commitment, or a fast
    // fling in either axis.
    const distThreshold = 110.0;
    const velThreshold = 900.0;

    ReviewGrade? grade;
    Offset target;

    if (dx < -distThreshold || velocity.dx < -velThreshold) {
      grade = ReviewGrade.forgot; // left
      target = Offset(-size.width * 1.4, dy);
    } else if (dx > distThreshold || velocity.dx > velThreshold) {
      grade = ReviewGrade.good; // right
      target = Offset(size.width * 1.4, dy);
    } else if (dy < -distThreshold || velocity.dy < -velThreshold) {
      grade = ReviewGrade.hard; // up
      target = Offset(dx, -size.height * 1.2);
    } else {
      // Below threshold → spring back to centre.
      _springBack();
      return;
    }

    _pendingGrade = grade;
    _flingAnim = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _flingCtrl, curve: Curves.easeInCubic),
    );
    _flingCtrl.forward(from: 0);
  }

  void _springBack() {
    _pendingGrade = null;
    _flingAnim = Tween<Offset>(begin: _drag, end: Offset.zero).animate(
      CurvedAnimation(parent: _flingCtrl, curve: Curves.easeOutBack),
    );
    // No grade fired on completion — reset handled by the status listener which
    // sees _pendingGrade == null.
    _flingCtrl.forward(from: 0);
  }

  /// The intent colour washed onto the card edge as the user drags toward a
  /// grade. Faint, so the paper still reads.
  Color _intentColor(Offset offset) {
    final dx = offset.dx;
    final dy = offset.dy;
    if (dx < -24 && dx.abs() >= dy.abs()) return MarginaliaColors.highlightRose;
    if (dx > 24 && dx.abs() >= dy.abs()) return MarginaliaColors.siennaLight;
    if (dy < -24) return MarginaliaColors.highlightAmber;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final remaining = widget.deck.length - widget.index;
        if (remaining <= 0) return const SizedBox.shrink();

        // Paint up to three cards, back-to-front. The two behind are static
        // "peeking" cards; the front one is interactive.
        final children = <Widget>[];
        final visible = math.min(3, remaining);
        for (var depth = visible - 1; depth >= 1; depth--) {
          final card = widget.deck[widget.index + depth];
          children.add(_peekingCard(card, depth));
        }
        children.add(_topCard(widget.deck[widget.index], size));

        return Stack(
          alignment: Alignment.center,
          children: children,
        );
      },
    );
  }

  Widget _peekingCard(Highlight h, int depth) {
    final scale = depth == 1 ? 0.94 : 0.88;
    final dy = depth == 1 ? 14.0 : 28.0;
    return Transform.translate(
      offset: Offset(0, dy),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: depth == 1 ? 0.9 : 0.7,
          child: IgnorePointer(child: ReviewCard(highlight: h)),
        ),
      ),
    );
  }

  Widget _topCard(Highlight h, Size size) {
    return AnimatedBuilder(
      animation: _flingCtrl,
      builder: (context, child) {
        final offset = _flingAnim?.value ?? _drag;
        // Tilt up to ±10° proportional to horizontal drag, around a low pivot.
        final angle = (offset.dx / size.width).clamp(-1.0, 1.0) * (math.pi / 18);
        return Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: (d) => _onPanEnd(d, size),
        child: AnimatedBuilder(
          animation: _flingCtrl,
          builder: (context, _) {
            final offset = _flingAnim?.value ?? _drag;
            return ReviewCard(
              highlight: h,
              intentColor: _intentColor(offset),
            );
          },
        ),
      ),
    );
  }
}

// ─── A single editorial review card ──────────────────────────────────────────

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.highlight,
    this.intentColor = Colors.transparent,
  });

  final Highlight highlight;

  /// A faint wash painted as a border/overlay to hint the pending grade while
  /// dragging. Transparent when at rest.
  final Color intentColor;

  /// Font-size ladder so long passages shrink instead of overflowing — mirrors
  /// the HighlightStoryCard sizing approach.
  static double _quoteFontSize(String text) {
    final len = text.length;
    if (len <= 120) return 24;
    if (len <= 220) return 21;
    if (len <= 340) return 18;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    final title = highlight.bookTitle?.trim() ?? '';
    final author = highlight.bookAuthor?.trim() ?? '';
    final hasIntent = intentColor != Colors.transparent;

    return DecoratedBox(
      decoration: MarginaliaDecorations.card(radius: 20).copyWith(
        border: hasIntent
            ? Border.all(color: intentColor.withOpacity(0.9), width: 2)
            : null,
      ),
      child: Stack(
        children: [
          // Faint intent wash so the whole card softly takes the grade colour.
          if (hasIntent)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: intentColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Literary opening quote mark — a faint watermark, top-left.
                Text(
                  '“',
                  style: MarginaliaTextStyles.quoteDecor.copyWith(
                    fontSize: 72,
                    height: 0.5,
                    color: MarginaliaColors.siennaFaint,
                  ),
                ),
                const SizedBox(height: 6),
                // The highlight itself — EB Garamond, scaled down for length.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        highlight.content,
                        style: MarginaliaTextStyles.highlightBody.copyWith(
                          fontSize: _quoteFontSize(highlight.content),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // Short sage rule.
                Container(
                  width: 34,
                  height: 2,
                  decoration: BoxDecoration(
                    color: MarginaliaColors.primary.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MarginaliaTextStyles.bookTitle,
                  ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    author.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MarginaliaTextStyles.bookAuthor,
                  ),
                ],
              ],
            ),
          )
              // Each new card's content rises + fades in (replays when the
              // highlight changes, i.e. when a fresh card reaches the top).
              .animate(key: ValueKey(highlight.content))
              .fadeIn(duration: 420.ms, curve: Curves.easeOut)
              .slideY(
                begin: 0.06,
                end: 0,
                duration: 460.ms,
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }
}
