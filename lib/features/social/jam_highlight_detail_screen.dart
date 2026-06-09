import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../messages/giphy_picker.dart';

// Reactions per single jam_highlight
final reactionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, jamHighlightId) async {
  try {
    return await ref
        .watch(supabaseServiceProvider)
        .fetchReactions(jamHighlightId);
  } catch (_) {
    return [];
  }
});

// Comments per single jam_highlight
final commentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, jamHighlightId) async {
  try {
    return await ref
        .watch(supabaseServiceProvider)
        .fetchComments(jamHighlightId);
  } catch (_) {
    return [];
  }
});

const _quickReactions = ['❤️', '🔥', '🤯', '💭', '👏', '😢'];

class JamHighlightDetailScreen extends ConsumerStatefulWidget {
  const JamHighlightDetailScreen({
    super.key,
    required this.jamHighlightId,
    required this.content,
    required this.bookTitle,
    required this.bookAuthor,
    required this.sharedBy,
  });

  final String jamHighlightId;
  final String content;
  final String bookTitle;
  final String bookAuthor;
  final String sharedBy;

  @override
  ConsumerState<JamHighlightDetailScreen> createState() =>
      _JamHighlightDetailScreenState();
}

class _JamHighlightDetailScreenState
    extends ConsumerState<JamHighlightDetailScreen> {
  final _commentController = TextEditingController();
  bool _posting = false;
  Uint8List? _imageBytes;
  String? _imageExt;
  String? _gifUrl;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickCommentImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() {
      _imageBytes = result.files.first.bytes;
      _imageExt   = (result.files.first.extension ?? 'jpg').toLowerCase();
      _gifUrl     = null; // image and gif are mutually exclusive attachments
    });
  }

  Future<void> _pickGif() async {
    final url = await showGifPicker(context);
    if (url == null || !mounted) return;
    // Tapping a GIF posts it IMMEDIATELY as a comment — no staging, no text
    // step. Mirror _postComment()'s send path: the Tenor URL rides along on the
    // image_url column and renders through Image.network in _CommentBubble.
    setState(() => _posting = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.addComment(
        widget.jamHighlightId,
        '📷', // jam_highlight_comments requires non-empty content
        imageUrl: url,
      );
      ref.invalidate(commentsProvider(widget.jamHighlightId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleReaction(String emoji) async {
    try {
      await ref
          .read(supabaseServiceProvider)
          .toggleReaction(widget.jamHighlightId, emoji);
      ref.invalidate(reactionsProvider(widget.jamHighlightId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
      );
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _imageBytes == null && _gifUrl == null) return;
    setState(() => _posting = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      // The jam_highlight_comments table only has an image_url column, so the
      // GIF rides along on the same field — the Tenor URL is an external image
      // URL and renders identically through Image.network in _CommentBubble.
      String? imageUrl = _gifUrl;
      if (_imageBytes != null && _imageExt != null) {
        imageUrl = await svc.uploadCommentImage(_imageBytes!, _imageExt!);
      }
      await svc.addComment(
        widget.jamHighlightId,
        text.isEmpty ? '📷' : text,
        imageUrl: imageUrl,
      );
      _commentController.clear();
      setState(() { _imageBytes = null; _imageExt = null; _gifUrl = null; });
      ref.invalidate(commentsProvider(widget.jamHighlightId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reactionsAsync = ref.watch(reactionsProvider(widget.jamHighlightId));
    final commentsAsync = ref.watch(commentsProvider(widget.jamHighlightId));
    final currentUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      // The comment input already pads itself by viewInsets.bottom; letting the
      // Scaffold ALSO resize double-applied the keyboard inset and flung the bar
      // up over the content. Disable the auto-resize.
      resizeToAvoidBottomInset: false,
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.l10n.jamDiscussionTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Citation card ──────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: ScriptaDecorations.card(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.bookTitle.isNotEmpty) ...[
                          Text(widget.bookTitle,
                              style: ScriptaTextStyles.bookTitle),
                          Text(widget.bookAuthor.toUpperCase(),
                              style: ScriptaTextStyles.bookAuthor),
                          const SizedBox(height: 14),
                        ],
                        Text('"', style: ScriptaTextStyles.quoteDecor.copyWith(fontSize: 48, height: 0.4)),
                        const SizedBox(height: 4),
                        Text(widget.content,
                            style: ScriptaTextStyles.highlightBody),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: ScriptaColors.inkMuted),
                            const SizedBox(width: 4),
                            Text(
                              context.l10n.jamSharedBy(widget.sharedBy),
                              style: ScriptaTextStyles.label,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Quick reactions ────────────────────────────────────
                  reactionsAsync.when(
                    data: (reactions) =>
                        _ReactionBar(
                          reactions: reactions,
                          currentUserId: currentUserId,
                          onTap: _toggleReaction,
                        ),
                    loading: () => const SizedBox(height: 56),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 28),

                  // ── Comments header ────────────────────────────────────
                  Row(
                    children: [
                      Text(context.l10n.feedCommentsSection,
                          style: ScriptaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Divider(color: ScriptaColors.rule)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  commentsAsync.when(
                    data: (comments) => comments.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                context.l10n.feedNoComments,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: ScriptaColors.inkMuted,
                                  fontSize: 13,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < comments.length; i++)
                                _CommentBubble(
                                  data: comments[i],
                                  index: i,
                                  isMine: comments[i]['user_id'] ==
                                      currentUserId,
                                  onDelete: () async {
                                    try {
                                      await ref
                                          .read(supabaseServiceProvider)
                                          .deleteComment(
                                              comments[i]['id'] as String);
                                      ref.invalidate(commentsProvider(
                                          widget.jamHighlightId));
                                    } catch (_) {}
                                  },
                                ),
                            ],
                          ),
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          color: ScriptaColors.primaryDark,
                          strokeWidth: 1.5,
                        ),
                      ),
                    ),
                    error: (e, _) => Text(context.l10n.errorPrefix('$e'),
                        style: const TextStyle(color: ScriptaColors.inkMuted)),
                  ),
                ],
              ),
            ),
          ),

          // ── Input commento ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: ScriptaColors.surfaceElevated,
              border: Border(
                top: BorderSide(color: ScriptaColors.rule),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Attachment preview (picked image OR selected GIF)
                if (_imageBytes != null || _gifUrl != null) ...[
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _imageBytes != null
                            ? Image.memory(_imageBytes!,
                                height: 80, width: double.infinity, fit: BoxFit.cover)
                            : Image.network(_gifUrl!,
                                height: 80, width: double.infinity, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _imageBytes = null;
                            _imageExt   = null;
                            _gifUrl     = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(160),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close, size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
              children: [
                // Photo button
                GestureDetector(
                  onTap: _pickCommentImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ScriptaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_outlined, size: 18,
                        color: ScriptaColors.primaryDark),
                  ),
                ),
                const SizedBox(width: 6),
                // GIF button — sends a Tenor GIF on the same image_url field.
                GestureDetector(
                  onTap: _pickGif,
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: ScriptaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text(
                        'GIF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: ScriptaColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: context.l10n.feedCommentHint,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => _posting ? null : _postComment(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _posting ? null : _postComment,
                  icon: _posting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF1EEE7),
                          ),
                        )
                      : const Icon(Icons.arrow_upward, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: ScriptaColors.primary,
                    foregroundColor: const Color(0xFFF1EEE7),
                  ),
                ),
              ],
            ),       // end Row
              ],
            ),       // end Column
          ),         // end Container
        ],
      ),
    );
  }
}

