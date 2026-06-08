// ─── Profile · Activity tab ──────────────────────────────────────────────────
//
// The third face of the OWN profile: two contribution heatmaps — Reading and
// Review (Ripasso) — each in its own card with a one-line summary and a share
// button. A "today" status strip sits on top ("Read today ✓/–", "Reviewed
// today ✓/–"), echoing the founder's "oggi ho letto / ho fatto il ripasso oggi"
// framing.
//
// Tapping a card's share button rasterises a dedicated, gorgeous 1080×1080 share
// card (gradient header + the heatmap + the headline stat + the Scripta
// wordmark) and offers Instagram Stories / Save / system share — reusing the
// exact capture+share infrastructure from highlight_story_share.dart.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/activity_provider.dart';
import '../../core/providers/review_provider.dart';
import '../../core/services/gallery_saver.dart';
import '../../core/services/instagram_share.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils/share_helper.dart';
import '../library/book_cover.dart';
import 'activity_heatmap.dart';

// Warm cream used on the share card's dark gradient header.
const Color _cream = Color(0xFFF1EEE7);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ═══════════════════════════════════════════════════════════════════════════
// Activity tab
// ═══════════════════════════════════════════════════════════════════════════

class ActivityTab extends ConsumerWidget {
  const ActivityTab({
    super.key,
    this.displayName,
    required this.seedColor,
    required this.headerColors,
  });

  /// The profile owner's display name, stamped on the shareable cards.
  final String? displayName;

  /// The profile's chosen background colour (the gradient's mid stop). The
  /// heatmaps + share cards derive their intensity ramp from it so the whole
  /// Activity tab is coherent with the rest of the profile.
  final Color seedColor;

  /// The profile's full gradient (light→mid→dark), reused as the share-card
  /// header so the shared image matches the profile the viewer would land on.
  final List<Color> headerColors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingAsync = ref.watch(readingDaysProvider);
    final reviewAsync = ref.watch(reviewActivityProvider);
    final reviewState = ref.watch(reviewStateProvider).asData?.value;

    final reading = readingAsync.asData?.value ?? const <DateTime, int>{};
    final review = reviewAsync.asData?.value ?? const <DateTime, int>{};
    final today = _dateOnly(DateTime.now());
    final ramp = activityRampFromSeed(seedColor);

    final readToday = (reading[today] ?? 0) > 0;
    // .toLocal() before _dateOnly — Isar may hand back lastReviewedOn in UTC, so
    // its raw y/m/d can be the wrong calendar day.
    final reviewedToday = reviewState?.lastReviewedOn != null &&
        _dateOnly(reviewState!.lastReviewedOn!.toLocal()) == today;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Reading Wrapped entry ───────────────────────────────────────
          _WrappedBanner(headerColors: headerColors)
              .animate()
              .fadeIn(duration: 320.ms)
              .slideY(begin: 0.06, end: 0, duration: 320.ms),

          const SizedBox(height: 16),

          // ── Today status pills ──────────────────────────────────────────
          _TodayStrip(readToday: readToday, reviewedToday: reviewedToday)
              .animate()
              .fadeIn(duration: 320.ms, delay: 40.ms)
              .slideY(begin: 0.05, end: 0, duration: 320.ms),

          const SizedBox(height: 18),

          // ── Card A · Reading ────────────────────────────────────────────
          _ActivityCard(
            title: context.l10n.activityReadingTitle,
            icon: PhosphorIconsRegular.bookOpen,
            data: reading,
            loading: readingAsync.isLoading,
            summary: _readingSummary(context, reading),
            displayName: displayName,
            shareKind: _ActivityKind.reading,
            ramp: ramp,
            seedColor: seedColor,
            headerColors: headerColors,
          ).animate().fadeIn(duration: 360.ms, delay: 60.ms).slideY(
              begin: 0.04, end: 0, duration: 360.ms),

          const SizedBox(height: 16),

