// ─── Profile shared widgets ────────────────────────────────────────────────────
// Widgets used by both MyProfileScreen and UserProfileScreen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../library/book_cover.dart';
import '../reader/book_info_screen.dart';

/// Per-user custom book covers, keyed by [favCoverKey] ('title|author',
/// lowercased). Lets a reader's custom covers show on their favourites — both
/// on their own profile AND when someone else visits their profile. Pass the
/// profile owner's id; null/empty resolves to the signed-in user.
final favCoversProvider = FutureProvider.family
    .autoDispose<Map<String, String>, String?>((ref, ownerUserId) async {
  final svc = ref.watch(supabaseServiceProvider);
  final uid =
      (ownerUserId == null || ownerUserId.isEmpty) ? svc.userId : ownerUserId;
  if (uid == null || uid.isEmpty) return const {};
  return svc.fetchBookCovers(uid);
});

/// Normalised lookup key for [favCoversProvider]; mirrors
/// SupabaseService.fetchBookCovers ('title|author', both lowercased + trimmed).
String favCoverKey(String title, String author) =>
    '${title.toLowerCase().trim()}|${author.toLowerCase().trim()}';

// ─── Favourite books Pinterest masonry grid ────────────────────────────────────

enum FavTileSize { large, medium, small }

class FavBooksGrid extends StatelessWidget {
  const FavBooksGrid({super.key, required this.favBooks, this.ownerUserId});
  final List<Map<String, String>> favBooks;

  /// Profile owner whose custom covers to show (null = signed-in user).
  final String? ownerUserId;

  @override
  Widget build(BuildContext context) {
    final n = favBooks.length.clamp(0, 6);
    if (n == 0) return const SizedBox.shrink();

    const gap   = 6.0;
    const row1H = 200.0;
    const row2H = 118.0;

    final row1 = favBooks.take(3).toList();
    final row2 = n > 3
        ? favBooks.skip(3).take(3).toList()
        : <Map<String, String>>[];

    Widget tile(Map<String, String> b, FavTileSize s) =>
        FavBookTile(book: b, size: s, ownerUserId: ownerUserId);

    return Column(
      children: [
        // ── Row 1: large left + up to two stacked mediums ─────────────────
        SizedBox(
          height: row1H,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: row1.length >= 2 ? 55 : 100,
                child: tile(row1[0], FavTileSize.large),
              ),
              if (row1.length >= 2) ...[
                const SizedBox(width: gap),
                Expanded(
                  flex: 45,
                  child: row1.length >= 3
                      ? Column(
                          children: [
                            Expanded(child: tile(row1[1], FavTileSize.medium)),
                            const SizedBox(height: gap),
                            Expanded(child: tile(row1[2], FavTileSize.medium)),
                          ],
                        )
                      : tile(row1[1], FavTileSize.medium),
                ),
              ],
            ],
          ),
        ),
        // ── Row 2: 1–3 small tiles (only when books 4–6 exist) ────────────
        if (row2.isNotEmpty) ...[
          const SizedBox(height: gap),
          SizedBox(
            height: row2H,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < row2.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(child: tile(row2[i], FavTileSize.small)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class FavBookTile extends ConsumerWidget {
  const FavBookTile(
      {super.key, required this.book, required this.size, this.ownerUserId});
  final Map<String, String> book;
  final FavTileSize size;

  /// Profile owner whose custom covers to show (null = signed-in user).
  final String? ownerUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title  = book['title']  ?? '';
    final author = book['author'] ?? '';
    final coverUrl = title.isEmpty
        ? null
        : ref
            .watch(favCoversProvider(ownerUserId))
            .asData
            ?.value[favCoverKey(title, author)];

    if (title.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: ScriptaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ScriptaColors.ruleFaint),
        ),
        child: const Center(
          child: Icon(Icons.add_outlined, size: 22, color: ScriptaColors.inkFaint),
        ),
      );
    }

    final double titleSize = switch (size) {
      FavTileSize.large  => 13.0,
      FavTileSize.medium => 11.5,
      FavTileSize.small  => 9.5,
    };
    final int maxLines = switch (size) {
      FavTileSize.large  => 3,
      FavTileSize.medium => 2,
      FavTileSize.small  => 2,
    };
    final double gradH = switch (size) {
      FavTileSize.large  => 90.0,
      FavTileSize.medium => 72.0,
      FavTileSize.small  => 60.0,
    };

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookInfoScreen(title: title, author: author),
        ),
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BookEditorialCover(title: title, author: author, coverUrl: coverUrl),
          Positioned(
            left: 0, right: 0, bottom: 0, height: gradH,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xCC000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8, right: 8, bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFEDE5D5),
                    height: 1.25,
                    letterSpacing: -0.1,
                  ),
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                if (size == FavTileSize.large && author.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    author.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: Color(0x99EDE5D5),
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
}

// ─── Instagram-style posts grid ────────────────────────────────────────────────

class PostsGrid extends StatelessWidget {
  const PostsGrid({super.key, required this.posts});
  final List<Map<String, dynamic>> posts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: posts.length,
        itemBuilder: (_, i) => PostGridTile(
          post: posts[i],
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => PostDetailSheet(post: posts[i]),
          ),
        ),
      ),
    );
  }
}

