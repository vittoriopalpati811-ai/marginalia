// ─── Threads-style profile posts timeline ──────────────────────────────────
//
// Replaces the 3-column Instagram grid with a vertical Threads-style
// timeline: avatar (left) + name & timestamp header, full-width body,
// optional image / highlight quote card, action row, hairline divider
// between posts. No card chrome — edge-to-edge with generous vertical
// rhythm, the way Threads renders a profile feed.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/theme.dart';

class PostsTimeline extends StatelessWidget {
  const PostsTimeline({
    super.key,
    required this.posts,
    required this.profile,
    this.onTapPost,
    this.isOwnProfile = false,
  });

  /// Posts list (each is a Map from Supabase select).
  final List<Map<String, dynamic>> posts;

  /// The owner profile (display_name, avatar_url, username) used for the
  /// post header so the timeline can render even when posts don't embed
  /// their author profile.
  final Map<String, dynamic>? profile;

  final void Function(Map<String, dynamic> post)? onTapPost;

  /// True when this timeline shows the signed-in user's OWN posts (my profile).
  /// Controls how a hidden like count is presented: hidden from other readers,
  /// but the owner still sees the number plus a small visibility-off hint.
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(posts.length, (i) {
        final post = posts[i];
        final isLast = i == posts.length - 1;
        return StaggeredListItem(
          index: i,
          child: _ThreadPost(
            post: post,
            profile: profile,
            showDivider: !isLast,
            isOwnProfile: isOwnProfile,
            onTap: onTapPost == null ? null : () => onTapPost!(post),
            key: ValueKey('thread-${post['id']}'),
          ),
        );
      }),
    );
  }
}

// ─── Single post row ───────────────────────────────────────────────────────

class _ThreadPost extends StatelessWidget {
  const _ThreadPost({
    super.key,
    required this.post,
    required this.profile,
    required this.showDivider,
    required this.isOwnProfile,
    this.onTap,
  });

  final Map<String, dynamic>  post;
  final Map<String, dynamic>? profile;
  final bool                  showDivider;
  final bool                  isOwnProfile;
  final VoidCallback?         onTap;

  String _timeAgo(BuildContext context, String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1)  return context.l10n.timeNow;
    if (diff.inMinutes < 60) return context.l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours   < 24) return context.l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays    <  7) return context.l10n.timeDaysAgo(diff.inDays);
    return context.l10n.timeWeeksAgo((diff.inDays / 7).floor());
  }

  @override
  Widget build(BuildContext context) {
    final body      = (post['body']      as String?)?.trim() ?? '';
    final imageUrl  = post['image_url']  as String?;
    final highlight = post['highlights'] as Map?;
    final hlContent = (highlight?['content'] as String?)?.trim();
    final hlBook    = highlight?['books'] as Map?;
    final hlTitle   = (hlBook?['title']  as String?)?.trim();
    final hlAuthor  = (hlBook?['author'] as String?)?.trim();
    final likes     = (post['likes_count'] as num?)?.toInt() ?? 0;
    final hideLikes = post['hide_like_count'] as bool? ?? false;

    final name      = (profile?['display_name'] as String?)?.trim()
        ?? (profile?['username'] as String?)?.trim()
        ?? context.l10n.profileReaderFallback;
    final username  = profile?['username']  as String?;
    final avatarUrl = profile?['avatar_url'] as String?;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint      = ScriptaDecorations.bookCoverColor(name);
    final timeAgo   = _timeAgo(context, post['created_at'] as String?);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar column ─────────────────────────────────────────
                _Avatar(
                  avatarUrl: avatarUrl,
                  initial: initial,
                  tint: tint,
                ),
                const SizedBox(width: 12),

                // ── Content column ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: name · @username · timeAgo
                      _Header(name: name, username: username, timeAgo: timeAgo),
                      const SizedBox(height: 4),

                      // Body
                      if (body.isNotEmpty) ...[
                        Text(
                          body,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            height: 1.42,
                            color: ScriptaColors.ink,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Optional image
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Optional highlight quote card
                      if (hlContent != null && hlContent.isNotEmpty)
                        _QuoteCard(
                          content: hlContent,
                          bookTitle: hlTitle,
                          author: hlAuthor,
                        ),

                      // Actions row
                      const SizedBox(height: 10),
                      _Actions(
                        likes: likes,
                        hideLikes: hideLikes,
                        isOwnProfile: isOwnProfile,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Threads-style hairline divider, indented past the avatar gutter
        if (showDivider)
          Container(
            margin: const EdgeInsets.only(left: 60),
            height: 0.5,
            color: ScriptaColors.ruleFaint,
          ),
      ],
    );
  }
}

// ─── Avatar ────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.initial,
    required this.tint,
  });
  final String? avatarUrl;
  final String  initial;
  final Color   tint;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [tint, ScriptaColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                width: size, height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialFallback(),
              ),
            )
          : _initialFallback(),
    );
  }

  Widget _initialFallback() => Center(
        child: Text(
          initial,
          style: GoogleFonts.ebGaramond(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
      );
}

// ─── Header row (name + username + time) ───────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.username,
    required this.timeAgo,
  });
  final String  name;
  final String? username;
  final String  timeAgo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: ScriptaColors.ink,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (username != null && username!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ScriptaColors.inkFaint,
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Text(
          '·',
          style: TextStyle(
            color: ScriptaColors.inkFaint,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          timeAgo,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: ScriptaColors.inkFaint,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Quote card (when post wraps a highlight) ─────────────────────────────

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.content,
    required this.bookTitle,
    required this.author,
  });
  final String  content;
  final String? bookTitle;
  final String? author;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScriptaColors.rule, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: GoogleFonts.ebGaramond(
              fontSize: 26,
              height: 0.6,
              color: ScriptaColors.siennaLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: GoogleFonts.ebGaramond(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              height: 1.55,
              color: ScriptaColors.ink,
              letterSpacing: 0.05,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          if (bookTitle != null && bookTitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              author != null && author!.isNotEmpty
                  ? '${bookTitle!.toUpperCase()} · ${author!}'
                  : bookTitle!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: ScriptaColors.inkFaint,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Action row (likes · reply · share) ────────────────────────────────────

class _Actions extends StatelessWidget {
  const _Actions({
    required this.likes,
    required this.hideLikes,
    required this.isOwnProfile,
  });
  final int  likes;
  final bool hideLikes;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    // When the author hid the like count, other readers see the heart with no
    // number; the owner still sees the number plus a small visibility-off hint.
    final showCount = !hideLikes || isOwnProfile;
    return Row(
      children: [
        _ActionIcon(
          icon: Icons.favorite_outline,
          count: showCount ? likes : 0,
          trailing: (hideLikes && isOwnProfile)
              ? const Icon(
                  Icons.visibility_off_outlined,
                  size: 16,
                  color: ScriptaColors.inkFaint,
                )
              : null,
        ),
        const SizedBox(width: 18),
        const _ActionIcon(icon: Icons.mode_comment_outlined),
        const SizedBox(width: 18),
        const _ActionIcon(icon: Icons.send_outlined),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, this.count = 0, this.trailing});
  final IconData icon;
  final int      count;
  final Widget?  trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: ScriptaColors.inkMuted),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Text(
            count.toString(),
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.inkMuted,
            ),
          ),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing!,
        ],
      ],
    );
  }
}
