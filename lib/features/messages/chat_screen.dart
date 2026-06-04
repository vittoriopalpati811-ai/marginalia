import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/unread_messages_provider.dart';
import 'giphy_picker.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _messagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, conversationId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  return svc.fetchMessages(conversationId);
});

/// Header metadata for the open chat: whether it's a group, the group name /
/// avatar, and (for 1:1) the OTHER member's id + display name + avatar.
///
/// The chat is opened with only a conversationId (see app.dart `/chat/:id`),
/// so the screen has to resolve the title itself instead of trusting the
/// passed-in `conversationName`, which is just a placeholder. Reads the
/// `conversations` row directly and the member profiles via the existing
/// `get_conversation_member_profiles` SECURITY DEFINER RPC (the same one
/// fetchConversations uses), so no new service method is required.
final _chatHeaderProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, conversationId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return null;
  final myId = svc.userId ?? '';

  final convRows = await svc.client
      .from('conversations')
      .select('id, is_group, group_name, group_avatar_url')
      .eq('id', conversationId)
      .limit(1);
  if ((convRows as List).isEmpty) return null;
  final conv = Map<String, dynamic>.from(convRows.first as Map);

  final profiles = List<Map<String, dynamic>>.from(
    await svc.client.rpc('get_conversation_member_profiles',
        params: {'p_conversation_id': conversationId}) as List,
  );
  // Exclude myself so `others` holds the people I'm talking to.
  final others = profiles.where((p) => p['id'] != myId).toList();

  return {
    'is_group': conv['is_group'] == true,
    'group_name': conv['group_name'] as String?,
    'group_avatar_url': conv['group_avatar_url'] as String?,
    'others': others,
  };
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
  // Per-sender profile cache: the realtime callback fires once per incoming
  // message, so without this every message from the same person re-queried
  // `profiles`. Fetched once per sender per session, then reused.
  final Map<String, Map<String, dynamic>?> _senderProfileCache = {};

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

            // Fetch sender profile to display name/avatar — cached per sender
            // so repeat messages from the same person don't re-query profiles.
            final senderId = row['sender_id'] as String?;
            Map<String, dynamic>? senderProfile;
            if (senderId != null) {
              if (_senderProfileCache.containsKey(senderId)) {
                senderProfile = _senderProfileCache[senderId];
              } else {
                try {
                  final profiles = await svc.client
                      .from('profiles')
                      .select('id, display_name, avatar_url')
                      .eq('id', senderId)
                      .limit(1);
                  if ((profiles as List).isNotEmpty) {
                    senderProfile =
                        Map<String, dynamic>.from(profiles.first as Map);
                  }
                } catch (_) {}
                _senderProfileCache[senderId] = senderProfile;
              }
            }

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
    void run() {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    // Jump after this frame, then re-pin (non-animated) as late-loading
    // content — images, wrapped text — grows the list. Without the follow-up
    // the first jump lands mid-chat because maxScrollExtent was still growing,
    // so opening a chat didn't reliably show the most recent message.
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
            content: Text(context.l10n.errorPrefix('$e')),
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
          SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
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
          SnackBar(content: Text(context.l10n.errorPrefix('$e'))),
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
      appBar: _ChatAppBar(
        conversationId: widget.conversationId,
        fallbackTitle: widget.conversationName,
      ),
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
                    // Dragging the history up means the user is done typing —
                    // drop the keyboard so the whole conversation is visible.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                        context.l10n.chatUnableToLoad,
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
                          context.l10n.retry,
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

class _ChatAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _ChatAppBar({
    required this.conversationId,
    required this.fallbackTitle,
  });

  final String conversationId;

  /// Shown only until the real header (group name / other user) resolves.
  final String fallbackTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  static const _ink = Color(0xFFF1EEE7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headerAsync = ref.watch(_chatHeaderProvider(conversationId));
    final header = headerAsync.asData?.value;

    final isGroup = header?['is_group'] == true;
    final others =
        (header?['others'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final other = others.isNotEmpty ? others.first : null;

    // Resolve the title: group name for groups, the OTHER member's name for
    // 1:1. Fall back to the passed-in name while loading, then to localized
    // placeholders (group / deleted account) so the bar is never blank.
    String title = fallbackTitle;
    String? avatarUrl;
    String? otherUserId;

    if (header != null) {
      if (isGroup) {
        final name = (header['group_name'] as String?)?.trim();
        title = (name != null && name.isNotEmpty)
            ? name
            : context.l10n.msgGroupFallback;
        avatarUrl = header['group_avatar_url'] as String?;
      } else {
        final rawName = (other?['display_name'] as String?)?.trim();
        title = (rawName != null && rawName.isNotEmpty)
            ? rawName
            : context.l10n.accountDeleted;
        avatarUrl = other?['avatar_url'] as String?;
        otherUserId = other?['id'] as String?;
      }
    }

    final initial =
        title.isNotEmpty ? title[0].toUpperCase() : '?';
    final avatarColor = MarginaliaDecorations.bookCoverColor(title);

    // Tapping the title renames the group (groups only). 1:1 titles aren't
    // editable — they're the other person's name.
    final titleWidget = Text(
      title,
      style: GoogleFonts.ebGaramond(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _ink,
        letterSpacing: -0.2,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return AppBar(
      backgroundColor: MarginaliaColors.primary,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: _ink),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          // Header avatar — tapping a 1:1 avatar opens the other user's
          // profile (groups have no single profile to open).
          GestureDetector(
            onTap: otherUserId != null
                ? () => context.push('/user/$otherUserId')
                : null,
            child: _ChatHeaderAvatar(
              avatarUrl: avatarUrl,
              initial: initial,
              color: avatarColor,
              isGroup: isGroup,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isGroup
                ? GestureDetector(
                    onTap: () => _renameGroup(context, ref, title),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Flexible(child: titleWidget),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_outlined,
                            size: 15, color: Color(0xAAF1EEE7)),
                      ],
                    ),
                  )
                : titleWidget,
          ),
        ],
      ),
    );
  }

  // ── Rename group (any member) ──────────────────────────────────────────────
  //
  // Mirrors the Jam-rename dialog in jam_detail_screen.dart. There is no
  // dedicated service method for conversation renames (only `updateJamTitle`
  // exists for jams), so this writes `group_name` directly. The
  // `conversations_update` RLS policy (migration 014) permits any member of
  // the conversation to update the row, so this succeeds without a SECURITY
  // DEFINER RPC. See report: a `SupabaseService.updateGroupName` wrapper would
  // be the cleaner home for this query.
  Future<void> _renameGroup(
      BuildContext context, WidgetRef ref, String currentTitle) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final controller = TextEditingController(text: currentTitle);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          l10n.msgGroupFallback,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogCtx, value),
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    controller.dispose();

    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == currentTitle) return;

    try {
      final svc = ref.read(supabaseServiceProvider);
      await svc.client
          .from('conversations')
          .update({'group_name': trimmed}).eq('id', conversationId);
      // Refresh the header here and the inbox tile on the messages list.
      ref.invalidate(_chatHeaderProvider(conversationId));
      ref.invalidate(conversationsProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix('$e'))),
      );
    }
  }
}

