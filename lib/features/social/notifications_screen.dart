import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Navigation helper ────────────────────────────────────────────────────────

/// Resolves the route a notification should open when tapped, or null if there
/// is no sensible destination.
///
/// `like` / `comment` notifications (created by notify_post_interaction) carry
/// `actor_id` (+ `post_id`) in their `data` jsonb. There is no standalone
/// post route in the app — posts are shown in bottom sheets inside profile /
/// feed timelines — so the most useful tap target is the ACTOR's profile (the
/// person who liked/commented). Jam-related notifications carry `jam_id` and
/// open the Jam.
String? _notificationDestination(Map<String, dynamic> n) {
  final data = n['data'];
  if (data is! Map) return null;
  final actorId = data['actor_id'] as String?;
  if (actorId != null && actorId.isNotEmpty) return '/user/$actorId';
  final jamId = (data['jam_id'] ?? n['jam_id']) as String?;
  if (jamId != null && jamId.isNotEmpty) return '/jam/$jamId';
  return null;
}

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
        // Force the back arrow (and any leading icon) to ink. On the founder's
        // phone it had rendered white/invisible; pinning it here keeps it
        // visible regardless of theme, matching every other screen.
        iconTheme: const IconThemeData(color: MarginaliaColors.ink),
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
                itemBuilder: (context, i) => _NotificationCard(
                  data: notifications[i],
                  onTap: () async {
                    final n = notifications[i];
                    final id = n['id'] as String?;
                    // Mark read (best-effort) then navigate to the relevant
                    // destination if we can resolve one from `data`.
                    if (id != null && (n['is_read'] as bool? ?? false) == false) {
                      try {
                        await ref
                            .read(supabaseServiceProvider)
                            .markNotificationRead(id);
                        ref.invalidate(notificationsProvider);
                        ref.invalidate(unreadNotificationCountProvider);
                      } catch (_) {}
                    }
                    if (!context.mounted) return;
                    final dest = _notificationDestination(n);
                    if (dest != null) context.push(dest);
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
    required this.onTap,
  });

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  /// Leading icon + tint chosen from the notification `type`. Covers the
  /// social types created by notify_post_interaction ('like', 'comment') and
  /// falls back to a generic bell for everything else (Jam alerts, etc.).
  (IconData, Color) _iconFor(String type) {
    switch (type) {
      case 'like':
        return (Icons.favorite, const Color(0xFFBF4A72));
      case 'comment':
        return (Icons.mode_comment_outlined, MarginaliaColors.primary);
      default:
        return (Icons.notifications_none_outlined, MarginaliaColors.sienna);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRead = data['is_read'] as bool? ?? false;
    final type = data['type'] as String? ?? '';
    final rawTitle = data['title'] as String? ?? '';
    // Defensive fallback: notify_post_interaction always sets a title, but an
    // older/foreign row might not. Uses an existing l10n key (no codegen).
    final title =
        rawTitle.isNotEmpty ? rawTitle : context.l10n.notificationsTitle;
    final body = data['body'] as String? ?? '';
    final createdAt = data['created_at'] as String?;
    final (icon, iconColor) = _iconFor(type);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
            // Type icon
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(28),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: iconColor),
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
              // This is the whole-app notification center (opened by the bell),
              // not just Jam activity — it shows likes, comments, follows and
              // Jam alerts (everything except message notifications). The copy
              // must therefore be app-wide. There's no l10n key for this exact
              // string yet, so use literal it/en (same pattern as other recent
              // screens) to avoid a codegen step.
              Localizations.localeOf(context).languageCode == 'it'
                  ? 'Le notifiche appariranno qui.'
                  : 'Your notifications will appear here.',
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
