import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/services/widget_service.dart';
import '../../core/theme.dart';

// ─── WidgetPreviewScreen ──────────────────────────────────────────────────────
//
// Simulates an iPhone 15 home screen with the Marginalia widget rendered at
// all three sizes (small, medium, large).
//
// The AI-selected highlight is shown in each size so the user can compare how
// the content fits. A "Refresh AI pick" button re-runs the selection algorithm
// with live time + weather, showing a new highlight if applicable.
//
// This screen is pure Flutter — no native code needed. The actual widget that
// appears on the real iOS home screen is the Swift WidgetKit extension in
// ios/Sources/MarginaliaWidgets/.

// ── Provider ─────────────────────────────────────────────────────────────────

final _widgetHighlightProvider =
    FutureProvider.autoDispose<WidgetHighlight?>((ref) async {
  // Pull mock highlights from the social feed provider if available,
  // or return a placeholder for preview.
  return _mockHighlight();
});

WidgetHighlight _mockHighlight() {
  final now = DateTime.now();
  final hour = now.hour;

  String greeting;
  if (hour >= 5 && hour < 12) {
    greeting = 'Buongiorno';
  } else if (hour >= 12 && hour < 17) {
    greeting = 'Buon pomeriggio';
  } else if (hour >= 17 && hour < 21) {
    greeting = 'Buona sera';
  } else {
    greeting = 'Buona notte';
  }

  // A curated set of placeholder highlights that look great in the preview
  const previews = [
    (
      text:
          "Non si leggono i libri per finirli, ma per abitarli — per trovare in essi un'altra casa.",
      book: 'Come un romanzo',
      author: 'Daniel Pennac',
    ),
    (
      text:
          'Un lettore vive mille vite prima di morire. Chi non legge ne vive solo una.',
      book: 'A Dance with Dragons',
      author: 'George R.R. Martin',
    ),
    (
      text:
          'Ogni libro è un mondo. Apri la copertina e sei già altrove.',
      book: 'La storia infinita',
      author: 'Michael Ende',
    ),
    (
      text:
          'Le parole giuste al momento giusto possono cambiare tutto.',
      book: 'The Alchemist',
      author: 'Paulo Coelho',
    ),
  ];

  final idx = (hour + now.weekday) % previews.length;
  final p = previews[idx];

  return WidgetHighlight(
    text: p.text,
    bookTitle: p.book,
    author: p.author,
    timeGreeting: greeting,
    weatherMood: _guessWeatherByHour(hour),
  );
}

String _guessWeatherByHour(int hour) {
  // Simple placeholder — real app fetches from wttr.in
  if (hour >= 7 && hour < 19) return 'sunny';
  return 'clear';
}

// ── Screen ───────────────────────────────────────────────────────────────────

class WidgetPreviewScreen extends ConsumerStatefulWidget {
  const WidgetPreviewScreen({super.key});

  @override
  ConsumerState<WidgetPreviewScreen> createState() =>
      _WidgetPreviewScreenState();
}

class _WidgetPreviewScreenState extends ConsumerState<WidgetPreviewScreen> {
  _WidgetSize _size = _WidgetSize.medium;
  bool _pushed = false;

