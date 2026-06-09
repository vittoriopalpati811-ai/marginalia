import 'package:flutter/material.dart';

/// The Scripta app mark — the layered sage cards + red bookmark used as the app
/// icon. This is the single source of truth for the small brand badge shown
/// throughout the app (share/story cards, stats card, paywall, widget preview,
/// activity share, …). It replaces the old gradient "S" square.
///
/// To restyle the brand mark everywhere, change `assets/brand/scripta_mark.png`.
class ScriptaMark extends StatelessWidget {
  const ScriptaMark({super.key, this.size = 26, this.opacity = 1.0});

  /// Width + height (the mark is square).
  final double size;

  /// 0–1; values < 1 wrap the mark in an [Opacity] (used for faint watermarks).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/brand/scripta_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    return opacity >= 1.0 ? image : Opacity(opacity: opacity, child: image);
  }
}