class PostGridTile extends StatelessWidget {
  const PostGridTile({super.key, required this.post, required this.onTap});
  final Map<String, dynamic> post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final body      = post['body']       as String?;
    final imageUrl  = post['image_url']  as String?;
    final highlight = post['highlights'] as Map?;
    final hlContent = highlight?['content'] as String?;

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final isQuote  = (body == null || body.trim().isEmpty) && hlContent != null;
    final preview  = isQuote ? hlContent!.trim() : (body?.trim() ?? '');

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: hasImage
            ? _PostImageTile(imageUrl: imageUrl!)
            : _PostTextTile(preview: preview, isQuote: isQuote),
      ),
    );
  }
}

// Quote tile: warm cream + serif opening mark
// Text tile: white + manrope body
class _PostTextTile extends StatelessWidget {
  const _PostTextTile({required this.preview, required this.isQuote});
  final String preview;
  final bool isQuote;

  @override
  Widget build(BuildContext context) {
    if (isQuote) {
      return Container(
        decoration: BoxDecoration(
          color: ScriptaColors.background,
          border: Border.all(color: ScriptaColors.ruleFaint, width: 0.8),
        ),
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 7),
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '“',
              style: GoogleFonts.ebGaramond(
                fontSize: 17,
                color: ScriptaColors.siennaLight.withAlpha(150),
                height: 0.85,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              preview,
              style: GoogleFonts.ebGaramond(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: ScriptaColors.ink,
                height: 1.4,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: ScriptaColors.surface,
        border: Border.all(color: ScriptaColors.ruleFaint, width: 0.8),
      ),
      padding: const EdgeInsets.all(8),
      alignment: Alignment.topLeft,
      child: Text(
        preview,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: ScriptaColors.ink,
          height: 1.4,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// Image tile: photo with loading shimmer and visible error state
class _PostImageTile extends StatelessWidget {
  const _PostImageTile({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(
              color: ScriptaColors.surfaceElevated,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: ScriptaColors.inkFaint,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              ),
            ),
      errorBuilder: (_, __, ___) => Container(
        color: ScriptaColors.surfaceElevated,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 22,
            color: ScriptaColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

// ─── Post detail sheet (generic) ──────────────────────────────────────────────

class PostDetailSheet extends ConsumerWidget {
  const PostDetailSheet({super.key, required this.post});
  final Map<String, dynamic> post;

  String _timeAgo(BuildContext context, String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return context.l10n.timeNow;
    if (diff.inMinutes < 60) return context.l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24)   return context.l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7)     return context.l10n.timeDaysAgo(diff.inDays);
    return context.l10n.timeWeeksAgo((diff.inDays / 7).round());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom    = MediaQuery.of(context).padding.bottom;
    final body      = post['body']        as String?;
    final imageUrl  = post['image_url']   as String?;
    final createdAt = post['created_at']  as String?;
    final likes     = post['likes_count'] as int? ?? 0;
    final highlight = post['highlights']  as Map?;
    final hlContent = highlight?['content'] as String?;
    final hlBook    = highlight?['books']   as Map?;
    final hlTitle   = hlBook?['title']  as String?;

    // Like-count visibility mirrors the feed: the author can hide the COUNT
    // (not the heart). Hide the number when hide_like_count is set and the
    // post isn't mine; my own posts always show the count.
    final currentUserId = ref.read(supabaseServiceProvider).userId;
    final isMine = currentUserId != null && currentUserId == post['user_id'];
    final hideLikeCount = post['hide_like_count'] == true && !isMine;

    return Container(
      decoration: const BoxDecoration(
        color: ScriptaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: ScriptaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timestamp
                  if (createdAt != null)
                    Text(
                      _timeAgo(context, createdAt),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: ScriptaColors.inkFaint,
                      ),
                    ),
                  // Body
                  if (body != null && body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      body,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: ScriptaColors.ink,
                        height: 1.65,
                      ),
                    ),
                  ],
                  // Attached highlight
                  if (hlContent != null && hlContent.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: ScriptaColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: ScriptaColors.ruleFaint, width: 0.8),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hlTitle != null && hlTitle.isNotEmpty)
                            Text(
                              hlTitle.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: ScriptaColors.inkMuted,
                                letterSpacing: 1.1,
                              ),
                            ),
                          const SizedBox(height: 5),
                          Text(
                            hlContent,
                            style: GoogleFonts.ebGaramond(
                              fontSize: 14.5,
                              fontStyle: FontStyle.italic,
                              color: ScriptaColors.ink,
                              height: 1.65,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Image
                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    height: 180,
                                    decoration: BoxDecoration(
                                      color: ScriptaColors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: ScriptaColors.sienna,
                                      ),
                                    ),
                                  ),
                        errorBuilder: (_, __, ___) => Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: ScriptaColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: ScriptaColors.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Likes — the heart always shows; the COUNT is hidden when
                  // the author hid it and this isn't my own post.
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.favorite_border,
                          size: 14, color: ScriptaColors.inkFaint),
                      if (!hideLikeCount) ...[
                        const SizedBox(width: 5),
                        Text(
                          '$likes',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: ScriptaColors.inkFaint,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
