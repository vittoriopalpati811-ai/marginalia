import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/unread_messages_provider.dart';

/// Opens the Instagram-style "share to chats" sheet for [postId].
///
/// Slides up from the bottom (rounded top, surface-elevated handle) and lets
/// the user send the post to any of their existing conversations (1:1 + groups)
/// or start a DM with someone they follow. Tapping a recipient fires a send and
/// shows a brief "Inviato ✓" confirmation; the user can keep tapping to send to
/// several people, then dismiss.
///
/// [previewText] is a short snippet of the post body used as the message text
/// that accompanies the shared-post card (see
/// SupabaseService.sharePostToConversation).
Future<void> showSharePostSheet(
  BuildContext context, {
  required String postId,
  String? previewText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SharePostSheet(postId: postId, previewText: previewText),
  );
}

/// A single recipient row, normalised from either a conversation or a followed
/// profile, so the list can mix both and filter them uniformly by name.
class _Recipient {
  const _Recipient({
    required this.key,
    required this.name,
    required this.avatarUrl,
    required this.isGroup,
    this.conversationId,
    this.userId,
    this.subtitle,
  });

  /// Stable key for de-duplication + sent-tracking.
  final String key;
  final String name;
  final String? avatarUrl;
  final bool isGroup;

  /// Set for an existing conversation (1:1 or group).
  final String? conversationId;

  /// Set for a followed user we'd open/create a DM with.
  final String? userId;

  /// Optional secondary line (e.g. "@username" or participant count).
  final String? subtitle;
}

class _SharePostSheet extends ConsumerStatefulWidget {
  const _SharePostSheet({required this.postId, this.previewText});

  final String postId;
  final String? previewText;

  @override
  ConsumerState<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends ConsumerState<_SharePostSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  bool _loading = true;
  String? _error;
  List<_Recipient> _recipients = [];

  /// Keys of recipients already sent to this session — drives the row state
  /// (spinner → "Inviato ✓") and prevents double-sends.
  final Set<String> _sent = {};