          // ── Card B · Review / Ripasso ───────────────────────────────────
          _ActivityCard(
            title: context.l10n.activityReviewTitle,
            icon: PhosphorIconsRegular.brain,
            data: review,
            loading: reviewAsync.isLoading,
            summary: _reviewSummary(context, review, reviewState),
            displayName: displayName,
            shareKind: _ActivityKind.review,
            ramp: ramp,
            seedColor: seedColor,
            headerColors: headerColors,
          ).animate().fadeIn(duration: 400.ms, delay: 120.ms).slideY(
              begin: 0.04, end: 0, duration: 400.ms),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Summary lines ──────────────────────────────────────────────────────

  String _readingSummary(BuildContext context, Map<DateTime, int> data) {
    final days = activeDayCount(data);
    final streak = longestStreak(data);
    return context.l10n.activityReadingSummary(days, streak);
  }

  String _reviewSummary(
    BuildContext context,
    Map<DateTime, int> data,
    dynamic reviewState,
  ) {
    final total = totalCount(data);
    final current = (reviewState?.currentStreak as int?) ?? 0;
    final best = (reviewState?.bestStreak as int?) ?? 0;
    return context.l10n.activityReviewSummary(total, current, best);
  }
}

enum _ActivityKind { reading, review }

// ═══════════════════════════════════════════════════════════════════════════
// Today status strip
// ═══════════════════════════════════════════════════════════════════════════

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.readToday, required this.reviewedToday});
  final bool readToday;
  final bool reviewedToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatusPill(
            label: context.l10n.activityReadTodayLabel,
            done: readToday,
            icon: PhosphorIconsRegular.bookOpen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusPill(
            label: context.l10n.activityReviewedTodayLabel,
            done: reviewedToday,
            icon: PhosphorIconsRegular.brain,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.done,
    required this.icon,
  });
  final String label;
  final bool done;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accent = done ? ScriptaColors.primaryDark : ScriptaColors.inkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: done
            ? ScriptaColors.primaryFaint
            : ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? ScriptaColors.primary.withAlpha(70)
              : ScriptaColors.ruleFaint,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: done ? ScriptaColors.ink : ScriptaColors.inkMuted,
                letterSpacing: -0.1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ✓ when done, an en-dash placeholder otherwise.
          Icon(
            done ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            size: 16,
            color: accent,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reading Wrapped entry banner
// ═══════════════════════════════════════════════════════════════════════════

class _WrappedBanner extends StatelessWidget {
  const _WrappedBanner({required this.headerColors});

  /// The profile gradient, reused so the banner sits in the same world as the
  /// rest of the profile (and the Wrapped story it opens).
  final List<Color> headerColors;

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final mid = headerColors.length >= 2
        ? headerColors[headerColors.length ~/ 2]
        : headerColors.first;
    // Cream on dark presets, near-ink on light ones, so the banner is legible on
    // every profile colour.
    final onColor =
        mid.computeLuminance() > 0.55 ? const Color(0xFF2A2620) : _cream;

    return GestureDetector(
      onTap: () => context.push('/wrapped'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: headerColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: mid.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: onColor.withAlpha(38),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(PhosphorIconsFill.sparkle, size: 20, color: onColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it ? 'La tua settimana, Wrapped' : 'Your week, Wrapped',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: onColor,
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    it
                        ? 'Un recap da condividere sulle storie'
                        : 'A shareable recap for your stories',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onColor.withAlpha(200),
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: onColor.withAlpha(220), size: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Activity card (heatmap + summary + share)
// ═══════════════════════════════════════════════════════════════════════════

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.title,
    required this.icon,
    required this.data,
    required this.loading,
    required this.summary,
    required this.shareKind,
    required this.ramp,
    required this.seedColor,
    required this.headerColors,
    this.displayName,
  });

  final String title;
  final IconData icon;
  final Map<DateTime, int> data;
  final bool loading;
  final String summary;
  final _ActivityKind shareKind;
  final List<Color> ramp;
  final Color seedColor;
  final List<Color> headerColors;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: ScriptaDecorations.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + title + share button.
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ScriptaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: ScriptaColors.primaryDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: ScriptaColors.ink,
                    letterSpacing: -0.3,
                    height: 1.0,
                  ),
                ),
              ),
              Builder(
                builder: (btnContext) => _ShareIconButton(
                  onTap: () => _openShareSheet(btnContext),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // The heatmap (or a quiet skeleton while Isar loads).
          if (loading)
            const _HeatmapSkeleton()
          else
            ActivityHeatmap(
              data: data,
              title: title,
              showTitle: false,
              ramp: ramp,
            ),

          const SizedBox(height: 14),
          const Divider(
              height: 1, thickness: 0.6, color: ScriptaColors.ruleFaint),
          const SizedBox(height: 12),

          // Summary line.
          Text(
            summary,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.inkMuted,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  void _openShareSheet(BuildContext context) {
    final headline = shareKind == _ActivityKind.reading
        ? context.l10n.activityShareReadingHeadline(activeDayCount(data))
        : context.l10n.activityShareReviewHeadline(totalCount(data));
    final cardTitle = title;
    final origin = shareOrigin(context);

    if (kIsWeb) {
      // No rasterise / Instagram on web — share a friendly text line instead so
      // the button still does something.
      Share.share(
        '$headline · $summary\n\nhttps://get-scripta.app',
        sharePositionOrigin: origin,
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ScriptaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ActivityShareSheet(
        kind: shareKind,
        title: cardTitle,
        headline: headline,
        summary: summary,
        data: data,
        displayName: displayName,
        ramp: ramp,
        headerColors: headerColors,
      ),
    );
  }
}

class _ShareIconButton extends StatelessWidget {
  const _ShareIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: context.l10n.activityShareTooltip,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: ScriptaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.ios_share_rounded,
            size: 16,
            color: ScriptaColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _HeatmapSkeleton extends StatelessWidget {
  const _HeatmapSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: ScriptaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Share sheet — preview + Instagram / Save / system share
// (mirrors highlight_story_share.dart's capture flow)
// ═══════════════════════════════════════════════════════════════════════════

// Logical design size; rendered at pixelRatio 3 → 1080×1920 (9:16), so it FILLS
// Instagram Stories with no black bars — same full-bleed format as the highlight
// story share.
const double _kCardWidth = 360;
const double _kCardHeight = 640;
const double _kCardPixelRatio = 3.0;

class _ActivityShareSheet extends StatefulWidget {
  const _ActivityShareSheet({
    required this.kind,
    required this.title,
    required this.headline,
    required this.summary,
    required this.data,
    required this.ramp,
    required this.headerColors,
    this.displayName,
  });

  final _ActivityKind kind;
  final String title;
  final String headline;
  final String summary;
  final Map<DateTime, int> data;
  final List<Color> ramp;
  final List<Color> headerColors;
  final String? displayName;

  @override
  State<_ActivityShareSheet> createState() => _ActivityShareSheetState();
}

class _ActivityShareSheetState extends State<_ActivityShareSheet> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _instagramAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    instagramStoriesAvailable().then((available) {
      if (mounted) setState(() => _instagramAvailable = available);
    });
    // Pre-warm the fonts the card uses so the first capture doesn't race glyph
    // loading (the documented cause of blank captures in release builds).
    GoogleFonts.pendingFonts([
      GoogleFonts.ebGaramond(),
      GoogleFonts.manrope(),
    ]);
  }

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
          final image = await boundary.toImage(pixelRatio: _kCardPixelRatio);
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
          '${tempDir.path}/marginalia_activity_${DateTime.now().millisecondsSinceEpoch}.png';
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
      sharePositionOrigin: origin,
    );
  }

  Future<void> _saveToPhotos() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final it = Localizations.localeOf(context).languageCode == 'it';
    final png = await _capturePng();
    if (png == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.shareStoryError)));
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
    final displayWidth = (media.size.width * 0.62).clamp(190.0, 260.0).toDouble();
    final displayHeight = displayWidth * (_kCardHeight / _kCardWidth);

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
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.activityShareSheetTitle,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ScriptaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.activityShareSheetTagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ScriptaColors.primaryDark,
              ),
            ),
            const SizedBox(height: 16),

            // ── The actual preview (this IS what gets shared) ────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: displayWidth,
                height: displayHeight, // 9:16
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: SizedBox(
                      width: _kCardWidth,
                      height: _kCardHeight,
                      child: ActivityShareCard(
                        kind: widget.kind,
                        title: widget.title,
                        headline: widget.headline,
                        summary: widget.summary,
                        data: widget.data,
                        displayName: widget.displayName,
                        ramp: widget.ramp,
                        headerColors: widget.headerColors,
                        localeTag:
                            Localizations.localeOf(context).toLanguageTag(),
                      ),
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
                  foregroundColor: ScriptaColors.primaryDark,
                  side: const BorderSide(color: ScriptaColors.rule),
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
                  foregroundColor: ScriptaColors.ink,
                  side: const BorderSide(color: ScriptaColors.rule),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ScriptaColors.inkMuted),
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
// Share card — 1080×1080 (rendered at 360×360 logical, ×3 pixel ratio)
// ═══════════════════════════════════════════════════════════════════════════

