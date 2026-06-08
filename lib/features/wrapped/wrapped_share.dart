// ─── Reading Wrapped — shareable 9:16 card capture + post flow ───────────────
//
// Reuses the exact, battle-tested capture pipeline from
// highlight_story_share.dart: a VISIBLE RepaintBoundary (so it always paints),
// font pre-warm, multi-frame wait, and a retry loop around `toImage`. The
// captured 1080×1920 PNG can go to Instagram Stories, the camera roll, or the
// system share sheet.
//
// The thing we render is [WrappedShareCard] — a dedicated 1080×1920 layout that
// re-stages a single Wrapped story (passed in as a [WrappedStorySlide]) with the
// brand mark and a subtle "marginalia.app" footer, so the shared image is
// polished and on-brand regardless of how the on-screen card was laid out.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/services/gallery_saver.dart';
import '../../core/services/instagram_share.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils/share_helper.dart';
import 'wrapped_slides.dart';

// Logical design size; rendered at pixelRatio 3 → 1080×1920 (9:16).
const double _kStoryWidth = 360;
const double _kStoryHeight = 640;
const double _kStoryPixelRatio = 3.0;

const Color _cream = Color(0xFFF1EEE7);

/// Opens a bottom sheet previewing [slide] as a 9:16 share card, with buttons to
/// post it to Instagram Stories, save it, or share via the system sheet.
Future<void> shareWrappedSlide(
  BuildContext context, {
  required WrappedStorySlide slide,
}) async {
  if (kIsWeb) {
    // Web can't rasterise reliably and has no Instagram app — share text.
    final origin = shareOrigin(context);
    await Share.share(
      '${slide.shareCaption}\n\nmarginalia.app',
      sharePositionOrigin: origin,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MarginaliaColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _WrappedSharePreviewSheet(slide: slide),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Preview sheet
// ═══════════════════════════════════════════════════════════════════════════

class _WrappedSharePreviewSheet extends StatefulWidget {
  const _WrappedSharePreviewSheet({required this.slide});
  final WrappedStorySlide slide;

  @override
  State<_WrappedSharePreviewSheet> createState() =>
      _WrappedSharePreviewSheetState();
}

class _WrappedSharePreviewSheetState extends State<_WrappedSharePreviewSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _instagramAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    instagramStoriesAvailable().then((available) {
      if (mounted) setState(() => _instagramAvailable = available);
    });
    // Pre-load the fonts the card uses so the FIRST capture doesn't race glyph
    // loading — the documented cause of blank captures in release builds.
    GoogleFonts.pendingFonts([
      GoogleFonts.ebGaramond(),
      GoogleFonts.manrope(),
    ]);
  }

  /// Rasterises the VISIBLE card. A visible RepaintBoundary always has a painted
  /// layer, so this can't silently produce null.
  Future<Uint8List?> _capturePng() async {
    try {
      RenderRepaintBoundary? boundary;
      for (var i = 0; i < 16; i++) {
        await WidgetsBinding.instance.endOfFrame;
        boundary = _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null && boundary.hasSize && !boundary.size.isEmpty) {
          await WidgetsBinding.instance.endOfFrame;
          await WidgetsBinding.instance.endOfFrame;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (boundary == null || !boundary.hasSize) return null;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final image = await boundary.toImage(pixelRatio: _kStoryPixelRatio);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final bytes = byteData?.buffer.asUint8List();
          if (bytes != null && bytes.isNotEmpty) return bytes;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _writeTempPng(Uint8List bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/marginalia_wrapped_${DateTime.now().millisecondsSinceEpoch}.png';
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
      text: widget.slide.shareCaption,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _saveToPhotos() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final it = Localizations.localeOf(context).languageCode == 'it';
    final png = await _capturePng();
    if (png == null) {
      messenger?.showSnackBar(
          SnackBar(content: Text(context.l10n.shareStoryError)));
      if (mounted) setState(() => _busy = false);
      return;
    }
    final ok = await saveImageToGallery(png);
    if (mounted) setState(() => _busy = false);
    messenger?.showSnackBar(SnackBar(
      content: Text(ok
          ? (it ? 'Salvata nelle foto' : 'Saved to your photos')
          : (it ? 'Impossibile salvare la foto' : "Couldn't save the photo")),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
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
              l10n.wrappedShareTitle,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.wrappedShareTagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MarginaliaColors.primaryDark,
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
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: SizedBox(
                      width: _kStoryWidth,
                      height: _kStoryHeight,
                      child: WrappedShareCard(slide: widget.slide),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_instagramAvailable) ...[
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _shareToInstagram,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE1306C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 22),
                  label: Text(
                    l10n.storyShareInstagram,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _saveToPhotos,
                style: OutlinedButton.styleFrom(
                  foregroundColor: MarginaliaColors.primaryDark,
                  side: const BorderSide(color: MarginaliaColors.rule),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  Localizations.localeOf(context).languageCode == 'it'
                      ? 'Salva foto'
                      : 'Save photo',
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
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
// Share card — 1080×1920 (360×640 logical, ×3 pixel ratio)
// ═══════════════════════════════════════════════════════════════════════════

/// A polished 9:16 render of a single Wrapped [slide]: the slide's gradient,
/// its editorial content re-staged for a story frame, the brand mark, and a
/// subtle "marginalia.app" footer.
class WrappedShareCard extends StatelessWidget {
  const WrappedShareCard({super.key, required this.slide});
  final WrappedStorySlide slide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kStoryWidth,
      height: _kStoryHeight,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient base from the slide's palette.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: slide.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Soft radial vignette to focus the centre.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [Colors.transparent, Color(0x33000000)],
                    stops: [0.55, 1.0],
                  ),
                ),
              ),
            ),

            // The re-staged slide content.
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 96, 36, 110),
              child: Center(
                child: slide.buildShareBody(context),
              ),
            ),

            // ── Top wordmark ─────────────────────────────────────────────
            Positioned(
              top: 44,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'READING WRAPPED',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _cream.withAlpha(196),
                    letterSpacing: 3.0,
                  ),
                ),
              ),
            ),

            // ── Bottom-right brand mark + marginalia.app ─────────────────
            Positioned(
              right: 26,
              bottom: 30,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'MARGINALIA',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _cream.withAlpha(217),
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'marginalia.app',
                        style: GoogleFonts.manrope(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: _cream.withAlpha(150),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 9),
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
                          color: Colors.black.withAlpha(89),
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
