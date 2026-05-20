import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final _messagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, conversationId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  return svc.fetchMessages(conversationId);
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.conversationName,
  });

  final String conversationId;
  final String conversationName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _localMessages = [];
  bool _initialScrollDone = false;
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll helpers ───────────────────────────────────────────────────────────

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ── Send message ─────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    final svc = ref.read(supabaseServiceProvider);
    final userId = svc.userId ?? '';

    // Optimistic message
    final optimistic = {
      'id': 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      'sender_id': userId,
      'content': text,
      'image_url': null,
      'created_at': DateTime.now().toIso8601String(),
      'sender': {
        'id': userId,
        'display_name': 'Tu',
        'avatar_url': null,
      },
    };

    setState(() {
      _localMessages.add(optimistic);
      _sending = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      await svc.sendMessage(widget.conversationId, content: text);
      // Refresh messages from server to get confirmed data
      ref.invalidate(_messagesProvider(widget.conversationId));
    } catch (e) {
      // Remove optimistic message on failure
      setState(() {
        _localMessages.removeWhere((m) => m['id'] == optimistic['id']);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nell\'invio: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(_messagesProvider(widget.conversationId));
    final svc = ref.watch(supabaseServiceProvider);
    final currentUserId = svc.userId ?? '';

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: _ChatAppBar(title: widget.conversationName),
      body: Column(
        children: [
          // ── Messages list ──────────────────────────────────────────────
          Expanded(
            child: messagesAsync.when(
              data: (serverMessages) {
                // Merge server messages with local optimistic messages,
                // deduplicate by id (optimistic ones have unique temp ids)
                final optimisticIds =
                    serverMessages.map((m) => m['id']).toSet();
                final merged = [
                  ...serverMessages,
                  ..._localMessages.where(
                      (m) => !optimisticIds.contains(m['id'])),
                ];

                if (!_initialScrollDone && merged.isNotEmpty) {
                  _initialScrollDone = true;
                  _scrollToBottom(animated: false);
                }

                if (merged.isEmpty) {
                  return const _EmptyChatState();
                }

                return RefreshIndicator(
                  color: MarginaliaColors.primary,
                  backgroundColor: MarginaliaColors.surface,
                  onRefresh: () async {
                    ref.invalidate(_messagesProvider(widget.conversationId));
                    await ref.read(
                        _messagesProvider(widget.conversationId).future);
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: merged.length,
                    itemBuilder: (context, index) {
                      final message = merged[index];
                      final senderId = message['sender_id'] as String? ?? '';
                      final isMe = senderId == currentUserId;
                      final isOptimistic =
                          (message['id'] as String).startsWith('optimistic_');
                      final showDateSeparator = index == 0 ||
                          _shouldShowDateSeparator(merged, index);

                      return Column(
                        children: [
                          if (showDateSeparator)
                            _DateSeparator(
                              dateString:
                                  message['created_at'] as String? ?? '',
                            ),
                          _MessageBubble(
                            message: message,
                            isMe: isMe,
                            isOptimistic: isOptimistic,
                            showSender: !isMe && index > 0
                                ? (merged[index - 1]['sender_id'] as String? ??
                                        '') !=
                                    senderId
                                : !isMe,
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna,
                  strokeWidth: 1.5,
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: MarginaliaColors.inkFaint, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'Impossibile caricare i messaggi',
                        style: GoogleFonts.barlow(
                          color: MarginaliaColors.inkMuted,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(
                            _messagesProvider(widget.conversationId)),
                        child: Text(
                          'Riprova',
                          style: GoogleFonts.barlow(
                            color: MarginaliaColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Input bar ─────────────────────────────────────────────────
          _MessageInputBar(
            controller: _textController,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _shouldShowDateSeparator(
      List<Map<String, dynamic>> messages, int index) {
    if (index == 0) return true;
    final prev = DateTime.tryParse(
        messages[index - 1]['created_at'] as String? ?? '');
    final curr =
        DateTime.tryParse(messages[index]['created_at'] as String? ?? '');
    if (prev == null || curr == null) return false;
    final prevLocal = prev.toLocal();
    final currLocal = curr.toLocal();
    return prevLocal.day != currLocal.day ||
        prevLocal.month != currLocal.month ||
        prevLocal.year != currLocal.year;
  }
}

// ─── Chat AppBar ─────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: MarginaliaColors.primary,
      foregroundColor: const Color(0xFFF1EEE7),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: Color(0xFFF1EEE7)),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        title,
        style: GoogleFonts.ebGaramond(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFF1EEE7),
          letterSpacing: -0.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isOptimistic,
    required this.showSender,
  });

  final Map<String, dynamic> message;
  final bool isMe;
  final bool isOptimistic;
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final content = message['content'] as String?;
    final imageUrl = message['image_url'] as String?;
    final sender = message['sender'] as Map<String, dynamic>? ?? {};
    final senderName = sender['display_name'] as String? ?? 'Utente';
    final senderAvatar = sender['avatar_url'] as String?;
    final createdAt = message['created_at'] as String?;
    final timeLabel = _formatTime(DateTime.tryParse(createdAt ?? ''));

    final senderInitial =
        senderName.isNotEmpty ? senderName[0].toUpperCase() : '?';
    final avatarBg = MarginaliaDecorations.bookCoverColor(senderName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (only for others)
          if (!isMe) ...[
            SizedBox(
              width: 32,
              child: showSender
                  ? _SmallAvatar(
                      avatarUrl: senderAvatar,
                      initial: senderInitial,
                      color: avatarBg,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
          ],

          // Bubble
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && showSender) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      senderName,
                      style: GoogleFonts.barlow(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.inkFaint,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
                _BubbleContainer(
                  isMe: isMe,
                  isOptimistic: isOptimistic,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            width: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 220,
                              height: 140,
                              color: MarginaliaColors.surfaceElevated,
                              child: const Icon(Icons.image_not_supported_outlined,
                                  color: MarginaliaColors.inkFaint),
                            ),
                          ),
                        ),
                      if (content != null && content.isNotEmpty)
                        Text(
                          content,
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            color: isMe ? Colors.white : MarginaliaColors.ink,
                            height: 1.45,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeLabel,
                      style: GoogleFonts.barlow(
                        fontSize: 10,
                        color: MarginaliaColors.inkFaint,
                      ),
                    ),
                    if (isOptimistic) ...[
                      const SizedBox(width: 4),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Spacer for my messages
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _BubbleContainer extends StatelessWidget {
  const _BubbleContainer({
    required this.isMe,
    required this.isOptimistic,
    required this.child,
  });

  final bool isMe;
  final bool isOptimistic;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.68,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? (isOptimistic
                ? MarginaliaColors.primary.withAlpha(180)
                : MarginaliaColors.primary)
            : MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
          bottomRight:
              isMe ? const Radius.circular(4) : const Radius.circular(18),
        ),
        border: isMe
            ? null
            : Border.all(color: MarginaliaColors.rule, width: 0.5),
      ),
      child: child,
    );
  }
}

// ─── Small Avatar (for chat) ─────────────────────────────────────────────────

class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.color,
  });

  final String? avatarUrl;
  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.ebGaramond(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initial,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Date Separator ──────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.dateString});

  final String dateString;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(dateString)?.toLocal();
    if (dt == null) return const SizedBox.shrink();

    final now = DateTime.now();
    String label;
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      label = 'Oggi';
    } else if (diff.inDays == 1) {
      label = 'Ieri';
    } else if (diff.inDays < 7) {
      const days = [
        'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì',
        'Venerdì', 'Sabato', 'Domenica'
      ];
      label = days[dt.weekday - 1];
    } else {
      label = '${dt.day}/${dt.month}/${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              color: MarginaliaColors.rule,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: GoogleFonts.barlow(
                fontSize: 11,
                color: MarginaliaColors.inkFaint,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              color: MarginaliaColors.rule,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty Chat State ─────────────────────────────────────────────────────────

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: MarginaliaColors.sienna,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Nessun messaggio',
              style: GoogleFonts.ebGaramond(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inizia la conversazione\nscrivendo il primo messaggio.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: MarginaliaColors.inkMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ─── Message Input Bar ────────────────────────────────────────────────────────

class _MessageInputBar extends StatelessWidget {
  const _MessageInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        border: const Border(
          top: BorderSide(color: MarginaliaColors.rule, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        bottomInset > 0 ? bottomInset + 10 : bottomPadding + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text field
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.barlow(
                fontSize: 15,
                color: MarginaliaColors.ink,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Scrivi un messaggio…',
                hintStyle: GoogleFonts.barlow(
                  color: MarginaliaColors.inkFaint,
                  fontSize: 15,
                ),
                filled: true,
                fillColor: MarginaliaColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: MarginaliaColors.rule, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: MarginaliaColors.rule, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: MarginaliaColors.primary, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: sending
                    ? MarginaliaColors.primary.withAlpha(150)
                    : MarginaliaColors.primary,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
