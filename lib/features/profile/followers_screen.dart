import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';

// ─── List type enum ───────────────────────────────────────────────────────────

enum ProfileListType { followers, following, books }

// ─── Modal bottom sheet entry point ──────────────────────────────────────────

/// Shows the followers/following/books list as a draggable bottom sheet.
Future<void> showProfileList(
  BuildContext context, {
  required String userId,
  required ProfileListType type,
  required int count,
  // Called after a follower is removed, so the profile behind the sheet can
  // refresh its (now-decremented) follower count.
  VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      userId: userId,
      type: type,
      count: count,
      onChanged: onChanged,
    ),
  );
}

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

class _ProfileListSheet extends ConsumerStatefulWidget {
  const _ProfileListSheet({
    required this.userId,
    required this.type,
    required this.count,
    this.onChanged,
  });
  final String userId;
  final ProfileListType type;
  final int count;
  final VoidCallback? onChanged;

  @override
  ConsumerState<_ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends ConsumerState<_ProfileListSheet> {
  List<Map<String, dynamic>>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(supabaseServiceProvider);
      List<Map<String, dynamic>> data;
      switch (widget.type) {
        case ProfileListType.followers:
          data = await svc.fetchUserFollowers(widget.userId);
        case ProfileListType.following:
          data = await svc.fetchUserFollowing(widget.userId);
        case ProfileListType.books:
          data = await svc.fetchUserBooks(widget.userId);
      }
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _title(BuildContext context) => switch (widget.type) {
        ProfileListType.followers => context.l10n.profileFollowers,
        ProfileListType.following => context.l10n.profileFollowing,
        ProfileListType.books     => context.l10n.booksTitle,
      };

  /// Followee-side curation: drop [followerId] from MY followers, then remove
  /// the row locally and refresh the count shown to the user. Only reachable on
  /// my OWN followers list (the overflow is hidden elsewhere).
  Future<void> _removeFollower(String followerId) async {
    final messenger = ScaffoldMessenger.of(context);
    final it = Localizations.localeOf(context).languageCode == 'it';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(it ? 'Rimuovere questo follower?' : 'Remove this follower?',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(it ? 'Annulla' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB94A41)),
            child: Text(it ? 'Rimuovi' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(supabaseServiceProvider).removeFollower(followerId);
      if (!mounted) return;
      setState(() => _items?.removeWhere((m) => m['id'] == followerId));
      // Refresh the profile's follower count behind the sheet.
      widget.onChanged?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(it ? 'Errore: $e' : 'Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // "Remove follower" is only offered on MY OWN followers list — never on
    // another reader's followers, and never on a Following list.
    final myId = ref.watch(supabaseServiceProvider).userId;
    final canRemove = widget.type == ProfileListType.followers &&
        myId != null &&
        myId == widget.userId;
    // Keep the header count in step with local removals once the list loaded.
    final shownCount = _items?.length ?? widget.count;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: ScriptaColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ScriptaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Text(
                      _title(context),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: ScriptaColors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$shownCount',
                      style: const TextStyle(
                        fontSize: 14,
                        color: ScriptaColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: ScriptaColors.ruleFaint, height: 1),
              // Content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ScriptaColors.sienna,
                          strokeWidth: 1.5,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Text(
                              context.l10n.errorPrefix('$_error'),
                              style: const TextStyle(
                                  color: ScriptaColors.inkMuted),
                            ),
                          )
                        : (_items?.isEmpty ?? true)
                            ? _EmptyState(type: widget.type)
                            : ListView.separated(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _items!.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: ScriptaColors.ruleFaint,
                                  height: 1,
                                  indent: 72,
                                ),
                                itemBuilder: (_, i) {
                                  final item = _items![i];
                                  return widget.type == ProfileListType.books
                                      ? _BookRow(data: item, index: i)
                                      : _UserRow(
                                          data: item,
                                          index: i,
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            context.push(
                                                '/user/${item['id']}');
                                          },
                                          onRemove:
                                              canRemove && item['id'] != null
                                                  ? () => _removeFollower(
                                                      item['id'] as String)
                                                  : null,
                                        );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── User row ─────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.data,
    required this.index,
    required this.onTap,
    this.onRemove,
  });
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback onTap;

  /// When non-null, the row shows a 3-dot overflow with "Remove" → removes this
  /// follower. Only set on the signed-in user's OWN followers list.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final it = Localizations.localeOf(context).languageCode == 'it';
    final name = data['display_name'] as String? ?? context.l10n.profileReaderFallback;
    final reading = data['currently_reading_title'] as String?;
    final avatarUrl = data['avatar_url'] as String?;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'L';

    return ListTile(
      onTap: onTap,
      leading: _Avatar(avatarUrl: avatarUrl, initial: initial, name: name),
      title: Text(
        name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ScriptaColors.ink,
        ),
      ),
      subtitle: reading != null && reading.isNotEmpty
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined,
                    size: 12, color: ScriptaColors.inkFaint),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    reading,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ScriptaColors.inkMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : null,
      trailing: onRemove != null
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz,
                  color: ScriptaColors.inkFaint, size: 20),
              color: ScriptaColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'remove') onRemove!();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(Icons.person_remove_outlined,
                          size: 18, color: Color(0xFFB94A41)),
                      const SizedBox(width: 10),
                      Text(
                        it ? 'Rimuovi' : 'Remove',
                        style: const TextStyle(
                            fontSize: 14, color: ScriptaColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Icon(
              Icons.chevron_right,
              color: ScriptaColors.inkFaint,
              size: 18,
            ),
    )
        .animate(delay: (index * 25).ms)
        .fadeIn(duration: 200.ms)
        .slideX(begin: 0.04, end: 0, duration: 200.ms);
  }
}

// ─── Book row ─────────────────────────────────────────────────────────────────

class _BookRow extends StatelessWidget {
  const _BookRow({required this.data, required this.index});
  final Map<String, dynamic> data;
  final int index;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? context.l10n.bookUntitled;
    final author = data['author'] as String? ?? '';
    final coverColor = ScriptaDecorations.bookCoverColor(title);

    return ListTile(
      leading: Container(
        width: 40,
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [coverColor, ScriptaColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x221A2614),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.menu_book_outlined,
              size: 16, color: Color(0xCCF2F5EA)),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ScriptaColors.ink,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: author.isNotEmpty
          ? Text(
              author.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: ScriptaColors.inkMuted,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    )
        .animate(delay: (index * 25).ms)
        .fadeIn(duration: 200.ms)
        .slideX(begin: 0.04, end: 0, duration: 200.ms);
  }
}

// ─── Avatar widget ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.initial,
    required this.name,
  });
  final String? avatarUrl;
  final String initial;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            ScriptaDecorations.bookCoverColor(name),
            ScriptaColors.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xFFF2F5EA),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFFF2F5EA),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.type});
  final ProfileListType type;

  @override
  Widget build(BuildContext context) {
    final (icon, msg) = switch (type) {
      ProfileListType.followers => (Icons.group_outlined, context.l10n.profileNoFollowers),
      ProfileListType.following => (Icons.person_add_outlined, context.l10n.profileNoFollowing),
      ProfileListType.books     => (Icons.menu_book_outlined, context.l10n.profileNoBooksImported),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: ScriptaColors.inkFaint),
          const SizedBox(height: 12),
          Text(
            msg,
            style: const TextStyle(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
