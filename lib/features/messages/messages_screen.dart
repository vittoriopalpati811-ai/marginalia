import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/unread_messages_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// conversationsProvider lives in core/providers/unread_messages_provider.dart
// so it can be shared with the bottom-nav unread badge.

// ─── Screen ───────────────────────────────────────────────────────────────────

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      // FAB sits at the standard position — no extra bottom padding now
      // that the bottom nav is a flat bar (was 96px for the old floating
      // glass pill, which pushed the FAB into the middle of the screen).
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewConversationSheet,
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
      body: Column(
        children: [
          // ── Gradient header ──────────────────────────────────────────────
          _MessagesHeader(),

          // ── Conversation list ────────────────────────────────────────────
          Expanded(
            child: conversationsAsync.when(
              data: (conversations) {
                if (conversations.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  color: MarginaliaColors.primary,
                  backgroundColor: MarginaliaColors.surface,
                  onRefresh: () async {
                    ref.invalidate(conversationsProvider);
                    await ref.read(conversationsProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      return _ConversationCard(
                        conversation: conv,
                        index: index,
                        onTap: () => context.push('/chat/${conv['id']}'),
                      ).animate(delay: (index * 40).ms)
                          .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                          .slideY(begin: 0.04, end: 0, duration: 300.ms);
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
                        context.l10n.msgErrorLoading,
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(conversationsProvider),
                        child: Text(
                          context.l10n.retry,
                          style: GoogleFonts.manrope(
                            color: MarginaliaColors.primaryDark,
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
        ],
      ),
    );
  }

  // ── Sheets ──────────────────────────────────────────────────────────────────

  void _showNewConversationSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NewConversationSheet(
        onConversationCreated: (id) {
          // Dismiss whichever bottom sheet is currently on top (this may be the
          // nested user-search / create-group sheet, NOT the original one — the
          // first sheet was already popped when the user chose an option). Pop
          // the active modal route via the screen navigator so the chat doesn't
          // open on top of a still-visible sheet that then lingers behind it.
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
          context.push('/chat/$id');
          ref.invalidate(conversationsProvider);
        },
      ),
    );
  }
}

// ─── Gradient Header ─────────────────────────────────────────────────────────

class _MessagesHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    // No colored bar: icons float over the normal page background, with the
    // global (dark) status-bar icons that are correct over the cream content.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topPadding > 0 ? 4 : 16, 20, 20),
        // Row layout: [bell] [Expanded centered title] [equal-width spacer].
        // The trailing spacer matches the bell's footprint so the title column
        // is mathematically centered between them and can never overlap the
        // bell, no matter how long the localized title is.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top-left bell → notifications ───────────────────────────────
            GestureDetector(
              onTap: () => context.push('/notifications'),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MarginaliaColors.ink.withAlpha(12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  PhosphorIconsRegular.bell,
                  color: MarginaliaColors.ink,
                  size: 18,
                ),
              ),
            ),

            // ── Centered title + subtitle ───────────────────────────────────
            Expanded(
              child: Padding(
                // Clears the bell on both sides while staying centered.
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      context.l10n.messagesTitle,
                      textAlign: TextAlign.center,
                      style: MarginaliaTextStyles.wordmark,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.msgSubtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        color: MarginaliaColors.inkMuted,
                        fontSize: 12,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Equal-width spacer balancing the bell (18px icon + 8+8 pad) ──
            const SizedBox(width: 34),
          ],
        ),
      ),
    );
  }
}

// ─── Conversation Card ───────────────────────────────────────────────────────

