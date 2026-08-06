// ─── The shelf as a shareable picture ────────────────────────────────────────
//
// One poster, two destinations: published to the Scripta feed as an image post,
// or handed to the system share sheet — which is how it reaches Instagram,
// WhatsApp or anywhere else the phone already knows about. Going through the OS
// rather than Instagram's own scheme means it works on both platforms, needs no
// extra entitlement, and degrades to "no apps installed" instead of a dead end.
//
// The poster is 4:5 — Instagram's portrait format, so nothing is cropped when
// it lands there.
//
// Signed bottom-right, small: the mark and the word Scripta. A shelf that gets
// reposted should say where it came from without shouting about it.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/services/instagram_share.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils/share_helper.dart';
import 'bookshelf_view.dart';

/// Safety valve, not a design choice. The poster shows the WHOLE library —
/// founder: "si devono vedere tutti in maniera leggibile" — but a four-hundred
/// book account would produce a cabinet no card can render legibly at any size,
/// so there is a ceiling. Ordinary libraries never reach it.
const int kPosterBooks = 120;

/// The books that go on a poster, in alphabetical order — so the thickest spine
/// is not simply the first, which would give the reading away at a glance.
///
/// Nothing is dropped below [kPosterBooks]; past it the most-marked books win,
/// because if something must go it should be the books barely read.
List<ShelfEntry> posterSelection(List<ShelfEntry> all) {
  var books = all;
  if (books.length > kPosterBooks) {
    books = [...books]
      ..sort((a, b) => b.highlightCount.compareTo(a.highlightCount));
    books = books.take(kPosterBooks).toList();
  }
  return [...books]
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

/// The design width that leaves the titles as large as they can be.
///
/// The shelf is laid out at a FIXED width and then scaled to fit the card, so
/// that width alone decides how many books stand per row — and therefore how
/// much the whole cabinet has to shrink. Too wide and it is a squat block that
/// wastes the card's height; too narrow and it is a tower that wastes its width.
/// The best is where the cabinet's proportions meet the room's, and since real
/// spine widths vary per book, the honest way to find it is to measure.
///
/// Returns the width whose fitted scale factor is highest — the factor the
/// FittedBox will apply, which multiplies the title's point size directly.
double posterDesignWidth(List<ShelfEntry> entries, Size room) {
  if (entries.isEmpty || room.isEmpty) return 320;

  var best = 320.0;
  var bestFit = 0.0;
  // 240 is about six slim spines; past ~1400 a row is so long that one more
  // book buys nothing. 20-unit steps are finer than one spine width, so the
  // search cannot skip the optimum.
  for (var w = 240.0; w <= 1400.0; w += 20) {
    final size =
        BookshelfView.measureAt(entries, w, metrics: ShelfMetrics.poster);
    if (size.isEmpty) continue;
    final fit = math.min(room.width / size.width, room.height / size.height);
    if (fit > bestFit) {
      bestFit = fit;
      best = w;
    }
  }
  return best;
}

// ─── Share to Instagram (and everywhere else) ────────────────────────────────

/// Shows the poster, then hands it to the system share sheet as a PNG.
Future<void> showShelfImageShareSheet(
  BuildContext context, {
  required List<ShelfEntry> entries,
  required String userName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShelfImageShareSheet(
      entries: entries,
      userName: userName,
    ),
  );
}

class _ShelfImageShareSheet extends StatefulWidget {
  const _ShelfImageShareSheet({required this.entries, required this.userName});

  final List<ShelfEntry> entries;
  final String userName;

  @override
  State<_ShelfImageShareSheet> createState() => _ShelfImageShareSheetState();
}

/// The Instagram Stories canvas, in logical pixels. 9:16, captured at ×3 for a
/// 1080×1920 PNG — the size Instagram wants, so it neither crops nor upsamples.
const double _kStoryWidth  = 360;
const double _kStoryHeight = 640;

class _ShelfImageShareSheetState extends State<_ShelfImageShareSheet> {
  /// The 4:5 card on its own — what the system share sheet and the feed get.
  final _posterKey = GlobalKey();

  /// The same card on a 9:16 ground — what Instagram gets. Two boundaries, both
  /// genuinely painted: Instagram aspect-FILLS a story background, so handing it
  /// the 4:5 card would crop away the cabinet's top rail and the "Scripta"
  /// signature in the bottom-right, which is the one thing the poster is for.
  final _storyKey = GlobalKey();

  bool _sharing = false;
  bool _instagramAvailable = false;

  late final List<ShelfEntry> _poster = posterSelection(widget.entries);

  @override
  void initState() {
    super.initState();
    instagramStoriesAvailable().then((available) {
      if (mounted) setState(() => _instagramAvailable = available);
    });
    // Have the fonts in hand before anything is rasterised. `toImage` racing
    // Google Fonts' network load is what produced blank captures in release
    // builds before — see the note atop highlight_story_share.dart.
    GoogleFonts.pendingFonts([GoogleFonts.ebGaramond(), GoogleFonts.manrope()]);
  }

  /// Rasterises one of the two boundaries. Returns null when it is not ready.
  ///
  /// The story frame is 360×640, so ×3 lands exactly on Instagram's native
  /// 1080×1920 and nothing is resampled. The 4:5 card is smaller on screen and
  /// gets ×4, which puts it above Instagram's 1080×1350 feed size — with a whole
  /// library on the card the type is small, and small type that has been
  /// UPSAMPLED is the difference between fine and mushy.
  Future<Uint8List?> _capture(GlobalKey key, {double pixelRatio = 3.0}) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _shareToInstagram() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final png = await _capture(_storyKey);
      if (png == null) throw Exception('poster not ready');
      if (await shareImageToInstagramStories(png)) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      // Instagram refused or closed — never leave the reader on a dead button.
      if (mounted) setState(() => _sharing = false);
      await _share();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sharing = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.shelfShareError)));
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final origin = shareOrigin(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    try {
      final bytes = await _capture(_posterKey, pixelRatio: 4.0);
      if (bytes == null) throw Exception('poster not ready');

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/scripta_shelf_${DateTime.now().millisecondsSinceEpoch}.png';
      await writeShareFile(path, bytes);

      await Share.shareXFiles([XFile(path)], sharePositionOrigin: origin);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sharing = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.shelfShareError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
      decoration: const BoxDecoration(
        color: ScriptaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ScriptaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.l10n.shelfShareTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: ScriptaColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              // The preview IS the story frame, at the size it will be posted.
              // Both boundaries are on screen and painting — rasterising an
              // off-screen widget is what silently produced blank shares before.
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.46,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RepaintBoundary(
                    key: _storyKey,
                    child: Container(
                      width: _kStoryWidth,
                      height: _kStoryHeight,
                      color: ScriptaColors.background,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: _kStoryWidth * 0.82,
                        child: RepaintBoundary(
                          key: _posterKey,
                          child: ShelfPosterCard(
                            entries: _poster,
                            userName: widget.userName,
                            totalBooks: widget.entries.length,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_instagramAvailable) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _shareToInstagram,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(
                        context.l10n.shelfShareInstagram,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE1306C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ScriptaColors.primaryDark,
                            ),
                          )
                        : const Icon(Icons.ios_share, size: 17),
                    label: Text(
                      _sharing
                          ? context.l10n.shareImagePreparing
                          : context.l10n.shareImageCta,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: ScriptaColors.primary,
                      foregroundColor: ScriptaColors.ink,
                      disabledBackgroundColor: ScriptaColors.primaryFaint,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── The poster ──────────────────────────────────────────────────────────────

class ShelfPosterCard extends StatefulWidget {
  const ShelfPosterCard({
    super.key,
    required this.entries,
    required this.userName,
    required this.totalBooks,
  });

  final List<ShelfEntry> entries;
  final String userName;
  final int    totalBooks;

  @override
  State<ShelfPosterCard> createState() => _ShelfPosterCardState();
}

class _ShelfPosterCardState extends State<ShelfPosterCard> {
  /// The last room the design width was solved for, and the answer.
  ///
  /// `LayoutBuilder` re-runs its callback on every rebuild of the sheet even
  /// when the constraints have not moved — measured at 32 rebuilds while the
  /// share sheet settles — and the search packs the whole library 59 times. The
  /// answer only depends on the room and the books, so it is computed once per
  /// distinct room and reused.
  Size? _solvedFor;
  double _design = 320;

  double _designWidthFor(Size room) {
    if (_solvedFor != room) {
      _solvedFor = room;
      _design = posterDesignWidth(widget.entries, room);
    }
    return _design;
  }

  @override
  void didUpdateWidget(ShelfPosterCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.entries, widget.entries)) _solvedFor = null;
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final userName = widget.userName;
    final totalBooks = widget.totalBooks;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          // Paper, like every other reading surface in the app — the cabinet
          // and the books supply all the colour a poster needs.
          color: ScriptaColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ScriptaColors.rule, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    context.l10n.shelfSharePosterKicker.toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: ScriptaColors.inkFaint,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const Spacer(),
                  if (userName.isNotEmpty)
                    Flexible(
                      child: Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          color: ScriptaColors.inkMuted,
                        ),
                      ),
                    ),
                ],
              ),

              // ── The headline ──────────────────────────────────────────────
              // How many books this is. It reads as the poster's title, which
              // is why it is set in the same serif the app reserves for the
              // books themselves rather than in the UI sans.
              const SizedBox(height: 6),
              Text(
                context.l10n.shelfSharePosterHeadline(totalBooks),
                style: GoogleFonts.ebGaramond(
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.ink,
                ),
              ),
              const SizedBox(height: 8),

              // ── The cabinet ───────────────────────────────────────────────
              // Laid out at ONE design width, then scaled to whatever room the
              // poster has. Letting it lay out against the live width would
              // change the number of shelves from phone to phone — and one
              // shelf too many overflows a fixed 4:5 card.
              //
              // The width is CHOSEN rather than fixed: with the whole library on
              // the card, the difference between a well- and badly-proportioned
              // cabinet is the difference between readable titles and a smudge.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, room) {
                    final design =
                        _designWidthFor(Size(room.maxWidth, room.maxHeight));
                    return Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: design,
                          child: BookshelfView(
                            entries: entries,
                            metrics: ShelfMetrics.poster,
                            onTap: (_, __) {},
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // ── Signature ─────────────────────────────────────────────────
              // The mark and the name bottom-right, small — a maker's stamp,
              // not a watermark. The count used to live down here too; it is
              // the headline now, and printing it twice read as a mistake.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const ScriptaMark(size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Scripta',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ScriptaColors.inkMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
