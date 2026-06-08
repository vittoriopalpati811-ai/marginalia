// ─── Reading Wrapped — story viewer ──────────────────────────────────────────
//
// A full-screen, Instagram-Stories-style player for the weekly recap. It pages
// through the [WrappedStorySlide]s built from a single [WrappedData]:
//
//   • segmented progress bars across the top (one per slide, the active one
//     filling over the slide's dwell time),
//   • auto-advance when a bar fills; tap the right two-thirds to skip ahead,
//     the left third to go back; long-press to pause; swipe down to dismiss,
//   • a share button that rasterises the CURRENT slide (reusing
//     [shareWrappedSlide]) to Instagram Stories / Save / system share.
//
// Everything is offline + deterministic — the numbers come from local Isar via
// [wrappedDataProvider]; there is no backend and no LLM, so it never produces
// "AI slop". The default cadence is WEEKLY (the headline ritual).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import 'wrapped_data.dart';
import 'wrapped_share.dart';
import 'wrapped_slides.dart';

class WrappedScreen extends ConsumerWidget {
  const WrappedScreen({super.key, this.period = WrappedPeriod.week});

  /// Which cadence to recap. Defaults to the last 7 days (the weekly ritual).
  final WrappedPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wrappedDataProvider(period));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MarginaliaDecorations.lightStatusBar,
      child: async.when(
        loading: () => const _WrappedFrame(child: _WrappedLoading()),
        error: (_, __) => _WrappedFrame(child: _WrappedEmpty(onClose: () => _close(context))),
        data: (data) {
          if (data.isEmpty) {
            return _WrappedFrame(child: _WrappedEmpty(onClose: () => _close(context)));
          }
          final slides = buildWrappedSlides(context, data);
          if (slides.isEmpty) {
            return _WrappedFrame(child: _WrappedEmpty(onClose: () => _close(context)));
          }
          return _WrappedPlayer(slides: slides);
        },
      ),
    );
  }

  static void _close(BuildContext context) => Navigator.of(context).maybePop();
}

// ─── Shared dark frame (loading + empty) ─────────────────────────────────────

class _WrappedFrame extends StatelessWidget {
  const _WrappedFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: wrappedGradientAt(0),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}

class _WrappedLoading extends StatelessWidget {
  const _WrappedLoading();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
}

class _WrappedEmpty extends StatelessWidget {
  const _WrappedEmpty({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    return Stack(
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: onClose,
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_stories_outlined,
                    color: Colors.white, size: 56),
                const SizedBox(height: 22),
                Text(
                  it ? 'Ancora niente da raccontare' : 'Nothing to wrap up yet',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  it
                      ? 'Evidenzia qualche frase questa settimana e torna a vedere il tuo recap.'
                      : 'Highlight a few passages this week and come back for your recap.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withAlpha(200),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── The player ──────────────────────────────────────────────────────────────

class _WrappedPlayer extends StatefulWidget {
  const _WrappedPlayer({required this.slides});
  final List<WrappedStorySlide> slides;

  @override
  State<_WrappedPlayer> createState() => _WrappedPlayerState();
}

class _WrappedPlayerState extends State<_WrappedPlayer>
    with SingleTickerProviderStateMixin {
  static const Duration _dwell = Duration(milliseconds: 5500);

  late final AnimationController _progress;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _dwell)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
    _progress.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _restart() => _progress
    ..reset()
    ..forward();

  void _advance() {
    if (_index >= widget.slides.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _index++);
    _restart();
  }

  void _back() {
    if (_index == 0) {
      _restart();
      return;
    }
    setState(() => _index--);
    _restart();
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progress.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _progress.forward();
  }

  Future<void> _shareCurrent() async {
    _pause();
    HapticFeedback.lightImpact();
    await shareWrappedSlide(context, slide: widget.slides[_index]);
    if (mounted) _resume();
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_index];
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (details.globalPosition.dx < width * 0.32) {
            _back();
          } else {
            _advance();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 280) {
            Navigator.of(context).maybePop();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: slide.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Segmented progress bars ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.slides.length; i++)
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2.5),
                            child: _SegmentBar(
                              animation: i < _index
                                  ? const AlwaysStoppedAnimation<double>(1)
                                  : (i == _index
                                      ? _progress
                                      : const AlwaysStoppedAnimation<double>(0)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Close + share row ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.ios_share_rounded,
                            color: Colors.white, size: 21),
                        onPressed: _shareCurrent,
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 26),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),

                // ── Slide body ───────────────────────────────────────────────
                // The AnimatedSwitcher cross-fades slides; on top, each new slide
                // RISES + SCALES in (Spotify-Wrapped energy) so it reads as a
                // dynamic reveal, not a static page.
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    child: KeyedSubtree(
                      key: ValueKey<int>(_index),
                      child: slide
                          .buildBody(context)
                          .animate()
                          .slideY(
                            begin: 0.14,
                            end: 0,
                            duration: 600.ms,
                            curve: Curves.easeOutCubic,
                          )
                          .scaleXY(
                            begin: 0.93,
                            end: 1.0,
                            duration: 600.ms,
                            curve: Curves.easeOutCubic,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── One progress segment ────────────────────────────────────────────────────

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => LinearProgressIndicator(
            value: animation.value.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withAlpha(64),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }
}
