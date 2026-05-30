import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/unread_messages_provider.dart';
import 'giphy_picker.dart';

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

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _localMessages = [];
  bool _initialScrollDone = false;
  bool _sending = false;
  bool _uploadingMedia = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _subscribeRealtime();
      // Record an optimistic local "read" instant FIRST, so the nav badge
      // + bold "unread" styling clear the moment the chat opens — even if
      // the markConversationRead RPC is slow or unavailable (e.g. the
      // mark_conversation_read migration is not yet applied on the backend).
      // This was the reported symptom: a viewed message still showed as
      // "da visualizzare".
      ref.read(locallyReadProvider.notifier).markRead(widget.conversationId);
      // Mark messages as read AND invalidate the inbox so the nav badge
      // + bold "unread" styling on the conversation tile disappear
      // immediately. Without the invalidate, the server-side last_read_at
      // updates but the cached inbox state lags until the next pull-to-
      // refresh — the user reported having to swipe down to clear the
      // red dot.
      await ref
          .read(supabaseServiceProvider)
          .markConversationRead(widget.conversationId);
      if (!mounted) return;
      ref.invalidate(conversationsProvider);
    });
  }

  void _subscribeRealtime() {
    final svc = ref.read(supabaseServiceProvider);
    final myId = svc.userId ?? '';

    _realtimeChannel = svc.client
        .channel('messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            // Skip messages we sent ourselves (already in _localMessages as
            // optimistic, then replaced by the server refresh in _send)
            if ((row['sender_id'] as String?) == myId) return;

            // Fetch sender profile to display name/avatar
            Map<String, dynamic>? senderProfile;
            try {
              final profiles = await svc.client
                  .from('profiles')
                  .select('id, display_name, avatar_url')
                  .eq('id', row['sender_id'] as String)
                  .limit(1);
              if ((profiles as List).isNotEmpty) {
                senderProfile = Map<String, dynamic>.from(profiles.first as Map);
              }
            } catch (_) {}

            final incoming = {
              ...row,
              'sender': senderProfile,
            };

            if (mounted) {
              setState(() => _localMessages.add(incoming));
              _scrollToBottom();
              // The user is actively reading this chat, so mark the
              // message as read immediately and refresh the inbox.
              // Without this, the nav badge lights up for a message
              // already on screen, until they leave and re-enter.
              // The optimistic local timestamp keeps the conversation
              // looking read even if the RPC round-trip lags.
              ref
                  .read(locallyReadProvider.notifier)
                  .markRead(widget.conversationId);
              svc.markConversationRead(widget.conversationId).then((_) {
                if (mounted) ref.invalidate(conversationsProvider);
              });
            }
          },
        )
        .subscribe();
  }

  // When the keyboard opens, the viewport shrinks; snap to the latest message
  // so the newest bubbles aren't left hidden behind the keyboard (the user had
  // to scroll down manually otherwise).
  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final keyboardOpen = views.isNotEmpty && views.first.viewInsets.bottom > 0;
    if (keyboardOpen) _scrollToBottom();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeChannel?.unsubscribe();
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
      // Remove optimistic message now that the real one is saved
      setState(() {
        _localMessages.removeWhere((m) => m['id'] == optimistic['id']);
      });
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
            content: Text('Send error: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Pick image from gallery ────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploadingMedia = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      final ext = file.extension ?? 'jpg';
      final url = await svc.uploadMessageImage('img.$ext', file.bytes!);
      await svc.sendMessage(widget.conversationId, imageUrl: url);
      ref.invalidate(_messagesProvider(widget.conversationId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  // ── Pick GIF via GIPHY ─────────────────────────────────────────────────────

  Future<void> _pickGif() async {
    final url = await showGifPicker(context);
    if (url == null || url.isEmpty) return;

    setState(() => _uploadingMedia = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.sendMessage(widget.conversationId, imageUrl: url);
      ref.invalidate(_messagesProvider(widget.conversationId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GIF send error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
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
              skipLoadingOnRefresh: true,
              data: (serverMessages) {
                // Server IDs (real UUIDs)
                final serverIds = serverMessages.map((m) => m['id']).toSet();
                // Keep only truly pending local messages not yet confirmed by server:
                // - optimistic messages (id starts with 'optimistic_') still in flight
                // - realtime-received messages NOT yet in server snapshot are already
                //   filtered out because they'll appear in the next server fetch
                final pendingLocal = _localMessages
                    .where((m) =>
                        (m['id'] as String).startsWith('optimistic_') &&
                        !serverIds.contains(m['id']))
                    .toList();
                final merged = [...serverMessages, ...pendingLocal];

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
                        'Unable to load messages',
                        style: GoogleFonts.manrope(
                          color: MarginaliaColors.inkMuted,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(
                            _messagesProvider(widget.conversationId)),
                        child: Text(
                          'Retry',
                          style: GoogleFonts.manrope(
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
            uploadingMedia: _uploadingMedia,
            onSend: _send,
            onPickImage: _pickImage,
            onPickGif: _pickGif,
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
    final content    = message['content']   as String?;
    final imageUrl   = message['image_url'] as String?;
    final sender     = message['sender']    as Map<String, dynamic>? ?? {};
    // Tombstone detection: when a profile is soft-deleted via
    // delete_my_account() the display_name is nulled, leaving the row in
    // place so chat history still resolves. We surface "Account eliminato"
    // and a blank avatar instead of the literal "User" placeholder.
    final isDeleted    = (sender['display_name'] as String?)?.isEmpty ?? true;
    final senderName   = isDeleted
        ? context.l10n.accountDeleted
        : sender['display_name'] as String;
    final senderAvatar = isDeleted ? null : sender['avatar_url'] as String?;
    final createdAt    = message['created_at'] as String?;
    final timeLabel    = _formatTime(DateTime.tryParse(createdAt ?? ''));

    final senderInitial =
        isDeleted ? '·' : senderName[0].toUpperCase();
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
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.inkFaint,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
                // Images and GIFs render WITHOUT the coloured bubble so the
                // chat feels lighter and the media stands on its own (the
                // bubble border read as visual clutter around imagery).
                // Text still gets the bubble — and when a message carries
                // both, the text bubble sits below the standalone image.
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: (content != null && content.isNotEmpty) ? 6 : 0),
                    child: Opacity(
                      opacity: isOptimistic ? 0.7 : 1.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
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
                    ),
                  ),
                if (content != null && content.isNotEmpty)
                  _BubbleContainer(
                    isMe: isMe,
                    isOptimistic: isOptimistic,
                    child: Text(
                      content,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: isMe ? Colors.white : MarginaliaColors.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeLabel,
                      style: GoogleFonts.manrope(
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
      label = 'Today';
    } else if (diff.inDays == 1) {
      label = 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'
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
              style: GoogleFonts.manrope(
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
              'No messages',
              style: GoogleFonts.ebGaramond(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation\nby sending the first message.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
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
    required this.uploadingMedia,
    required this.onSend,
    required this.onPickImage,
    required this.onPickGif,
  });

  final TextEditingController controller;
  final bool sending;
  final bool uploadingMedia;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onPickGif;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final busy = sending || uploadingMedia;

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        border: Border(
          top: BorderSide(color: MarginaliaColors.rule, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        bottomInset > 0 ? bottomInset + 8 : bottomPadding + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Image picker
          _MediaButton(
            icon: Icons.image_outlined,
            onTap: busy ? null : onPickImage,
          ),
          // GIF picker
          _MediaButton(
            icon: Icons.gif_box_outlined,
            onTap: busy ? null : onPickGif,
          ),
          const SizedBox(width: 4),

          // Text field
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: MarginaliaColors.ink,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: uploadingMedia
                    ? 'Loading…'
                    : 'Write a message…',
                hintStyle: GoogleFonts.manrope(
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
            onTap: busy ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: busy
                    ? MarginaliaColors.primary.withAlpha(130)
                    : MarginaliaColors.primary,
                shape: BoxShape.circle,
              ),
              child: busy
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

class _MediaButton extends StatelessWidget {
  const _MediaButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 24,
          color: onTap != null
              ? MarginaliaColors.inkMuted
              : MarginaliaColors.inkFaint,
        ),
      ),
    );
  }
}

