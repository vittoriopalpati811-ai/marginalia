// ─── Share your shelf as a post ──────────────────────────────────────────────
//
// A poster of your shelf, published to the feed as an ordinary image post.
//
// It was briefly something more elaborate — a shelf you could play, tapping the
// spine you thought was the most-highlighted book. The founder's call, after
// seeing it: too much. A shared shelf should be a nice thing to look at, and
// nothing else. So this is a picture: preview it, publish it, done. It likes,
// comments and shares exactly like every other post, with no special case
// anywhere in the feed.
//
// Only a curated slice goes on the poster: the most-marked books, put back into
// alphabetical order so the fattest spine falls somewhere in the middle rather
// than sitting first — the poster reads as a shelf, not as a ranking.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../social/feed_tab.dart' show postsProvider;
import 'bookshelf_view.dart';
import 'shelf_poster.dart';

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
  bool _publishing = false;

  late final List<ShelfEntry> _poster = posterSelection(widget.entries);

  /// The post body: what the picture is, in one line.
  String _caption(BuildContext context) =>
      context.l10n.shelfSharePostBody(widget.entries.length);

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
                  child: ShelfPosterCard(
                    entries:  _poster,
                    userName: name,
                    totalBooks: widget.entries.length,
                  ),
                ),
              ),
              const SizedBox(height: 24),

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