class _ConversationCard extends ConsumerWidget {
  const _ConversationCard({
    required this.conversation,
    required this.index,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGroup = conversation['is_group'] == true;
    final members =
        (conversation['members'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final lastMessage = conversation['last_message'] as Map<String, dynamic>?;
    final myLastReadAt = conversation['my_last_read_at'] as String?;
    final currentUserId = conversation['current_user_id'] as String? ?? '';

    // Derive display name and avatar
    String displayName;
    String? avatarUrl;

    if (isGroup) {
      displayName = conversation['group_name'] as String? ?? context.l10n.msgGroupFallback;
      avatarUrl = conversation['group_avatar_url'] as String?;
    } else {
      final otherMember = members.isNotEmpty ? members.first : null;
      // display_name == null/empty means the other person soft-deleted
      // their account. Surface a clear tombstone label.
      final rawName = otherMember?['display_name'] as String?;
      if (rawName == null || rawName.isEmpty) {
        displayName = context.l10n.accountDeleted;
        avatarUrl   = null;
      } else {
        displayName = rawName;
        avatarUrl   = otherMember?['avatar_url'] as String?;
      }
    }

    // Unread = last message exists, NOT sent by me, newer than my effective
    // read time. The effective read time is the LATEST of the server's
    // persisted my_last_read_at and any optimistic local read recorded this
    // session (set the instant the chat opens — see locallyReadProvider).
    // This clears the bold "unread" styling immediately after viewing, even
    // if the mark_conversation_read RPC lags or is unavailable.
    final localRead = ref.watch(locallyReadProvider)[conversation['id']];
    bool hasUnread = false;
    if (lastMessage != null) {
      final senderId = lastMessage['sender_id'] as String? ?? '';
      if (senderId != currentUserId) {
        final lastMsgTime =
            DateTime.tryParse(lastMessage['created_at'] as String? ?? '');
        final serverRead =
            myLastReadAt != null ? DateTime.tryParse(myLastReadAt) : null;
        final effectiveRead = serverRead == null
            ? localRead
            : (localRead == null
                ? serverRead
                : (localRead.isAfter(serverRead) ? localRead : serverRead));
        if (effectiveRead == null) {
          hasUnread = true;
        } else if (lastMsgTime != null) {
          hasUnread = lastMsgTime.isAfter(effectiveRead);
        }
      }
    }

    // Last message preview
    String lastPreview = context.l10n.msgNoMessages;
    String timeLabel = '';

    if (lastMessage != null) {
      final content = lastMessage['content'] as String?;
      final imageUrl = lastMessage['image_url'] as String?;
      if (content != null && content.isNotEmpty) {
        lastPreview = content;
      } else if (imageUrl != null) {
        lastPreview = context.l10n.msgPhoto;
      }

      final createdAt = lastMessage['created_at'] as String?;
      if (createdAt != null) {
        timeLabel = _formatTime(context, DateTime.tryParse(createdAt));
      }
    }

    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final avatarBg = MarginaliaDecorations.bookCoverColor(displayName);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.rule, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              _Avatar(
                avatarUrl: avatarUrl,
                initial: initial,
                color: avatarBg,
                size: 48,
                isGroup: isGroup,
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.ink,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: MarginaliaColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: hasUnread
                                  ? MarginaliaColors.ink
                                  : MarginaliaColors.inkMuted,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: MarginaliaColors.sienna,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isGroup && members.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.msgParticipantCount(members.length),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: MarginaliaColors.inkFaint,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: MarginaliaColors.inkFaint,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime? dt) {
    if (dt == null) return '';
    final l10n = context.l10n;
    final now = DateTime.now();
    final diff = now.difference(dt.toLocal());
    if (diff.inMinutes < 1) return l10n.timeNow;
    if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
    return '${dt.day}/${dt.month}';
  }
}

// ─── Avatar widget ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.initial,
    required this.color,
    required this.size,
    this.isGroup = false,
  });

  final String? avatarUrl;
  final String initial;
  final Color color;
  final double size;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialFallback(
                  initial: initial,
                  isGroup: isGroup,
                  size: size,
                ),
              )
            : _InitialFallback(
                initial: initial,
                isGroup: isGroup,
                size: size,
              ),
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({
    required this.initial,
    required this.isGroup,
    required this.size,
  });

  final String initial;
  final bool isGroup;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return Center(
        child: Icon(Icons.group_outlined,
            color: Colors.white.withAlpha(220), size: size * 0.45),
      );
    }
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.ebGaramond(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.send_outlined,
                size: 36,
                color: MarginaliaColors.sienna,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.messagesNoConversations,
              style: GoogleFonts.ebGaramond(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.msgEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
  }
}

