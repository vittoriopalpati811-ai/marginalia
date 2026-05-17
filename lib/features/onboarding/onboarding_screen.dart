import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/onboarding_service.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}

const _kSlides = [
  _Slide(
    icon: Icons.auto_stories_outlined,
    title: 'Bentornato\ntra le pagine.',
    body:
        'Marginalia ridà vita agli highlight che hai sottolineato su Kindle — '
        'e ti aiuta a non dimenticare più niente di quello che hai letto.',
    accent: Color(0xFF6B4C3B),
  ),
  _Slide(
    icon: Icons.upload_file_outlined,
    title: 'Importa\nin un tocco.',
    body:
        'Collega il tuo Kindle o carica il file My Clippings.txt: '
        'tutti i tuoi libri e highlight appaiono all\'istante, '
        'ordinati e pronti.',
    accent: Color(0xFF2D5A3D),
  ),
  _Slide(
    icon: Icons.group_outlined,
    title: 'Leggi\ninsieme.',
    body:
        'Crea una Jam con gli amici, condividi i tuoi highlight preferiti '
        'e scopri cosa leggono le persone che ami.',
    accent: Color(0xFF1A3A5C),
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_finishing) return;
    if (_currentPage < _kSlides.length - 1) {
      HapticFeedback.lightImpact();
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await _complete();
    }
  }

  Future<void> _complete() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    HapticFeedback.mediumImpact();
    await OnboardingService.markComplete();
    // Flipping the provider causes MarginaliaApp to rebuild from
    // MaterialApp(home: OnboardingScreen) → MaterialApp.router.
    // The router's initialLocation '/' shows LibraryScreen automatically —
    // no explicit navigation call needed here.
    ref.read(onboardingCompleteProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _kSlides.length - 1;

    return Scaffold(
      backgroundColor: MarginaliaColors.primary,
      body: Stack(
        children: [
          // ── Background gradient animated per slide ──────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _kSlides[_currentPage].accent,
                  MarginaliaColors.primaryDark,
                ],
              ),
            ),
          ),

          // ── Decorative large quote mark ─────────────────────────────────────
          Positioned(
            top: -20,
            right: -10,
            child: Text(
              '"',
              style: MarginaliaTextStyles.quoteDecor.copyWith(
                fontSize: 260,
                color: Colors.white.withAlpha(10),
                height: 1,
              ),
            ),
          ),

          // ── Page content ───────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Skip button (top right, hidden on last slide)
                Align(
                  alignment: Alignment.topRight,
                  child: AnimatedOpacity(
                    opacity: isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: TextButton(
                      onPressed: isLast ? null : _complete,
                      child: Text(
                        'Salta',
                        style: TextStyle(
                          color: const Color(0xFFF1EEE7).withAlpha(160),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

                // Slide pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _kSlides.length,
                    onPageChanged: (i) {
                      setState(() => _currentPage = i);
                    },
                    itemBuilder: (context, index) =>
                        _SlidePage(slide: _kSlides[index]),
                  ),
                ),

                // Bottom controls
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
                  child: Column(
                    children: [
                      // Dot indicators
                      _DotIndicator(
                        count: _kSlides.length,
                        current: _currentPage,
                      ),
                      const SizedBox(height: 28),

                      // CTA button
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: SizedBox(
                          key: ValueKey(isLast),
                          width: double.infinity,
                          height: 56,
                          child: FilledButton(
                            onPressed: _finishing ? null : _advance,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF1EEE7),
                              foregroundColor: MarginaliaColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            child: _finishing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                          MarginaliaColors.primary),
                                    ),
                                  )
                                : Text(
                                    isLast
                                        ? 'Inizia a leggere'
                                        : 'Avanti',
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slide page ───────────────────────────────────────────────────────────────

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon in a frosted circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withAlpha(30),
                width: 1.5,
              ),
            ),
            child: Icon(
              slide.icon,
              size: 36,
              color: const Color(0xFFF1EEE7),
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 500.ms),

          const SizedBox(height: 32),

          // Title
          Text(
            slide.title,
            style: const TextStyle(
              color: Color(0xFFF1EEE7),
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.1,
            ),
          )
              .animate()
              .fadeIn(
                  delay: 80.ms, duration: 500.ms, curve: Curves.easeOut)
              .slideY(
                  begin: 0.06,
                  end: 0,
                  delay: 80.ms,
                  duration: 500.ms),

          const SizedBox(height: 20),

          // Body
          Text(
            slide.body,
            style: TextStyle(
              color: const Color(0xFFF1EEE7).withAlpha(200),
              fontSize: 16,
              height: 1.65,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
          )
              .animate()
              .fadeIn(
                  delay: 160.ms, duration: 500.ms, curve: Curves.easeOut)
              .slideY(
                  begin: 0.06,
                  end: 0,
                  delay: 160.ms,
                  duration: 500.ms),
        ],
      ),
    );
  }
}

// ─── Dot indicator ────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFF1EEE7)
                : const Color(0xFFF1EEE7).withAlpha(70),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