  @override
  Widget build(BuildContext context) {
    final highlightAsync = ref.watch(_widgetHighlightProvider);
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    // Build localised date string without requiring locale init
    final weekdays = ['Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'];
    final months  = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
                     'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'];
    final dateStr = '${weekdays[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Anteprima widget',
          style: GoogleFonts.barlow(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _SizeSelector(
              current: _size,
              onChanged: (s) => setState(() => _size = s),
            ),
          ),
        ],
      ),
      body: highlightAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        error: (_, __) => const Center(
          child: Text('Errore nel caricamento',
              style: TextStyle(color: Colors.white54)),
        ),
        data: (highlight) {
          if (highlight == null) {
            return const Center(
              child: Text('Nessun highlight disponibile',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          return _PhoneFrame(
            timeStr: timeStr,
            dateStr: dateStr,
            child: _buildWidget(highlight),
            bottomContent: _BottomBar(
              highlight: highlight,
              pushed: _pushed,
              onPush: () async {
                // In a real build this would call WidgetService.update(...)
                setState(() => _pushed = true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Widget aggiornato sul telefono',
                        style: GoogleFonts.barlow(fontSize: 13),
                      ),
                      backgroundColor: MarginaliaColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              onRefresh: () {
                setState(() => _pushed = false);
                ref.invalidate(_widgetHighlightProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWidget(WidgetHighlight h) {
    return switch (_size) {
      _WidgetSize.small  => _SmallWidget(highlight: h),
      _WidgetSize.medium => _MediumWidget(highlight: h),
      _WidgetSize.large  => _LargeWidget(highlight: h),
    };
  }
}

// ── Phone frame ───────────────────────────────────────────────────────────────

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.timeStr,
    required this.dateStr,
    required this.child,
    required this.bottomContent,
  });

  final String timeStr;
  final String dateStr;
  final Widget child;
  final Widget bottomContent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── iPhone frame ──────────────────────────────────────────────────
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 390 / 844, // iPhone 15 logical pixels
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(48),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(180),
                      blurRadius: 60,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(48),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Wallpaper
                      _WallpaperBackground(),
                      // Home screen content
                      Positioned.fill(
                        child: Column(
                          children: [
                            // Status bar + time
                            _StatusBar(time: timeStr),
                            const SizedBox(height: 8),
                            // Lock screen date
                            Text(
                              dateStr,
                              style: GoogleFonts.barlow(
                                fontSize: 13,
                                color: Colors.white.withAlpha(180),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Widget
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: child,
                            ),
                          ],
                        ),
                      ),
                      // Dynamic Island overlay
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 120,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      // Frame border
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(48),
                              border: Border.all(
                                color: Colors.white.withAlpha(30),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── Controls ──────────────────────────────────────────────────────
        bottomContent,
      ],
    );
  }
}

class _WallpaperBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0D1B2A), // deep navy
            Color(0xFF1A3A2A), // deep forest
            Color(0xFF0F2318), // near-black green
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: _BookPatternPainter(),
      ),
    );
  }
}

