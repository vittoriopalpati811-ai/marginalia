import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Notifications Screen ─────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.l10n.notificationsTitle,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: MarginaliaColors.ink,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref
                    .read(supabaseServiceProvider)
                    .markAllNotificationsRead();
                ref.invalidate(notificationsProvider);
                ref.invalidate(unreadNotificationCountProvider);
              } catch (_) {}
            },
            child: Text(
              context.l10n.notificationsMarkAllRead,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: MarginaliaColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) => notifications.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: notifications.length,
                itemBuilder: (_, i) => _NotificationCard(
                  data: notifications[i],
                  onRead: () async {
                    final id = notifications[i]['id'] as String?;
                    if (id == null) return;
                    try {
                      await ref
                          .read(supabaseServiceProvider)
                          .markNotificationRead(id);
                      ref.invalidate(notificationsProvider);
                      ref.invalidate(unreadNotificationCountProvider);
                    } catch (_) {}
                  },
                )
                    .animate(delay: (i * 40).ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.04, end: 0),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: MarginaliaColors.primary,
            strokeWidth: 1.5,
          ),
        ),
        error: (e, _) => Center(child: Text(context.l10n.errorPrefix('$e'))),
      ),
    );
  }
}

// ─── Notification card ────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.data,
    required this.onRead,
  });

  final Map<String, dynamic> data;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final isRead = data['is_read'] as bool? ?? false;
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final createdAt = data['created_at'] as String?;

    return GestureDetector(
      onTap: isRead ? null : onRead,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead
              ? MarginaliaColors.surface
              : MarginaliaColors.primaryFaint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead
                ? MarginaliaColors.rule
                : MarginaliaColors.primary.withAlpha(70),
            width: isRead ? 0.8 : 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread dot
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5, right: 12),
              decoration: BoxDecoration(
                color: isRead
                    ? Colors.transparent
                    : MarginaliaColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isRead ? FontWeight.w500 : FontWeight.w700,
                      color: MarginaliaColors.ink,
                      height: 1.3,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: MarginaliaColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatDate(createdAt),
                      style: MarginaliaTextStyles.label,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

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
            const Icon(
              Icons.notifications_none_outlined,
              size: 56,
              color: MarginaliaColors.inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.notificationsEmpty,
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.notificationsEmptyBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: MarginaliaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
