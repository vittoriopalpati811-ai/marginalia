// ─── Share a highlight as an Instagram-Story image (9:16) ──────────────────
//
// Renders a 1080×1920 card built around the Marginalia-generated book cover
// for the highlight's book — heavily blurred with a dark scrim so the quote
// sits legibly on top — then exports it to a PNG and hands it to the system
// share sheet so the user can drop it straight into Instagram Stories.
//
// Public surface:
//   • HighlightStoryCard            — the 1080×1920 layout widget.
//   • shareHighlightAsStory(...)    — off-screen render → PNG → Share.shareXFiles.
//
// The render is done off-screen via an OverlayEntry (positioned far outside
// the viewport) wrapped in a RepaintBoundary, so the full layout/paint
// pipeline runs — fonts, CustomPaint cover art and ImageFilter.blur all
// resolve — without the card ever being visible to the user. Every step is
// guarded; on any failure we fall back to a plain text share so the button
// never dead-ends.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/utils/share_helper.dart';
import '../library/book_cover.dart';

// Logical design size; rendered at pixelRatio 3 → 1080×1920 (9:16).
const double _kStoryWidth = 360;
const double _kStoryHeight = 640;
const double _kStoryPixelRatio = 3.0; // 360*3 = 1080, 640*3 = 1920

// Warm cream used across the app's dark surfaces (matches share_card_service).
const Color _cream = Color(0xFFF1EEE7);

// ═══════════════════════════════════════════════════════════════════════════
// Public entry point
// ═══════════════════════════════════════════════════════════════════════════

/// Renders [text] (plus optional [title] / [author]) as a 9:16 story image and
/// opens the system share sheet so the user can post it to Instagram Stories.
///
/// Off-screen rendering means [context] only needs to be mounted long enough
/// to read the [Overlay] and locale; the card itself is never shown.
Future<void> shareHighlightAsStory(
  BuildContext context, {
  required String text,
  String? title,
  String? author,
}) async {
  // Resolve everything that needs [context] up front, before any await — the
  // widget may be disposed by the time the async render completes.
  final origin = shareOrigin(context);
  final l10n = context.l10n;
  final fallbackText =
      _storyShareText(l10n.shareHighlightCallToAction, text, title);

  // Web can't rasterise an off-screen RepaintBoundary reliably here — share
  // text instead so the action still does something useful.
  if (kIsWeb) {
    await Share.share(fallbackText, sharePositionOrigin: origin);
    return;
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (overlay == null) {
    await Share.share(fallbackText, sharePositionOrigin: origin);
    return;
  }

  final boundaryKey = GlobalKey();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      // Park the card far outside the visible viewport. It still lays out and
      // paints (so the blur + cover render), but the user never sees it.
      left: -_kStoryWidth * 3,
      top: -_kStoryHeight * 3,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: boundaryKey,
          child: HighlightStoryCard(
            text: text,
            title: title,
            author: author,
          ),
        ),
      ),
    ),
  );

  Uint8List? pngBytes;
  try {
    overlay.insert(entry);

    // Let the off-screen subtree complete a full layout+paint pass. We wait
    // for two frames plus a short delay so Google Fonts and the blur filter
    // have settled before we snapshot.
    await _waitForFrames(2);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary != null) {
      // If layout somehow hasn't happened yet, give it one more frame.
      if (boundary.debugNeedsPaint) {
        await _waitForFrames(1);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      final image = await boundary.toImage(pixelRatio: _kStoryPixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      pngBytes = byteData?.buffer.asUint8List();
    }
  } catch (_) {
    // Swallow — handled by the null check below.
  } finally {
    entry.remove();
  }

  if (pngBytes == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.shareStoryError)));
    await Share.share(fallbackText, sharePositionOrigin: origin);
    return;
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/marginalia_story_${DateTime.now().millisecondsSinceEpoch}.png';
    await writeShareFile(path, pngBytes);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'image/png')],
      sharePositionOrigin: origin,
    );
  } catch (_) {
    await Share.share(fallbackText, sharePositionOrigin: origin);
  }
}

/// Awaits [count] post-frame callbacks so the off-screen tree has time to
/// build, lay out and paint before we rasterise it.
Future<void> _waitForFrames(int count) async {
  for (var i = 0; i < count; i++) {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    // Nudge the pipeline in case we're idle (e.g. nothing else is animating).
    WidgetsBinding.instance.scheduleFrame();
    await completer.future;
  }
}

String _storyShareText(String cta, String text, String? title) {
  final excerpt = text.length > 140 ? '${text.substring(0, 140)}…' : text;
  final book = (title != null && title.isNotEmpty) ? '\n— $title' : '';
  return '❝ $excerpt ❞$book\n\n$cta → https://marginalia.app';
}

