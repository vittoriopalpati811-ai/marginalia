// ─── Blocked-users management screen (App Store Guideline 1.2) ───────────────
//
// Lists everyone the current user has blocked, with a per-row "Unblock" action.
// Reached from Settings → Privacy & data → "Blocked users".
//
// Data flow:
//   • `fetchBlockedUserIds(forceRefresh: true)` gives the set of blocked ids.
//   • For each id we resolve a public profile (`fetchPublicProfile`) for the
//     avatar + display name. Soft-deleted accounts return null and are shown
//     with a neutral fallback so they can still be unblocked.
//   • Unblock calls `unblockUser(id)`, drops the row locally, and confirms.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';

/// A blocked user resolved for display: the [id] (always present) plus optional
/// profile fields. [displayName] is null for accounts that no longer exist.
class _BlockedUser {
  const _BlockedUser({required this.id, this.displayName, this.avatarUrl});
  final String id;
  final String? displayName;
  final String? avatarUrl;
}

/// Loads the blocked set and resolves each id to a display profile. Forces a
/// refresh so the list is authoritative every time the screen opens.
final _blockedUsersProvider =
    FutureProvider.autoDispose<List<_BlockedUser>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return const [];

  final ids = await svc.fetchBlockedUserIds(forceRefresh: true);
  if (ids.isEmpty) return const [];

  // Resolve profiles in parallel; a failed lookup degrades to id-only so the
  // user can still unblock.
  final users = await Future.wait(ids.map((id) async {
    try {
      final profile = await svc.fetchPublicProfile(id);
      return _BlockedUser(
        id: id,
        displayName: profile?['display_name'] as String?,
        avatarUrl: profile?['avatar_url'] as String?,
      );
    } catch (_) {
      return _BlockedUser(id: id);
    }
  }));

  return users;
});

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  // Ids currently being unblocked — disables the row's button and removes it
  // optimistically once the RPC succeeds.
  final Set<String> _unblocking = {};
  // Ids removed locally after a successful unblock, so the row disappears
  // without re-fetching the whole list.
  final Set<String> _removed = {};

  Future<void> _unblock(_BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final svc = ref.read(supabaseServiceProvider);

    setState(() => _unblocking.add(user.id));
    try {
      await svc.unblockUser(user.id);
      if (!mounted) return;
      setState(() {
        _removed.add(user.id);
        _unblocking.remove(user.id);
      });
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.userUnblocked)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _unblocking.remove(user.id));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorPrefix('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_blockedUsersProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        foregroundColor: MarginaliaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.l10n.blockedUsersTitle),
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: MarginaliaColors.sienna,
            strokeWidth: 1.5,
          ),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(_blockedUsersProvider),
        ),
        data: (users) {
          final visible =
              users.where((u) => !_removed.contains(u.id)).toList();
          if (visible.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            color: MarginaliaColors.sienna,
            backgroundColor: MarginaliaColors.surface,
            strokeWidth: 1.5,
            onRefresh: () async {
              _removed.clear();
              ref.invalidate(_blockedUsersProvider);
              await ref.read(_blockedUsersProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 72,
                color: MarginaliaColors.ruleFaint,
              ),
              itemBuilder: (_, i) {
                final user = visible[i];
                return _BlockedUserRow(
                  user: user,
                  busy: _unblocking.contains(user.id),
                  onUnblock: () => _unblock(user),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow({
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final _BlockedUser user;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : context.l10n.accountDeleted;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '·';
    final tint = MarginaliaDecorations.bookCoverColor(name);
    final avatarUrl = user.avatarUrl;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tint, MarginaliaColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AvatarInitial(initial: initial),
              )
            : _AvatarInitial(initial: initial),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: MarginaliaColors.ink,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: MarginaliaColors.sienna,
              ),
            )
          : OutlinedButton(
              onPressed: onUnblock,
              style: OutlinedButton.styleFrom(
                foregroundColor: MarginaliaColors.primaryDark,
                side: const BorderSide(color: MarginaliaColors.rule),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text(context.l10n.unblockAction),
            ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFFF1EEE7),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.block_outlined,
                  size: 28, color: MarginaliaColors.primaryDark),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.blockedUsersEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: MarginaliaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: MarginaliaColors.inkFaint, size: 40),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
