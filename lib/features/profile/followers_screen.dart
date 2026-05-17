import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
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
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      userId: userId,
      type: type,
      count: count,
    ),
  );
}

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

class _ProfileListSheet extends ConsumerStatefulWidget {
  const _ProfileListSheet({
    required this.userId,
    required this.type,
    required this.count,
  });
  final String userId;
  final ProfileListType type;
  final int count;

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

  String get _title => switch (widget.type) {
        ProfileListType.followers => 'Follower',
        ProfileListType.following => 'Seguiti',
        ProfileListType.books     => 'Libri letti',
      };

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: MarginaliaColors.background,
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
                    color: MarginaliaColors.rule,
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
                      _title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: MarginaliaColors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.count}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: MarginaliaColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: MarginaliaColors.ruleFaint, height: 1),
              // Content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: MarginaliaColors.sienna,
                          strokeWidth: 1.5,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Text(
                              'Errore: $_error',
                              style: const TextStyle(
                                  color: MarginaliaColors.inkMuted),
                            ),
                          )
                        : (_items?.isEmpty ?? true)
                            ? _EmptyState(type: widget.type)
                            : ListView.separated(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _items!.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: MarginaliaColors.ruleFaint,
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
  });
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = data['display_name'] as String? ?? 'Lettore';
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
          color: MarginaliaColors.ink,
        ),
      ),
      subtitle: reading != null && reading.isNotEmpty
          ? Text(
              '📖 $reading',
              style: const TextStyle(
                fontSize: 12,
                color: MarginaliaColors.inkMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right,
        color: MarginaliaColors.inkFaint,
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
    final title = data['title'] as String? ?? 'Titolo sconosciuto';
    final author = data['author'] as String? ?? '';
    final coverColor = MarginaliaDecorations.bookCoverColor(title);

    return ListTile(
      leading: Container(
        width: 40,
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [coverColor, MarginaliaColors.primaryDark],
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
          color: MarginaliaColors.ink,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: author.isNotEmpty
          ? Text(
              author.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: MarginaliaColors.inkMuted,
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
            MarginaliaDecorations.bookCoverColor(name),
            MarginaliaColors.primaryDark,
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
      ProfileListType.followers => (Icons.group_outlined, 'Nessun follower ancora'),
      ProfileListType.following => (Icons.person_add_outlined, 'Non segui ancora nessuno'),
      ProfileListType.books     => (Icons.menu_book_outlined, 'Nessun libro importato'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: MarginaliaColors.inkFaint),
          const SizedBox(height: 12),
          Text(
            msg,
            style: const TextStyle(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