class ActivityShareCard extends StatelessWidget {
  const ActivityShareCard({
    super.key,
    required this.kind,
    required this.title,
    required this.headline,
    required this.summary,
    required this.data,
    required this.ramp,
    required this.headerColors,
    this.displayName,
    this.localeTag,
  });

  final _ActivityKind kind;
  final String title;
  final String headline;
  final String summary;
  final Map<DateTime, int> data;

  /// Intensity ramp derived from the profile colour (see [activityRampFromSeed]).
  final List<Color> ramp;

  /// The profile gradient, reused as the card header so the shared image matches
  /// the profile's own background.
  final List<Color> headerColors;

  final String? displayName;
  final String? localeTag;

  @override
  Widget build(BuildContext context) {
    final name = (displayName ?? '').trim();
    // A varied editorial cover as the backdrop (seeded by the user's name so it
    // is stable per person), exactly like the highlight story share — then a
    // dark scrim for legibility. Full-bleed 9:16, SQUARE corners → fills
    // Instagram Stories with NO black bars.
    final coverSeed = name.isNotEmpty ? name : 'Scripta';

    return SizedBox(
      width: _kCardWidth,
      height: _kCardHeight,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1) Editorial cover background (sharp, like the highlight story).
            Positioned.fill(
              child: BookEditorialCover(title: coverSeed, author: title),
            ),
            // 2) Dark scrim so the content reads over any cover.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(205),
                      Colors.black.withAlpha(140),
                      Colors.black.withAlpha(220),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            // 3) Content.
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 66, 30, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _cream.withAlpha(220),
                          letterSpacing: 2.4,
                        ),
                      ),
                      const Spacer(),
                      if (name.isNotEmpty)
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _cream.withAlpha(190),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    headline,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ebGaramond(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      color: _cream,
                      height: 1.08,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  // Heatmap on a warm-paper card so it reads over the cover.
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: ScriptaColors.background.withAlpha(244),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ActivityHeatmap(
                          data: data,
                          title: title,
                          showTitle: false,
                          showLegend: true,
                          cellSize: 4.2,
                          cellGap: 1.3,
                          ramp: ramp,
                          localeTag: localeTag,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: ScriptaColors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Brand footer.
                  Row(
                    children: [
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
                      const SizedBox(width: 10),
                      Text(
                        'SCRIPTA',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _cream,
                          letterSpacing: 2.4,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'get-scripta.app',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _cream.withAlpha(160),
                        ),
                      ),
                    ],
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
