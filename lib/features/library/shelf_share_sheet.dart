// ─── Share your shelf as a post ──────────────────────────────────────────────
//
// Turns the bookshelf into something other people can answer.
//
// The post is a poster of your shelf plus ONE question. That question is the
// whole point: a picture of somebody's books is pleasant, a picture that asks
// you something is a conversation. Friends reply in the comments, which the
// feed already supports — no new post type, no new table, nothing to moderate
// that isn't already moderated.
//
// The default question is the good one: "guess which book I've highlighted
// most". It works because the shelf already encodes the answer — spine
// thickness IS highlight count — so the picture is playable rather than
// merely pretty, and answering teaches you to read the shelf. The caption
// carries that rule so the game is fair.
//
// Only a curated slice goes on the poster: the sixteen most-marked books, put
// back into alphabetical order so the fattest spine is somewhere in the middle
// instead of sitting first and giving the game away.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../social/feed_tab.dart' show postsProvider;
import 'bookshelf_view.dart';

/// How many books make it onto the poster.
const int _kPosterBooks = 14;

/// The poster's shelf is drawn smaller than the reading one.
const double _kPosterScale = 0.64;

/// Fixed design width the poster's shelf is laid out against, so the number of
/// rows is a property of the design and not of the phone it is rendered on.
const double _kPosterShelfWidth = 260;

/// The question printed on the poster and used as the post body.
enum ShelfPrompt { guess, next, recommend, none }

Future<void> showShelfShareSheet(
  BuildContext context, {
  required List<ShelfEntry> entries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShelfShareSheet(entries: entries),
  );
}

class _ShelfShareSheet extends ConsumerStatefulWidget {
  const _ShelfShareSheet({required this.entries});

  final List<ShelfEntry> entries;

  @override
  ConsumerState<_ShelfShareSheet> createState() => _ShelfShareSheetState();
}

class _ShelfShareSheetState extends ConsumerState<_ShelfShareSheet> {
  final _posterKey = GlobalKey();
  ShelfPrompt _prompt = ShelfPrompt.guess;
  bool _publishing = false;

  /// The most-marked books, handed back in alphabetical order so the thickest
  /// spine is not simply the first one.
  late final List<ShelfEntry> _poster = () {
    final sorted = [...widget.entries]
      ..sort((a, b) => b.highlightCount.compareTo(a.highlightCount));
    final top = sorted.take(_kPosterBooks).toList()
      ..sort((a, b) =>
          a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));
    return top;
  }();

  String _question(BuildContext context) => switch (_prompt) {
        ShelfPrompt.guess     => context.l10n.shelfSharePromptGuess,
        ShelfPrompt.next      => context.l10n.shelfSharePromptNext,
        ShelfPrompt.recommend => context.l10n.shelfSharePromptRecommend,
        ShelfPrompt.none      => '',
      };

  /// The post body. For the guessing game it also spells out the rule, so the
  /// question is answerable by anyone rather than only by people who already
  /// know how a Scripta shelf is drawn.
  String _caption(BuildContext context) {
    final q = _question(context);
    final base = context.l10n.shelfSharePostBody(widget.entries.length);
    if (q.isEmpty) return base;
    if (_prompt == ShelfPrompt.guess) {
      return '$base\n\n$q\n${context.l10n.shelfShareGuessHint}';
    }
    return '$base\n\n$q';
  }

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);

    final messenger = ScaffoldMessenger.of(context);
    final l10n      = context.l10n;
    final caption   = _caption(context);
    final navigator = Navigator.of(context);

    try {
      // One extra frame so the RepaintBoundary has certainly painted.
      await Future<void>.delayed(const Duration(milliseconds: 90));

      final boundary = _posterKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('poster not ready');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final data  = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('poster not encodable');

      final supabase = ref.read(supabaseServiceProvider);
      final url = await supabase.uploadPostImage(data.buffer.asUint8List(), 'png');
      await supabase.createPost(body: caption, imageUrl: url);

      ref.invalidate(postsProvider);

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shelfSharePosted)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.shelfShareError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(myDisplayNameProvider).asData?.value ?? '';

    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).size.height * 0.08,
      ),
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

              // ── The poster, exactly as it will be posted ──────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: RepaintBoundary(
                  key: _posterKey,
                  child: _ShelfPoster(
                    entries:  _poster,
                    userName: name,
                    question: _question(context),
                    totalBooks: widget.entries.length,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── The question makes it a post people answer ────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.shelfSharePromptLabel.toUpperCase(),
                    style: ScriptaTextStyles.sectionTitle.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: ScriptaColors.inkFaint,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in ShelfPrompt.values)
                      _PromptChip(
                        label: switch (p) {
                          ShelfPrompt.guess     => context.l10n.shelfSharePromptGuess,
                          ShelfPrompt.next      => context.l10n.shelfSharePromptNext,
                          ShelfPrompt.recommend => context.l10n.shelfSharePromptRecommend,
                          ShelfPrompt.none      => context.l10n.shelfSharePromptNone,
                        },
                        active: _prompt == p,
                        onTap: () => setState(() => _prompt = p),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _publishing ? null : _publish,
                    style: FilledButton.styleFrom(
                      backgroundColor: ScriptaColors.primary,
                      foregroundColor: ScriptaColors.ink,
                      disabledBackgroundColor: ScriptaColors.primaryFaint,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _publishing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ScriptaColors.primaryDark,
                            ),
                          )
                        : Text(
                            context.l10n.shelfSharePublish,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
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

// ─── Prompt chip ─────────────────────────────────────────────────────────────

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool   active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: active ? ScriptaColors.primary : ScriptaColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? ScriptaColors.primary : ScriptaColors.rule,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? ScriptaColors.ink : ScriptaColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

// ─── The poster ──────────────────────────────────────────────────────────────

class _ShelfPoster extends StatelessWidget {
  const _ShelfPoster({
    required this.entries,
    required this.userName,
    required this.question,
    required this.totalBooks,
  });

  final List<ShelfEntry> entries;
  final String userName;
  final String question;
  final int    totalBooks;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: BoxDecoration(
          // Paper, like every other reading surface in the app — the books
          // supply all the colour a poster needs.
          color: ScriptaColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ScriptaColors.rule, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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

              // ── The shelf ─────────────────────────────────────────────────
              // Laid out at ONE fixed design width, then scaled down to
              // whatever room the poster has. Letting it lay out against the
              // live width would change the number of rows from phone to phone
              // — and a row too many overflows a fixed 4:5 card.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: _kPosterShelfWidth,
                      child: BookshelfView(
                        entries: entries,
                        scale: _kPosterScale,
                        onOpen: (_) {},
                      ),
                    ),
                  ),
                ),
              ),

              // ── The question ──────────────────────────────────────────────
              if (question.isNotEmpty) ...[
                Text(
                  question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: ScriptaColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Footer ────────────────────────────────────────────────────
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
                  Text(
                    'get-scripta.app',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.inkFaint,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const ScriptaMark(size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
