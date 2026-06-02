import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n_extension.dart';

import '../utils/share_helper.dart';

import '../theme.dart';
import 'share_file_helper.dart';

// Generates an Instagram/Spotify-style share card for a Kindle highlight.
//
// Usage:
//   await ShareCardService.show(context,
//     content: h.content, bookTitle: h.bookTitle,
//     bookAuthor: h.bookAuthor, kindleColor: h.color);
class ShareCardService {
  ShareCardService._();

  static Future<void> show(
    BuildContext context, {
    required String content,
    String? bookTitle,
    String? bookAuthor,
    String? kindleColor,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(
        content: content,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        kindleColor: kindleColor,
      ),
    );
  }

  /// Stats-mode share: a card showing books / streak / minutes + a
  /// short headline, suitable for posting to Instagram stories
  /// (4:5 aspect ratio, Marginalia branding watermark).
  /// Reuses [_ShareSheet]'s capture+share pipeline; the difference is
  /// only the rendered card content.
  static Future<void> showStats(
    BuildContext context, {
    required String userName,
    required int booksThisYear,
    required int streakDays,
    required int monthMinutes,
    int? yearGoal,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareSheet.stats(
        userName: userName,
        booksThisYear: booksThisYear,
        streakDays: streakDays,
        monthMinutes: monthMinutes,
        yearGoal: yearGoal,
      ),
    );
  }
}

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.content,
    this.bookTitle,
    this.bookAuthor,
    this.kindleColor,
  })  : statsUserName  = null,
        statsBooks     = null,
        statsStreak    = null,
        statsMinutes   = null,
        statsYearGoal  = null;

  const _ShareSheet.stats({
    required String userName,
    required int booksThisYear,
    required int streakDays,
    required int monthMinutes,
    int? yearGoal,
  })  : content       = '',
        bookTitle     = null,
        bookAuthor    = null,
        kindleColor   = null,
        statsUserName = userName,
        statsBooks    = booksThisYear,
        statsStreak   = streakDays,
        statsMinutes  = monthMinutes,
        statsYearGoal = yearGoal;

  final String content;
  final String? bookTitle;
  final String? bookAuthor;
  final String? kindleColor;

  // Stats variant — when these are non-null, render _StatsShareCard
  // instead of _ShareCard.
  final String? statsUserName;
  final int?    statsBooks;
  final int?    statsStreak;
  final int?    statsMinutes;
  final int?    statsYearGoal;

  bool get isStats => statsUserName != null;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  bool _capturing = false;

  // ── Share as image ──────────────────────────────────────────────────────────

  Future<void> _shareImage() async {
    if (_capturing) return;
    final origin = shareOrigin(context);
    setState(() => _capturing = true);

    try {
      if (kIsWeb) {
        await Share.share(_buildShareText(), sharePositionOrigin: origin);
        return;
      }

      // One extra frame so the RepaintBoundary finishes painting
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        await Share.share(_buildShareText(), sharePositionOrigin: origin);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        await Share.share(_buildShareText(), sharePositionOrigin: origin);
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/marginalia_${DateTime.now().millisecondsSinceEpoch}.png';

      await writeShareFile(path, bytes);
      await Share.shareXFiles([XFile(path)], text: _buildShareText(), sharePositionOrigin: origin);
    } catch (_) {
      // Fallback to text-only share on any error
      await Share.share(_buildShareText(), sharePositionOrigin: origin);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  String _buildShareText() {
    final excerpt = widget.content.length > 140
        ? '${widget.content.substring(0, 140)}…'
        : widget.content;
    final book =
        widget.bookTitle != null ? '\n— ${widget.bookTitle}' : '';
    return '❝ $excerpt ❞$book\n\nApri in Marginalia → https://marginalia.app';
  }

  // ── Copy to clipboard ───────────────────────────────────────────────────────

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.highlightCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).size.height * 0.12,
      ),
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ─────────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── Title ──────────────────────────────────────────────────────────
          const Text(
            'Share highlight',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 24),

          // ── Card preview ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: RepaintBoundary(
              key: _cardKey,
              child: widget.isStats
                  ? _StatsShareCard(
                      userName:      widget.statsUserName!,
                      booksThisYear: widget.statsBooks!,
                      streakDays:    widget.statsStreak!,
                      monthMinutes:  widget.statsMinutes!,
                      yearGoal:      widget.statsYearGoal,
                    )
                  : _ShareCard(
                      content: widget.content,
                      bookTitle: widget.bookTitle,
                      bookAuthor: widget.bookAuthor,
                      kindleColor: widget.kindleColor,
                    ),
            ),
          )
              .animate()
              .fadeIn(duration: 350.ms, curve: Curves.easeOut)
              .scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1.0, 1.0),
                duration: 350.ms,
                curve: Curves.easeOut,
              ),

          const SizedBox(height: 28),

          // ── Action buttons ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyText,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copia'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MarginaliaColors.inkMuted,
                      side: const BorderSide(color: MarginaliaColors.rule),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _capturing ? null : _shareImage,
                    icon: _capturing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.ios_share, size: 16),
                    label:
                        Text(_capturing ? 'Preparing…' : 'Share image'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MarginaliaColors.primary,
                      foregroundColor: const Color(0xFFF1EEE7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

// ─── Share card widget ────────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.content,
    this.bookTitle,
    this.bookAuthor,
    this.kindleColor,
  });

  final String content;
  final String? bookTitle;
  final String? bookAuthor;
  final String? kindleColor;

  List<Color> get _gradientColors => switch (kindleColor) {
        'blue'   => [const Color(0xFF192736), const Color(0xFF2C3E52)],
        'pink'   => [const Color(0xFF3A1828), const Color(0xFF5C2D40)],
        'orange' => [const Color(0xFF3A2010), const Color(0xFF5A3820)],
        _        => [const Color(0xFF2C2018), const Color(0xFF4C3B2A)],
      };

  String get _excerpt {
    if (content.length <= 220) return content;
    final sub = content.substring(0, 220);
    final lastSpace = sub.lastIndexOf(' ');
    return lastSpace > 160 ? '${sub.substring(0, lastSpace)}…' : '$sub…';
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // ── Decorative oversized quote mark ───────────────────────────────
            Positioned(
              top: -10,
              left: 18,
              child: Text(
                '❝',
                style: GoogleFonts.ebGaramond(
                  fontSize: 130,
                  height: 0.8,
                  color: Colors.white.withAlpha(14),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // ── MARGINALIA wordmark ───────────────────────────────────────────
            Positioned(
              top: 18,
              right: 18,
              child: Text(
                'MARGINALIA',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withAlpha(65),
                  letterSpacing: 3.5,
                ),
              ),
            ),

            // ── Main content ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 50, 26, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lora italic quote
                  Expanded(
                    child: Text(
                      _excerpt,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 14.5,
                        height: 1.85,
                        color: const Color(0xFFEDE5D5),
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.fade,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Thin separator
                  Container(
                    height: 0.5,
                    color: Colors.white.withAlpha(35),
                  ),

                  const SizedBox(height: 12),

                  // Book title + author + "marginalia.app" badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (bookTitle != null && bookTitle!.isNotEmpty)
                              Text(
                                bookTitle!,
                                style: GoogleFonts.ebGaramond(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withAlpha(200),
                                  height: 1.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (bookAuthor != null && bookAuthor!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  bookAuthor!.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withAlpha(90),
                                    letterSpacing: 0.9,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withAlpha(35),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          'marginalia.app',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withAlpha(130),
                            letterSpacing: 0.4,
                          ),
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

// ─── Stats share card ─────────────────────────────────────────────────────────
//
// Strava-style snapshot of the user's reading week: 3 big numbers + a
// short headline, ready to drop into an Instagram story. 4:5 aspect
// matches IG portrait. All deterministic — no network, no API costs.

class _StatsShareCard extends StatelessWidget {
  const _StatsShareCard({
    required this.userName,
    required this.booksThisYear,
    required this.streakDays,
    required this.monthMinutes,
    this.yearGoal,
  });

  final String userName;
  final int    booksThisYear;
  final int    streakDays;
  final int    monthMinutes;
  final int?   yearGoal;

  String _fmtMinutes(int m) {
    if (m <= 0) return '0m';
    final h = m ~/ 60;
    final mm = m % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h ${mm}m';
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B2A1A), Color(0xFF2E4D24)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // ── Decorative big M ───────────────────────────────────────
            Positioned(
              top: -30,
              right: -20,
              child: Text(
                'M',
                style: GoogleFonts.ebGaramond(
                  fontSize: 300,
                  height: 0.8,
                  color: const Color(0xFFF1EEE7).withAlpha(10),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // ── Wordmark + user ───────────────────────────────────────
            Positioned(
              top: 24,
              left: 28,
              right: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MARGINALIA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFF1EEE7).withAlpha(160),
                      letterSpacing: 3.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La lettura di $userName',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 18,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFFF1EEE7),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            // ── Three big numbers ─────────────────────────────────────
            Positioned(
              top: 0, bottom: 0, left: 0, right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BigStat(
                      value: yearGoal != null
                          ? '$booksThisYear/$yearGoal'
                          : booksThisYear.toString(),
                      label: 'LIBRI ${DateTime.now().year}',
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _BigStat(
                            value: streakDays.toString(),
                            label: 'GIORNI DI FILA',
                            smaller: true,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 60,
                          color: const Color(0xFFF1EEE7).withAlpha(40),
                        ),
                        Expanded(
                          child: _BigStat(
                            value: _fmtMinutes(monthMinutes),
                            label: 'QUESTO MESE',
                            smaller: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer URL ────────────────────────────────────────────
            Positioned(
              bottom: 22,
              left: 28,
              right: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'marginalia.app',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF1EEE7).withAlpha(180),
                      letterSpacing: 1.4,
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1EEE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'M',
                      style: GoogleFonts.ebGaramond(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1B2A1A),
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

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.value,
    required this.label,
    this.smaller = false,
  });
  final String value;
  final String label;
  final bool   smaller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.ebGaramond(
            fontSize: smaller ? 38 : 64,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF1EEE7),
            letterSpacing: -1.5,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: smaller ? 9 : 11,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF1EEE7).withAlpha(150),
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}