// ═══════════════════════════════════════════════════════════════════════════
// Story card — 1080×1920 (rendered at 360×640 logical, ×3 pixel ratio)
// ═══════════════════════════════════════════════════════════════════════════

class HighlightStoryCard extends StatelessWidget {
  const HighlightStoryCard({
    super.key,
    required this.text,
    this.title,
    this.author,
  });

  final String text;
  final String? title;
  final String? author;

  // Quotes longer than this are trimmed at a word boundary so the card never
  // overflows its fixed 9:16 frame.
  String get _excerpt {
    final t = text.trim();
    const max = 320;
    if (t.length <= max) return t;
    final sub = t.substring(0, max);
    final lastSpace = sub.lastIndexOf(' ');
    return lastSpace > max - 60 ? '${sub.substring(0, lastSpace)}…' : '$sub…';
  }

  // Fluid type size: shrink as the quote grows so long passages still fit.
  double get _quoteFontSize {
    final len = _excerpt.length;
    if (len <= 90) return 27;
    if (len <= 150) return 24;
    if (len <= 230) return 21;
    return 18;
  }

  @override
  Widget build(BuildContext context) {
    final safeTitle = (title ?? '').trim();
    final safeAuthor = (author ?? '').trim();
    // The cover art keys off the title, so give it a sensible fallback.
    final coverTitle = safeTitle.isNotEmpty ? safeTitle : 'Marginalia';

    return SizedBox(
      width: _kStoryWidth,
      height: _kStoryHeight,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Blurred book-cover background ──────────────────────────
            // ImageFiltered blurs the cover widget itself (not a backdrop),
            // which rasterises reliably off-screen. OverflowBox lets the
            // cover paint larger than the frame so the heavy blur never
            // reveals transparent edges.
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 55,
                  sigmaY: 55,
                  tileMode: TileMode.decal,
                ),
                child: OverflowBox(
                  minWidth: _kStoryWidth * 1.5,
                  minHeight: _kStoryHeight * 1.5,
                  maxWidth: _kStoryWidth * 1.5,
                  maxHeight: _kStoryHeight * 1.5,
                  child: BookEditorialCover(
                    title: coverTitle,
                    author: safeAuthor,
                  ),
                ),
              ),
            ),

            // ── 2. Dark scrim for text legibility ─────────────────────────
            // Vertical gradient: darker at top/bottom so the wordmark and any
            // tall quote stay readable, slightly lighter through the middle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(184), // ~72%
                      Colors.black.withAlpha(133), // ~52%
                      Colors.black.withAlpha(189), // ~74%
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            // A second, very soft radial vignette to focus the centre.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(71), // ~28%
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),

            // ── 3. Quote + attribution, centred ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 96, 40, 96),
              child: Center(
                // FittedBox guards the fixed 9:16 frame: even after the
                // word-boundary trim + fluid type sizing, an extreme-length
                // highlight (plus a long title/author) is scaled down to fit
                // rather than overflowing the column. Constrained to the
                // content width so only vertical scaling kicks in.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kStoryWidth - 80, // matches L/R padding
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Opening quotation mark — subtle, decorative.
                        Text(
                          '“',
                          style: GoogleFonts.ebGaramond(
                            fontSize: 92,
                            height: 0.7,
                            fontWeight: FontWeight.w600,
                            color: _cream.withAlpha(77), // ~30%
                          ),
                        ),
                        const SizedBox(height: 4),

                        // The highlight — legible roman (NON-italic) Garamond.
                        Text(
                          _excerpt,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ebGaramond(
                            fontSize: _quoteFontSize,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: _cream,
                            letterSpacing: 0.15,
                            shadows: [
                              Shadow(
                                color: Colors.black.withAlpha(115), // ~45%
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),

                        if (safeTitle.isNotEmpty || safeAuthor.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          // Short rule between quote and attribution.
                          Container(
                            width: 34,
                            height: 1.4,
                            decoration: BoxDecoration(
                              color: _cream.withAlpha(140), // ~55%
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (safeTitle.isNotEmpty)
                            Text(
                              safeTitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.ebGaramond(
                                fontSize: 17,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                color: _cream.withAlpha(235), // ~92%
                                height: 1.3,
                              ),
                            ),
                          if (safeAuthor.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              safeAuthor.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _cream.withAlpha(158), // ~62%
                                letterSpacing: 1.6,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 4. Bottom-right Marginalia wordmark + logo mark ───────────
            Positioned(
              right: 28,
              bottom: 34,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MARGINALIA',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _cream.withAlpha(217), // ~85%
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(width: 9),
                  // Small rounded-square gradient brand mark with an "M",
                  // echoing the app's existing mark style.
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A7A35), Color(0xFF254D16)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(89), // ~35%
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'M',
                      style: GoogleFonts.ebGaramond(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _cream,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