// ─── Reaction bar ─────────────────────────────────────────────────────────────

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactions,
    required this.currentUserId,
    required this.onTap,
  });

  final List<Map<String, dynamic>> reactions;
  final String? currentUserId;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    // Aggregate counts per emoji + whether current user reacted
    final counts = <String, int>{};
    final myReactions = <String>{};
    for (final r in reactions) {
      final emoji = r['emoji'] as String? ?? '';
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (r['user_id'] == currentUserId) myReactions.add(emoji);
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final emoji in _quickReactions)
            _ReactionChip(
              emoji: emoji,
              count: counts[emoji] ?? 0,
              isMine: myReactions.contains(emoji),
              onTap: () => onTap(emoji),
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color:
                isMine ? ScriptaColors.primaryFaint : ScriptaColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isMine ? ScriptaColors.primary : ScriptaColors.rule,
              width: isMine ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isMine
                        ? ScriptaColors.primaryDark
                        : ScriptaColors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Comment bubble ───────────────────────────────────────────────────────────

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.data,
    required this.index,
    required this.isMine,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final int index;
  final bool isMine;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final content  = data['content'] as String? ?? '';
    final imageUrl = data['image_url'] as String?;
    final profile  = data['profiles'] as Map<String, dynamic>?;
    final name     = profile?['display_name'] as String? ?? 'User';
    final createdAt = data['created_at'] as String?;
    final showText = content.isNotEmpty && content != '📷';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: isMine
            ? ScriptaColors.primaryFaint
            : ScriptaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScriptaColors.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ScriptaColors.primaryDark,
                  ),
                ),
              ),
              if (createdAt != null)
                Text(_formatTime(context, createdAt),
                    style: ScriptaTextStyles.label),
              if (isMine)
                GestureDetector(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: ScriptaColors.inkFaint),
                  ),
                ),
            ],
          ),
          if (showText) ...[
            const SizedBox(height: 4),
            Text(content,
                style: const TextStyle(
                  fontSize: 14,
                  color: ScriptaColors.ink,
                  height: 1.45,
                )),
          ],
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            // image_url carries either an uploaded photo OR an external GIF
            // (Tenor) — both render through Image.network. Cap the height so a
            // tall GIF can't blow out the bubble.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.04, end: 0, duration: 250.ms);
  }

  String _formatTime(BuildContext context, String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return context.l10n.timeNow;
      if (diff.inMinutes < 60) return context.l10n.timeMinutesAgo(diff.inMinutes);
      if (diff.inHours < 24) return context.l10n.timeHoursAgo(diff.inHours);
      if (diff.inDays < 7) return context.l10n.timeDaysAgo(diff.inDays);
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}