// ─── New Conversation Sheet ───────────────────────────────────────────────────

class _NewConversationSheet extends StatelessWidget {
  const _NewConversationSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                context.l10n.msgNewConversation,
                style: GoogleFonts.ebGaramond(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.ink,
                ),
              ),
              const SizedBox(height: 24),

              // Direct message option
              _SheetOption(
                icon: Icons.person_outline,
                title: context.l10n.msgDirectMessage,
                subtitle: context.l10n.msgDirectMessageSubtitle,
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => _UserSearchSheet(
                      onConversationCreated: onConversationCreated,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // Group option
              _SheetOption(
                icon: Icons.group_outlined,
                title: context.l10n.msgCreateGroup,
                subtitle: context.l10n.msgCreateGroupSubtitle,
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => _CreateGroupSheet(
                      onConversationCreated: onConversationCreated,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.rule, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: MarginaliaColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MarginaliaColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: MarginaliaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: MarginaliaColors.inkFaint, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── User Search Sheet (direct message) ──────────────────────────────────────

class _UserSearchSheet extends ConsumerStatefulWidget {
  const _UserSearchSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  ConsumerState<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends ConsumerState<_UserSearchSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(supabaseServiceProvider);
      final results = await svc.searchUsers(query.trim());
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = l10n.msgSearchError;
        _loading = false;
      });
    }
  }

  Future<void> _startConversation(String userId) async {
    final l10n = context.l10n;
    try {
      final svc = ref.read(supabaseServiceProvider);
      final id = await svc.createOrFetchDirectConversation(userId);
      widget.onConversationCreated(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard-aware height: a modal bottom sheet does NOT resize for the
    // keyboard, so subtract the keyboard inset from the fixed height. This keeps
    // the whole sheet — the autofocus search field at the top AND the scrollable
    // results below it — above the keyboard instead of letting the keyboard
    // overlap (and cover) the lower half of the sheet.
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = (screenHeight * 0.75) - viewInsetsBottom;
    return Container(
      height: sheetHeight > 0 ? sheetHeight : screenHeight * 0.75,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MarginaliaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.msgDirectMessage,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _search,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.msgSearchUsersHint,
                    prefixIcon: const Icon(Icons.search_outlined, size: 20),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: MarginaliaColors.sienna,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // Results
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: GoogleFonts.manrope(color: MarginaliaColors.inkMuted),
                    ),
                  )
                : _results.isEmpty && _searchController.text.isNotEmpty && !_loading
                    ? Center(
                        child: Text(
                          context.l10n.msgNoUsersFound,
                          style: GoogleFonts.manrope(
                            color: MarginaliaColors.inkFaint,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          final name =
                              user['display_name'] as String? ?? context.l10n.msgUserFallback;
                          final username = user['username'] as String? ?? '';
                          final avatarUrl = user['avatar_url'] as String?;
                          final userId = user['id'] as String? ?? '';
                          final initial =
                              name.isNotEmpty ? name[0].toUpperCase() : '?';
                          final avatarBg =
                              MarginaliaDecorations.bookCoverColor(name);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: _Avatar(
                              avatarUrl: avatarUrl,
                              initial: initial,
                              color: avatarBg,
                              size: 42,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.ink,
                              ),
                            ),
                            subtitle: username.isNotEmpty
                                ? Text(
                                    '@$username',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      color: MarginaliaColors.inkFaint,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right,
                                color: MarginaliaColors.inkFaint, size: 18),
                            onTap: () => _startConversation(userId),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Create Group Sheet ───────────────────────────────────────────────────────

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _selectedUsers = [];
  bool _searchLoading = false;
  bool _creating = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      final results = await svc.searchUsers(query.trim());
      setState(() {
        _searchResults = results
            .where((u) => !_selectedUsers.any((s) => s['id'] == u['id']))
            .toList();
        _searchLoading = false;
      });
    } catch (_) {
      setState(() => _searchLoading = false);
    }
  }

  void _toggleUser(Map<String, dynamic> user) {
    setState(() {
      final exists = _selectedUsers.any((u) => u['id'] == user['id']);
      if (exists) {
        _selectedUsers.removeWhere((u) => u['id'] == user['id']);
      } else {
        _selectedUsers.add(user);
      }
      _searchResults = _searchResults
          .where((u) => !_selectedUsers.any((s) => s['id'] == u['id']))
          .toList();
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.messagesEnterGroupName)),
      );
      return;
    }
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.messagesAddParticipant)),
      );
      return;
    }
    final l10n = context.l10n;
    setState(() => _creating = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      final memberIds =
          _selectedUsers.map((u) => u['id'] as String).toList();
      final id = await svc.createGroupConversation(
        memberIds,
        groupName: name,
      );
      widget.onConversationCreated(id);
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard-aware height: a modal bottom sheet does NOT resize for the
    // keyboard, so subtract the keyboard inset from the fixed height. This keeps
    // the whole sheet — the group-name field, the user-search field, the
    // results list AND the create button — above the keyboard, so no field is
    // ever covered while typing.
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = (screenHeight * 0.85) - viewInsetsBottom;
    return Container(
      height: sheetHeight > 0 ? sheetHeight : screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.msgNewGroup,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 16),

                // Group name
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.msgGroupNameHint,
                    prefixIcon: const Icon(Icons.group_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // User search
                TextField(
                  controller: _searchController,
                  onChanged: _search,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.msgSearchUsersToAddHint,
                    prefixIcon: const Icon(Icons.person_add_outlined, size: 20),
                    suffixIcon: _searchLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: MarginaliaColors.sienna,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),

                // Selected chips
                if (_selectedUsers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selectedUsers.map((user) {
                      final name = user['display_name'] as String? ?? context.l10n.msgUserFallback;
                      return Chip(
                        label: Text(name),
                        onDeleted: () => _toggleUser(user),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        backgroundColor: MarginaliaColors.primaryFaint,
                        labelStyle: GoogleFonts.manrope(
                          fontSize: 12,
                          color: MarginaliaColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Search results
          Expanded(
            child: _searchResults.isEmpty && _searchController.text.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.msgSearchUserToAdd,
                      style: GoogleFonts.manrope(
                        color: MarginaliaColors.inkFaint,
                        fontSize: 13,
                      ),
                    ),
                  )
                : _searchResults.isEmpty && _searchController.text.isNotEmpty && !_searchLoading
                    ? Center(
                        child: Text(
                          context.l10n.msgNoUsersFound,
                          style: GoogleFonts.manrope(
                            color: MarginaliaColors.inkFaint,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final name =
                              user['display_name'] as String? ?? context.l10n.msgUserFallback;
                          final username = user['username'] as String? ?? '';
                          final avatarUrl = user['avatar_url'] as String?;
                          final initial =
                              name.isNotEmpty ? name[0].toUpperCase() : '?';
                          final avatarBg =
                              MarginaliaDecorations.bookCoverColor(name);
                          final isSelected = _selectedUsers
                              .any((u) => u['id'] == user['id']);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: _Avatar(
                              avatarUrl: avatarUrl,
                              initial: initial,
                              color: avatarBg,
                              size: 40,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.ink,
                              ),
                            ),
                            subtitle: username.isNotEmpty
                                ? Text(
                                    '@$username',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      color: MarginaliaColors.inkFaint,
                                    ),
                                  )
                                : null,
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: MarginaliaColors.primaryDark, size: 20)
                                : const Icon(Icons.add_circle_outline,
                                    color: MarginaliaColors.inkFaint, size: 20),
                            onTap: () => _toggleUser(user),
                          );
                        },
                      ),
          ),

          // Create button. The sheet height already subtracts the keyboard
          // inset (see build above), so the button sits above the keyboard
          // without adding viewInsets here — only clear the home indicator.
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 8, 24, MediaQuery.of(context).padding.bottom + 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _creating ? null : _createGroup,
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.l10n.msgCreateGroupCta),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

