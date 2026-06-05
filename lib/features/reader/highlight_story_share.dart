// ─── Share a highlight as an Instagram-Story image (9:16) ──────────────────
//
// Renders a 1080×1920 card built around the Marginalia-generated book cover for
// the highlight's book — heavily blurred with a dark scrim so the quote sits
// legibly on top — and lets the user post it.
//
// WHY A VISIBLE PREVIEW (the fix): the old flow rendered the card OFF-SCREEN and
// blind-shared the PNG. When the off-screen rasterisation hiccupped it fell back
// to sharing plain TEXT — which is exactly why "Instagram Stories" never showed
// (Stories only accept image/video) and no image preview appeared. Now the card
// is shown in a bottom sheet (so the user SEES it) and captured from a VISIBLE
// RepaintBoundary (which always paints), guaranteeing a real image every time.
//
// Two ways out of the sheet:
//   • "Instagram Stories" — only shown when Instagram is installed; hands the
//     PNG straight to the Stories composer via the native channel
//     (ios/Runner/AppDelegate.swift → instagram-stories:// + pasteboard).
//   • "Altre app"        — the system share sheet (Share.shareXFiles) with the
//     real PNG attached, so a thumbnail + Instagram/WhatsApp/etc. all appear.
//
// Public surface (unchanged for callers):
//   • HighlightStoryCard         — the 1080×1920 layout widget.
//   • shareHighlightAsStory(...) — opens the preview sheet.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/services/instagram_share.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/theme.dart';
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

/// Opens a bottom sheet previewing [text] (plus optional [title] / [author]) as
/// a 9:16 story card, with buttons to post it to Instagram Stories or share it
/// via the system sheet.
Future<void> shareHighlightAsStory(
  BuildContext context, {
  required String text,
  String? title,
  String? author,
}) async {
  // Web can't rasterise reliably and has no Instagram app — share text instead
  // so the action still does something useful.
  if (kIsWeb) {
    final origin = shareOrigin(context);
    await Share.share(
      _storyShareText(context.l10n.shareHighlightCallToAction, text, title),
      sharePositionOrigin: origin,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StoryPreviewSheet(text: text, title: title, author: author),
  );
}

String _storyShareText(String cta, String text, String? title) {
  final excerpt = text.length > 140 ? '${text.substring(0, 140)}…' : text;
  final book = (title != null && title.isNotEmpty) ? '\n— $title' : '';
  return '❝ $excerpt ❞$book\n\n$cta → https://marginalia.app';
}

// ═══════════════════════════════════════════════════════════════════════════
// Preview sheet
// ═══════════════════════════════════════════════════════════════════════════

class _StoryPreviewSheet extends StatefulWidget {
  const _StoryPreviewSheet({required this.text, this.title, this.author});

  final String text;
  final String? title;
  final String? author;

  @override
  State<_StoryPreviewSheet> createState() => _StoryPreviewSheetState();
}

class _StoryPreviewSheetState extends State<_StoryPreviewSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _instagramAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Decide whether to show the dedicated Instagram button (iOS + IG installed).
    instagramStoriesAvailable().then((available) {
      if (mounted) setState(() => _instagramAvailable = available);
    });
  }

  /// Rasterises the VISIBLE card. A visible RepaintBoundary always has a painted
  /// layer, so unlike the old off-screen path this can't silently produce null.
  Future<Uint8List?> _capturePng() async {
    try {
      // One frame of breathing room so Google Fonts / blur have settled.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      if (boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      final image = await boundary.toImage(pixelRatio: _kStoryPixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _writeTempPng(Uint8List bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/marginalia_story_${DateTime.now().millisecondsSinceEpoch}.png';
      await writeShareFile(path, bytes);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareToInstagram() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final png = await _capturePng();
    if (png == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.shareStoryError)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    final ok = await shareImageToInstagramStories(png);
    if (ok) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    // Instagram refused / closed unexpectedly → fall back to the system sheet.
    await _shareViaSystem(prebuilt: png);
  }

  Future<void> _shareViaSystem({Uint8List? prebuilt}) async {
    if (_busy && prebuilt == null) return;
    if (!_busy) setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final origin = shareOrigin(context);
    final png = prebuilt ?? await _capturePng();
    if (png == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.shareStoryError)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    final path = await _writeTempPng(png);
    if (path == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.shareStoryError)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) Navigator.of(context).pop();
    await Share.shareXFiles(
      [XFile(path, mimeType: 'image/png')],
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    // Display size for the preview: fit comfortably above the buttons.
    final displayWidth =
        (media.size.width * 0.6).clamp(180.0, 250.0).toDouble();
    final displayHeight = displayWidth * (_kStoryHeight / _kStoryWidth);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + media.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle.
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.storyPreviewTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 14),

            // ── The actual preview (this IS what gets shared) ────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  // RepaintBoundary wraps the FULL-SIZE 360×640 card; FittedBox
                  // only scales how it's DISPLAYED. Capture stays 1080×1920.
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: SizedBox(
                      width: _kStoryWidth,
                      height: _kStoryHeight,
                      child: HighlightStoryCard(
                        text: widget.text,
                        title: widget.title,
                        author: widget.author,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Actions ──────────────────────────────────────────────────────
            if (_instagramAvailable) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _shareToInstagram,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE1306C), // Instagram pink
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: Text(
                    l10n.storyShareInstagram,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _shareViaSystem(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MarginaliaColors.ink,
                  side: const BorderSide(color: MarginaliaColors.rule),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: MarginaliaColors.inkMuted),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 20),
                label: Text(
                  l10n.storyShareMore,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
            // which rasterises reliably. OverflowBox lets the cover paint
            // larger than the frame so the heavy blur never reveals
            // transparent edges.
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
                  // Small rounded-square gradient brand mark with an "M".
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
