// ─── Profile shared widgets ────────────────────────────────────────────────────
// Widgets used by both MyProfileScreen and UserProfileScreen.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../library/book_cover.dart';

// ─── Favourite books Pinterest masonry grid ────────────────────────────────────

enum FavTileSize { large, medium, small }

class FavBooksGrid extends StatelessWidget {
  const FavBooksGrid({super.key, required this.favBooks});
  final List<Map<String, String>> favBooks;

  @override
  Widget build(BuildContext context) {
    final books = List<Map<String, String>>.from(favBooks);
    while (books.length < 6) {
      books.add({'title': '', 'author': ''});
    }

    const gap  = 6.0;
    const row1 = 200.0;
    const row2 = 118.0;

    return Column(
      children: [
        // ── Row 1: large left + two stacked mediums ───────────────────────
        SizedBox(
          height: row1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 55,
                child: FavBookTile(book: books[0], size: FavTileSize.large),
              ),
              const SizedBox(width: gap),
              Expanded(
                flex: 45,
                child: Column(
                  children: [
                    Expanded(
                      child: FavBookTile(book: books[1], size: FavTileSize.medium),
                    ),
                    const SizedBox(height: gap),
                    Expanded(
                      child: FavBookTile(book: books[2], size: FavTileSize.medium),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: gap),
        // ── Row 2: three equal small tiles ───────────────────────────────
        SizedBox(
          height: row2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: FavBookTile(book: books[3], size: FavTileSize.small)),
              const SizedBox(width: gap),
              Expanded(child: FavBookTile(book: books[4], size: FavTileSize.small)),
              const SizedBox(width: gap),
              Expanded(child: FavBookTile(book: books[5], size: FavTileSize.small)),
            ],
          ),
        ),
      ],
    );
  }
}

class FavBookTile extends StatelessWidget {
  const FavBookTile({super.key, required this.book, required this.size});
  final Map<String, String> book;
  final FavTileSize size;

  @override
  Widget build(BuildContext context) {
    final title  = book['title']  ?? '';
    final author = book['author'] ?? '';

    if (title.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MarginaliaColors.ruleFaint),
        ),
        child: const Center(
          child: Icon(Icons.add_outlined, size: 22, color: MarginaliaColors.inkFaint),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BookEditorialCover(title: title, author: author),
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
    );
  }
}

// ─── Instagram-style posts grid ────────────────────────────────────────────────

const kPostBgColors = <Color>[
  Color(0xFF3D5A4E), // sage
  Color(0xFF4A3D5A), // plum
  Color(0xFF5A4A3D), // umber
  Color(0xFF3D4A5A), // slate
  Color(0xFF5A3D4A), // dusty rose
  Color(0xFF4A5A3D), // olive
  Color(0xFF5A3D3D), // terracotta
  Color(0xFF3D3D5A), // indigo
];

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
    final hash     = preview.hashCode.abs();
    final bgColor  = kPostBgColors[hash % kPostBgColors.length];

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(color: bgColor),
              )
            else
              ColoredBox(color: bgColor),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(hasImage ? 170 : 110),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),
            ),
            if (preview.isNotEmpty)
              Positioned(
                left: 7, right: 18, bottom: 7,
                child: Text(
                  preview,
                  style: isQuote
                      ? GoogleFonts.ebGaramond(
                          fontSize: 8.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                          height: 1.3,
                        )
                      : GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Positioned(
              bottom: 4, right: 4,
              child: Icon(
                Icons.chevron_right_rounded,
                color: Color(0xCCFFFFFF),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Post detail sheet (generic) ──────────────────────────────────────────────

class PostDetailSheet extends StatelessWidget {
  const PostDetailSheet({super.key, required this.post});
  final Map<String, dynamic> post;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24)   return '${diff.inHours}h fa';
    if (diff.inDays < 7)     return '${diff.inDays}g fa';
    return '${(diff.inDays / 7).round()}sett fa';
  }

  @override
  Widget build(BuildContext context) {
    final bottom    = MediaQuery.of(context).padding.bottom;
    final body      = post['body']        as String?;
    final imageUrl  = post['image_url']   as String?;
    final createdAt = post['created_at']  as String?;
    final likes     = post['likes_count'] as int? ?? 0;
    final highlight = post['highlights']  as Map?;
    final hlContent = highlight?['content'] as String?;
    final hlBook    = highlight?['books']   as Map?;
    final hlTitle   = hlBook?['title']  as String?;

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
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
                      _timeAgo(createdAt),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: MarginaliaColors.inkFaint,
                      ),
                    ),
                  // Body
                  if (body != null && body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      body,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: MarginaliaColors.ink,
                        height: 1.65,
                      ),
                    ),
                  ],
                  // Attached highlight
                  if (hlContent != null && hlContent.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: MarginaliaColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: MarginaliaColors.ruleFaint, width: 0.8),
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
                                color: MarginaliaColors.inkMuted,
                                letterSpacing: 1.1,
                              ),
                            ),
                          const SizedBox(height: 5),
                          Text(
                            hlContent,
                            style: GoogleFonts.ebGaramond(
                              fontSize: 14.5,
                              fontStyle: FontStyle.italic,
                              color: MarginaliaColors.ink,
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
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  // Likes
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.favorite_border,
                          size: 14, color: MarginaliaColors.inkFaint),
                      const SizedBox(width: 5),
                      Text(
                        '$likes',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: MarginaliaColors.inkFaint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
