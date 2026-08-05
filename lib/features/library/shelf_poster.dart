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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/services/share_file_helper.dart';
import '../../core/theme.dart';
import '../../core/utils/share_helper.dart';
import 'bookshelf_view.dart';

/// How many books make it onto the poster.
const int kPosterBooks = 14;

/// The poster's shelf is drawn smaller than the reading one.
const double kPosterScale = 0.64;

/// Fixed design width the poster's shelf is laid out against, so the number of
/// rows is a property of the design and not of the phone rendering it.
const double kPosterShelfWidth = 260;

/// The books that go on a poster: the most-marked ones, handed back in
/// alphabetical order so the thickest spine is not simply the first.
List<ShelfEntry> posterSelection(List<ShelfEntry> all) {
  final sorted = [...all]
    ..sort((a, b) => b.highlightCount.compareTo(a.highlightCount));
  return sorted.take(kPosterBooks).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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

class _ShelfImageShareSheetState extends State<_ShelfImageShareSheet> {
  final _posterKey = GlobalKey();
  bool _sharing = false;

  late final List<ShelfEntry> _poster = posterSelection(widget.entries);

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final origin = shareOrigin(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    try {
      // One extra frame so the RepaintBoundary has certainly painted.
      await Future<void>.delayed(const Duration(milliseconds: 90));

      final boundary =
          _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('poster not ready');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('poster not encodable');

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/scripta_shelf_${DateTime.now().millisecondsSinceEpoch}.png';
      await writeShareFile(path, data.buffer.asUint8List());

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: RepaintBoundary(
                  key: _posterKey,
                  child: ShelfPosterCard(
                    entries: _poster,
                    userName: widget.userName,
                    totalBooks: widget.entries.length,
                  ),
                ),
              ),
              const SizedBox(height: 24),
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

class ShelfPosterCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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

              // ── The cabinet ───────────────────────────────────────────────
              // Laid out at ONE fixed design width, then scaled to whatever room
              // the poster has. Letting it lay out against the live width would
              // change the number of shelves from phone to phone — and one
              // shelf too many overflows a fixed 4:5 card.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: kPosterShelfWidth,
                      child: BookshelfView(
                        entries: entries,
                        scale: kPosterScale,
                        onTap: (_, __) {},
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Signature ─────────────────────────────────────────────────
              // Book count on the left; the mark and the name bottom-right,
              // small — a maker's stamp, not a watermark.
              Row(
                children: [
                  Text(
                    context.l10n.shelfSharePosterFooter(totalBooks),
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.inkFaint,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
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
