// ─── A shelf you can play, inside the feed ───────────────────────────────────
//
// The first version of shared shelves was a PNG with a question in the caption,
// answered — if anyone bothered — in the comments. That is a picture, not an
// interaction. This renders the shelf LIVE from the post's payload and lets a
// reader answer by touching it: tap the spine you believe is the book its owner
// highlighted most, and the shelf answers you on the spot.
//
// Why the verdict is instant: the highlight counts travel inside the post, so
// the correct spine is already known on the device. No spinner, no round trip,
// works with no signal. The one network call happens AFTER the answer is on
// screen, and only records the guess so the post can also say what everyone
// else thought.
//
// It is fair by construction — the shelf draws thickness FROM those same
// counts, so the answer is genuinely visible to anyone who looks carefully.
// That is the whole trick: playing it teaches you to read a Scripta shelf.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import 'bookshelf_view.dart';

/// Payload marker written by the share sheet.
const String kShelfGuessPayloadType = 'shelf_guess';

/// Reads the shelf out of a post row, or null when this post is not one.
ShelfGuessData? shelfGuessFromPost(Map<dynamic, dynamic> post) {
  final payload = post['payload'];
  if (payload is! Map) return null;
  if (payload['type'] != kShelfGuessPayloadType) return null;

  final raw = payload['books'];
  if (raw is! List || raw.isEmpty) return null;

  final entries = <ShelfEntry>[];
  for (final b in raw) {
    if (b is! Map) continue;
    final title = (b['t'] as String?)?.trim() ?? '';
    if (title.isEmpty) continue;
    entries.add(ShelfEntry(
      title: title,
      author: (b['a'] as String?)?.trim() ?? '',
      highlightCount: (b['m'] as num?)?.toInt() ?? 0,
    ));
  }
  if (entries.isEmpty) return null;

  return ShelfGuessData(
    entries: entries,
    playable: payload['question'] == 'guess',
    totalBooks: (payload['total'] as num?)?.toInt() ?? entries.length,
  );
}

class ShelfGuessData {
  const ShelfGuessData({
    required this.entries,
    required this.playable,
    required this.totalBooks,
  });

  final List<ShelfEntry> entries;

  /// Only the "guess" question turns the shelf into a game; the other prompts
  /// share a shelf that is simply browsable.
  final bool playable;
  final int  totalBooks;

  /// The book its owner marked most — the answer, derived rather than stored so
  /// it can never disagree with the spines the reader is looking at.
  int get answerIndex {
    var best = 0;
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].highlightCount > entries[best].highlightCount) best = i;
    }
    return best;
  }
}

// ─── The card ────────────────────────────────────────────────────────────────

class ShelfGuessCard extends ConsumerStatefulWidget {
  const ShelfGuessCard({
    super.key,
    required this.postId,
    required this.data,
    required this.isOwner,
  });

  final String        postId;
  final ShelfGuessData data;

  /// The author already knows the answer, so they get the result instead of
  /// the invitation to play.
  final bool isOwner;

  @override
  ConsumerState<ShelfGuessCard> createState() => _ShelfGuessCardState();
}

class _ShelfGuessCardState extends ConsumerState<ShelfGuessCard> {
  int?  _picked;      // which spine this reader chose
  bool  _revealed = false;
  int   _total    = 0;
  int   _correct  = 0;
  bool  _loadedStats = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// A returning reader sees the post as they left it: played once, answer
  /// showing. Their earlier verdict comes back from the server, the answer
  /// itself from the payload.
  Future<void> _restore() async {
    if (!widget.data.playable) return;
    if (widget.isOwner) {
      await _loadStats();
      if (mounted) setState(() => _revealed = true);
      return;
    }
    try {
      final mine = await ref.read(supabaseServiceProvider).myShelfGuess(widget.postId);
      if (!mounted || mine == null) return;
      setState(() {
        _revealed = true;
        // Their exact pick is not stored — only whether it was right, which is
        // all the card needs to phrase the verdict.
        _picked = mine ? widget.data.answerIndex : null;
      });
      await _loadStats();
    } catch (_) {
      // A stats hiccup must never stop the shelf from being readable.
    }
  }

  Future<void> _loadStats() async {
    try {
      final (total, correct) =
          await ref.read(supabaseServiceProvider).shelfGuessStats(widget.postId);
      if (!mounted) return;
      setState(() {
        _total   = total;
        _correct = correct;
        _loadedStats = true;
      });
    } catch (_) {
      // Leave the crowd line off rather than showing a wrong number.
    }
  }

  Future<void> _guess(int index) async {
    if (_revealed || widget.isOwner || !widget.data.playable) return;

    final right = index == widget.data.answerIndex;

    // Answer first, network second: the verdict is already on the device.
    setState(() {
      _picked   = index;
      _revealed = true;
    });

    try {
      await ref
          .read(supabaseServiceProvider)
          .submitShelfGuess(widget.postId, correct: right);
      await _loadStats();
    } catch (_) {
      // The guess still counts on screen; only the crowd figure is lost.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final answer = data.entries[data.answerIndex];

    return Container(
      decoration: BoxDecoration(
        color: ScriptaColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ScriptaColors.rule, width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── The invitation, or the verdict ───────────────────────────────
          if (data.playable)
            _Headline(
              revealed: _revealed,
              isOwner:  widget.isOwner,
              correct:  _picked != null && _picked == data.answerIndex,
              answer:   answer,
            )
          else
            Text(
              context.l10n.shelfSharePosterFooter(data.totalBooks),
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: ScriptaColors.inkFaint,
                letterSpacing: 1.2,
              ),
            ),

          const SizedBox(height: 12),

          // ── The shelf itself ─────────────────────────────────────────────
          BookshelfView(
            entries: data.entries,
            scale: 0.72,
            poppedIndex: _revealed ? data.answerIndex : null,
            onTap: (i, _) => _guess(i),
          ),

          // ── What everyone else thought ───────────────────────────────────
          if (_revealed && _loadedStats && _total > 0) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.shelfGuessCrowd(
                ((_correct / _total) * 100).round(),
                _total,
              ),
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({
    required this.revealed,
    required this.isOwner,
    required this.correct,
    required this.answer,
  });

  final bool revealed;
  final bool isOwner;
  final bool correct;
  final ShelfEntry answer;

  @override
  Widget build(BuildContext context) {
    if (!revealed) {
      return Row(
        children: [
          const Icon(Icons.touch_app_outlined,
              size: 15, color: ScriptaColors.primaryDark),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              context.l10n.shelfGuessInvite,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.primaryDark,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    }

    final verdict = isOwner
        ? context.l10n.shelfGuessOwner
        : (correct
            ? context.l10n.shelfGuessRight
            : context.l10n.shelfGuessWrong);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          verdict,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isOwner
                ? ScriptaColors.inkMuted
                : (correct ? ScriptaColors.primaryDark : ScriptaColors.red),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          context.l10n.shelfGuessAnswer(answer.title, answer.highlightCount),
          style: GoogleFonts.ebGaramond(
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: ScriptaColors.ink,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: AirbnbMotion.standard);
  }
}