// ─── Chat Header Avatar ───────────────────────────────────────────────────────

class _ChatHeaderAvatar extends StatelessWidget {
  const _ChatHeaderAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.color,
    required this.isGroup,
  });

  final String? avatarUrl;
  final String initial;
  final Color color;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    Widget fallback() => Center(
          child: isGroup
              ? const Icon(Icons.group_rounded, size: 18, color: Colors.white)
              : Text(
                  initial,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
        );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback(),
              )
            : fallback(),
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
    final senderId   = message['sender_id'] as String?;
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
          // Avatar (only for others) — tapping it opens the sender's profile.
          // Skipped for tombstoned (deleted) senders, whose profile is gone.
          if (!isMe) ...[
            SizedBox(
              width: 32,
              child: showSender
                  ? GestureDetector(
                      onTap: (!isDeleted &&
                              senderId != null &&
                              senderId.isNotEmpty)
                          ? () => context.push('/user/$senderId')
                          : null,
                      child: _SmallAvatar(
                        avatarUrl: senderAvatar,
                        initial: senderInitial,
                        color: avatarBg,
                      ),
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
      label = context.l10n.chatDateToday;
    } else if (diff.inDays == 1) {
      label = context.l10n.chatDateYesterday;
    } else if (diff.inDays < 7) {
      // Locale-aware full weekday name ("Monday" / "Lunedì") via intl.
      final locale = Localizations.localeOf(context).toLanguageTag();
      label = DateFormat.EEEE(locale).format(dt);
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
              context.l10n.msgNoMessages,
              style: GoogleFonts.ebGaramond(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chatEmptyBody,
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
                    ? context.l10n.loading
                    : context.l10n.messagesInputHint,
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
      behavior: HitTestBehavior.opaque,
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