  /// Keys currently sending — shows an inline spinner on that row.
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l10n = context.l10n;
    final svc = ref.read(supabaseServiceProvider);
    if (!svc.isAuthenticated) {
      setState(() {
        _loading = false;
        _recipients = [];
      });
      return;
    }
    try {
      // Existing conversations + followed users, in parallel.
      final results = await Future.wait([
        svc.fetchConversations(),
        svc.fetchFollowing(),
      ]);
      final conversations = results[0];
      final following = results[1];

      final recipients = <_Recipient>[];
      // Track which other-user ids already have a 1:1 conversation, so a
      // followed user isn't listed twice (once as a chat, once as "start DM").
      final dmUserIds = <String>{};

      for (final conv in conversations) {
        final convId = conv['id'] as String?;
        if (convId == null) continue;
        final isGroup = conv['is_group'] == true;
        final members = (conv['members'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();

        String name;
        String? avatarUrl;
        String? subtitle;

        if (isGroup) {
          final raw = (conv['group_name'] as String?)?.trim();
          name = (raw != null && raw.isNotEmpty) ? raw : l10n.msgGroupFallback;
          avatarUrl = conv['group_avatar_url'] as String?;
          if (members.isNotEmpty) {
            subtitle = l10n.msgParticipantCount(members.length);
          }
        } else {
          final other = members.isNotEmpty ? members.first : null;
          final raw = (other?['display_name'] as String?)?.trim();
          name = (raw != null && raw.isNotEmpty) ? raw : l10n.accountDeleted;
          avatarUrl = other?['avatar_url'] as String?;
          final otherId = other?['id'] as String?;
          if (otherId != null) dmUserIds.add(otherId);
        }

        recipients.add(_Recipient(
          key: 'conv_$convId',
          name: name,
          avatarUrl: avatarUrl,
          isGroup: isGroup,
          conversationId: convId,
          subtitle: subtitle,
        ));
      }

      for (final profile in following) {
        final uid = profile['id'] as String?;
        if (uid == null || dmUserIds.contains(uid)) continue;
        final raw = (profile['display_name'] as String?)?.trim();
        final name = (raw != null && raw.isNotEmpty) ? raw : l10n.msgUserFallback;
        recipients.add(_Recipient(
          key: 'user_$uid',
          name: name,
          avatarUrl: profile['avatar_url'] as String?,
          isGroup: false,
          userId: uid,
        ));
      }

      if (!mounted) return;
      setState(() {
        _recipients = recipients;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = l10n.sharePostLoadError;
        _loading = false;
      });
    }
  }

  Future<void> _sendTo(_Recipient r) async {
    if (_sending.contains(r.key) || _sent.contains(r.key)) return;
    final svc = ref.read(supabaseServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    setState(() => _sending.add(r.key));
    try {
      String conversationId;
      if (r.conversationId != null) {
        conversationId = r.conversationId!;
      } else {
        // Followed user with no existing DM — open/create one first.
        conversationId = await svc.createOrFetchDirectConversation(r.userId!);
      }
      await svc.sharePostToConversation(
        conversationId,
        widget.postId,
        previewText: widget.previewText,
      );
      // Refresh the inbox so the newly-touched conversation bubbles up.
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      setState(() {
        _sending.remove(r.key);
        _sent.add(r.key);
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.sharePostSent),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending.remove(r.key));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.sharePostError(e.toString()))),
      );
    }
  }

  List<_Recipient> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _recipients;
    return _recipients
        .where((r) => r.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // A modal bottom sheet does NOT resize for the keyboard, so subtract the
    // keyboard inset from the fixed height to keep the search field + rows
    // above the keyboard while typing.
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = (screenHeight * 0.78) - viewInsetsBottom;

    return Container(
      height: sheetHeight > 0 ? sheetHeight : screenHeight * 0.78,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Grab handle + title ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                Row(
                  children: [
                    Icon(
                      PhosphorIconsRegular.paperPlaneTilt,
                      size: 20,
                      color: MarginaliaColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.sharePostTitle,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ── Search box ───────────────────────────────────────────
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: context.l10n.sharePostSearchHint,
                    hintStyle: GoogleFonts.manrope(
                      color: MarginaliaColors.inkFaint,
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                      size: 20,
                      color: MarginaliaColors.inkFaint,
                    ),
                    filled: true,
                    fillColor: MarginaliaColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: MarginaliaColors.primaryDark,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Recipient list ───────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: MarginaliaColors.sienna,
          strokeWidth: 1.5,
        ),
      );
    }
    if (_error != null) {
      return _CenteredHint(text: _error!);
    }

    final items = _filtered;
    if (_recipients.isEmpty) {
      return _CenteredHint(text: context.l10n.sharePostNoConvos);
    }
    if (items.isEmpty) {
      return _CenteredHint(text: context.l10n.sharePostNoResults);
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        8, 8, 8, MediaQuery.of(context).padding.bottom + 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final r = items[index];
        return _RecipientRow(
          recipient: r,
          sending: _sending.contains(r.key),
          sent: _sent.contains(r.key),
          onTap: () => _sendTo(r),
        );
      },
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.recipient,
    required this.sending,
    required this.sent,
    required this.onTap,
  });

  final _Recipient recipient;
  final bool sending;
  final bool sent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial =
        recipient.name.isNotEmpty ? recipient.name[0].toUpperCase() : '?';
    final avatarBg = MarginaliaDecorations.bookCoverColor(recipient.name);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: sent ? null : onTap,
      leading: _ShareAvatar(
        avatarUrl: recipient.avatarUrl,
        initial: initial,
        color: avatarBg,
        isGroup: recipient.isGroup,
      ),
      title: Text(
        recipient.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: MarginaliaColors.ink,
        ),
      ),
      subtitle: recipient.subtitle != null
          ? Text(
              recipient.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: MarginaliaColors.inkFaint,
              ),
            )
          : (recipient.conversationId == null
              ? Text(
                  context.l10n.sharePostStartConvo,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: MarginaliaColors.inkFaint,
                  ),
                )
              : null),
      trailing: _trailing(context),
    );
  }

  Widget _trailing(BuildContext context) {
    if (sending) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: MarginaliaColors.sienna,
        ),
      );
    }
    if (sent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: MarginaliaColors.primaryFaint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.check,
                size: 13, color: MarginaliaColors.primaryDark),
            const SizedBox(width: 4),
            Text(
              context.l10n.sharePostSentLabel,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.primaryDark,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: MarginaliaColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        context.l10n.sharePostSendCta,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ShareAvatar extends StatelessWidget {
  const _ShareAvatar({
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
    const size = 44.0;
    Widget fallback() => Center(
          child: isGroup
              ? Icon(Icons.group_outlined,
                  color: Colors.white.withAlpha(220), size: size * 0.45)
              : Text(
                  initial,
                  style: GoogleFonts.ebGaramond(
                    fontSize: size * 0.42,
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

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: MarginaliaColors.inkMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