// Subtle decorative book-spine pattern for the wallpaper
class _BookPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final rng = math.Random(42);
    for (var i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final h = 30 + rng.nextDouble() * 50;
      final w = 4 + rng.nextDouble() * 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 54, 28, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            time,
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Row(
            children: [
              Icon(Icons.signal_cellular_alt, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Icon(Icons.wifi, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Icon(Icons.battery_full, size: 14, color: Colors.white),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Widget renderers (Small / Medium / Large) ─────────────────────────────────
//
// These replicate the visual design of the real Swift WidgetKit extension.
// Keep them visually in sync with MarginaliaWidget.swift.

class _SmallWidget extends StatelessWidget {
  const _SmallWidget({required this.highlight});
  final WidgetHighlight highlight;

  @override
  Widget build(BuildContext context) {
    return _WidgetShell(
      width: 155,
      height: 155,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WidgetBrand(greeting: highlight.timeGreeting, small: true),
          const Spacer(),
          Text(
            _firstSentence(highlight.text, 80),
            style: GoogleFonts.ebGaramond(
              fontSize: 13,
              height: 1.55,
              color: const Color(0xFFF5F2EC),
              fontStyle: FontStyle.italic,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            highlight.bookTitle,
            style: GoogleFonts.barlowCondensed(
              fontSize: 9,
              color: const Color(0xFF9EBB8A),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MediumWidget extends StatelessWidget {
  const _MediumWidget({required this.highlight});
  final WidgetHighlight highlight;

  @override
  Widget build(BuildContext context) {
    return _WidgetShell(
      width: double.infinity,
      height: 155,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: quote text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WidgetBrand(greeting: highlight.timeGreeting),
                const Spacer(),
                Text(
                  _firstSentence(highlight.text, 120),
                  style: GoogleFonts.ebGaramond(
                    fontSize: 13.5,
                    height: 1.6,
                    color: const Color(0xFFF5F2EC),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  highlight.bookTitle,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 9.5,
                    color: const Color(0xFF9EBB8A),
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          // Right: decorative quote mark + weather icon
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '"',
                style: GoogleFonts.ebGaramond(
                  fontSize: 48,
                  height: 0.9,
                  color: const Color(0xFF4A7A35).withAlpha(120),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                _weatherIcon(highlight.weatherMood),
                size: 18,
                color: const Color(0xFF9EBB8A).withAlpha(160),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LargeWidget extends StatelessWidget {
  const _LargeWidget({required this.highlight});
  final WidgetHighlight highlight;

  @override
  Widget build(BuildContext context) {
    return _WidgetShell(
      width: double.infinity,
      height: 330,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WidgetBrand(greeting: highlight.timeGreeting),
          const SizedBox(height: 16),
          // Decorative rule
          Container(
            height: 0.5,
            color: const Color(0xFF9EBB8A).withAlpha(80),
          ),
          const SizedBox(height: 16),
          // Full quote
          Expanded(
            child: Text(
              _firstSentence(highlight.text, 300),
              style: GoogleFonts.ebGaramond(
                fontSize: 16,
                height: 1.72,
                color: const Color(0xFFF5F2EC),
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(height: 12),
          // Book + author row
          Row(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A7A35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      highlight.bookTitle,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF5F2EC),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      highlight.author,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 10,
                        color: const Color(0xFF9EBB8A),
                        letterSpacing: 0.8,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(
                _weatherIcon(highlight.weatherMood),
                size: 20,
                color: const Color(0xFF9EBB8A).withAlpha(180),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Widget shell (shared container) ──────────────────────────────────────────

class _WidgetShell extends StatelessWidget {
  const _WidgetShell({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Matte dark green — matches the iOS widget background in Swift
        color: const Color(0xFF0F2318),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A7A35).withAlpha(60),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WidgetBrand extends StatelessWidget {
  const _WidgetBrand({required this.greeting, this.small = false});
  final String greeting;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF3A6624),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Center(
            child: Text(
              'M',
              style: TextStyle(
                color: Color(0xFFF5F2EC),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'serif',
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (!small)
          Text(
            greeting,
            style: GoogleFonts.barlow(
              fontSize: 11,
              color: const Color(0xFF9EBB8A),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
      ],
    );
  }
}

// ── Bottom bar (info + actions) ───────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.highlight,
    required this.pushed,
    required this.onPush,
    required this.onRefresh,
  });

  final WidgetHighlight highlight;
  final bool pushed;
  final VoidCallback onPush;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        children: [
          // AI context pills
          Row(
            children: [
              _ContextPill(
                icon: Icons.access_time_rounded,
                label: highlight.timeGreeting,
              ),
              const SizedBox(width: 8),
              _ContextPill(
                icon: _weatherIcon(highlight.weatherMood),
                label: _weatherLabel(highlight.weatherMood),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onRefresh,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: Colors.white.withAlpha(100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Push to widget button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: pushed ? null : onPush,
              style: FilledButton.styleFrom(
                backgroundColor: pushed
                    ? const Color(0xFF3A6624).withAlpha(100)
                    : const Color(0xFF3A6624),
                foregroundColor: const Color(0xFFF5F2EC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                pushed
                    ? 'Widget aggiornato ✓'
                    : 'Invia al widget iOS',
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          if (!pushed) ...[
            const SizedBox(height: 8),
            Text(
              'Richiede installazione del widget su iPhone',
              style: GoogleFonts.barlow(
                fontSize: 11,
                color: Colors.white.withAlpha(60),
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF9EBB8A)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 11,
              color: Colors.white.withAlpha(160),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Size selector ─────────────────────────────────────────────────────────────

enum _WidgetSize { small, medium, large }

class _SizeSelector extends StatelessWidget {
  const _SizeSelector({required this.current, required this.onChanged});
  final _WidgetSize current;
  final ValueChanged<_WidgetSize> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in _WidgetSize.values)
          GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: s == current
                    ? const Color(0xFF3A6624)
                    : Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                switch (s) {
                  _WidgetSize.small  => 'S',
                  _WidgetSize.medium => 'M',
                  _WidgetSize.large  => 'L',
                },
                style: GoogleFonts.barlow(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _firstSentence(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  // Try to break at a sentence boundary
  final cut = text.substring(0, maxChars);
  final dot = cut.lastIndexOf('.');
  if (dot > maxChars * 0.6) return '${text.substring(0, dot + 1)}';
  return '${cut.trimRight()}…';
}

IconData _weatherIcon(String mood) => switch (mood) {
      'sunny'  => Icons.wb_sunny_outlined,
      'rain'   => Icons.water_drop_outlined,
      'cloudy' => Icons.cloud_outlined,
      'snow'   => Icons.ac_unit_outlined,
      _        => Icons.nights_stay_outlined,
    };

String _weatherLabel(String mood) => switch (mood) {
      'sunny'  => 'Sole',
      'rain'   => 'Pioggia',
      'cloudy' => 'Nuvoloso',
      'snow'   => 'Neve',
      _        => 'Cielo',
    };
