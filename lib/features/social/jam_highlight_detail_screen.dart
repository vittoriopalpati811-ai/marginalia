import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

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
    });
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
        SnackBar(content: Text('Errore reazione: $e')),
      );
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _imageBytes == null) return;
    setState(() => _posting = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      String? imageUrl;
      if (_imageBytes != null && _imageExt != null) {
        imageUrl = await svc.uploadCommentImage(_imageBytes!, _imageExt!);
      }
      await svc.addComment(
        widget.jamHighlightId,
        text.isEmpty ? '📷' : text,
        imageUrl: imageUrl,
      );
      _commentController.clear();
      setState(() { _imageBytes = null; _imageExt = null; });
      ref.invalidate(commentsProvider(widget.jamHighlightId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore commento: $e')),
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
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Discussione',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                    decoration: MarginaliaDecorations.card(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.bookTitle.isNotEmpty) ...[
                          Text(widget.bookTitle,
                              style: MarginaliaTextStyles.bookTitle),
                          Text(widget.bookAuthor.toUpperCase(),
                              style: MarginaliaTextStyles.bookAuthor),
                          const SizedBox(height: 14),
                        ],
                        Text('"', style: MarginaliaTextStyles.quoteDecor.copyWith(fontSize: 48, height: 0.4)),
                        const SizedBox(height: 4),
                        Text(widget.content,
                            style: MarginaliaTextStyles.highlightBody),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: MarginaliaColors.inkMuted),
                            const SizedBox(width: 4),
                            Text(
                              'Condiviso da ${widget.sharedBy}',
                              style: MarginaliaTextStyles.label,
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
                      Text('COMMENTI',
                          style: MarginaliaTextStyles.sectionTitle),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Divider(color: MarginaliaColors.rule)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  commentsAsync.when(
                    data: (comments) => comments.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Nessun commento ancora.\nSii il primo a rispondere.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: MarginaliaColors.inkMuted,
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
                          color: MarginaliaColors.primary,
                          strokeWidth: 1.5,
                        ),
                      ),
                    ),
                    error: (e, _) => Text('Errore caricamento: $e',
                        style: const TextStyle(color: MarginaliaColors.inkMuted)),
                  ),
                ],
              ),
            ),
          ),

          // ── Input commento ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: MarginaliaColors.surfaceElevated,
              border: Border(
                top: BorderSide(color: MarginaliaColors.rule),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, MediaQuery.of(context).viewInsets.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image preview
                if (_imageBytes != null) ...[
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_imageBytes!,
                            height: 80, width: double.infinity, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() { _imageBytes = null; _imageExt = null; }),
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
                      color: MarginaliaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_outlined, size: 18,
                        color: MarginaliaColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Scrivi un commento…',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    backgroundColor: MarginaliaColors.primary,
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
                isMine ? MarginaliaColors.primaryFaint : MarginaliaColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isMine ? MarginaliaColors.primary : MarginaliaColors.rule,
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
                        ? MarginaliaColors.primary
                        : MarginaliaColors.inkMuted,
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
    final name     = profile?['display_name'] as String? ?? 'Utente';
    final createdAt = data['created_at'] as String?;
    final showText = content.isNotEmpty && content != '📷';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: isMine
            ? MarginaliaColors.primaryFaint
            : MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarginaliaColors.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isMine
                        ? MarginaliaColors.primary
                        : MarginaliaColors.sienna,
                  ),
                ),
              ),
              if (createdAt != null)
                Text(_formatTime(createdAt),
                    style: MarginaliaTextStyles.label),
              if (isMine)
                GestureDetector(
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: MarginaliaColors.inkFaint),
                  ),
                ),
            ],
          ),
          if (showText) ...[
            const SizedBox(height: 4),
            Text(content,
                style: const TextStyle(
                  fontSize: 14,
                  color: MarginaliaColors.ink,
                  height: 1.45,
                )),
          ],
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'adesso';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}g';
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}
