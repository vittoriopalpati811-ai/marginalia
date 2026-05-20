import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Posts from people I follow + my own (newest first).
final postsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchPosts();
  } catch (_) {
    return [];
  }
});

/// Legacy feed (jam shared highlights). Kept for compatibility.
final feedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchFeed();
  } catch (_) {
    return [];
  }
});

/// Profiles of users I follow — used for the stories row.
final followingProfilesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  try {
    return await svc.fetchFollowing();
  } catch (_) {
    return [];
  }
});

// ─── FeedTab ──────────────────────────────────────────────────────────────────

class FeedTab extends ConsumerWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(supabaseServiceProvider);
    if (!svc.isAuthenticated) return const _NotLoggedIn();

    final postsAsync    = ref.watch(postsProvider);
    final followingAsync = ref.watch(followingProfilesProvider);

    return RefreshIndicator(
      color: MarginaliaColors.sienna,
      backgroundColor: MarginaliaColors.surface,
      strokeWidth: 1.5,
      onRefresh: () async {
        ref.invalidate(postsProvider);
        ref.invalidate(followingProfilesProvider);
        await ref
            .read(postsProvider.future)
            .catchError((_) => <Map<String, dynamic>>[]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [

          // ── Stories row ──────────────────────────────────────────────────
          followingAsync.when(
            loading: () => const SliverToBoxAdapter(child: SizedBox(height: 88)),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (following) => following.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(child: _StoriesRow(following: following)),
          ),

          // ── Divider after stories ─────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: MarginaliaColors.ruleFaint,
            ),
          ),

          // ── Posts ─────────────────────────────────────────────────────────
          postsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna,
                    strokeWidth: 1.5,
                  ),
                ),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (posts) => posts.isEmpty
                ? SliverToBoxAdapter(child: _EmptyFeed())
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _PostCard(post: posts[i], index: i),
                      childCount: posts.length,
                    ),
                  ),
          ),

          // ── Bottom padding (above nav bar) ───────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

// ─── Stories row ──────────────────────────────────────────────────────────────

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({required this.following});
  final List<Map<String, dynamic>> following;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MarginaliaColors.surface,
      child: SizedBox(
        height: 92,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: following.length,
          itemBuilder: (ctx, i) => _StoryCircle(user: following[i]),
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  const _StoryCircle({required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final name      = user['display_name'] as String? ?? '?';
    final avatarUrl = user['avatar_url']   as String?;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint      = MarginaliaDecorations.bookCoverColor(name);
    final firstName = name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: () {
          final id = user['id'] as String?;
          if (id != null) context.push('/user/$id');
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient ring → white gap → avatar
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [MarginaliaColors.sienna, MarginaliaColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: MarginaliaColors.background,
                ),
                padding: const EdgeInsets.all(1.5),
                child: _AvatarCircle(
                  avatarUrl: avatarUrl,
                  initial: initial,
                  tint: tint,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 58,
              child: Text(
                firstName,
                style: const TextStyle(
                  fontSize: 10,
                  color: MarginaliaColors.inkMuted,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared avatar circle widget ─────────────────────────────────────────────

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.avatarUrl,
    required this.initial,
    required this.tint,
    required this.size,
  });

  final String?  avatarUrl;
  final String   initial;
  final Color    tint;
  final double   size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [tint, MarginaliaColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                avatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Initial(initial: initial, size: size),
              ),
            )
          : _Initial(initial: initial, size: size),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.initial, required this.size});
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initial,
          style: TextStyle(
            color: const Color(0xFFF1EEE7),
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

// ─── Create post sheet ────────────────────────────────────────────────────────

class CreatePostSheet extends ConsumerStatefulWidget {
  const CreatePostSheet({required this.onCreated});
  final VoidCallback onCreated;

  @override
  ConsumerState<CreatePostSheet> createState() => CreatePostSheetState();
}

class CreatePostSheetState extends ConsumerState<CreatePostSheet> {
  final _controller = TextEditingController();
  bool _posting = false;
  Uint8List? _imageBytes;
  String? _imageExt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() {
      _imageBytes = result.files.first.bytes;
      _imageExt   = (result.files.first.extension ?? 'jpg').toLowerCase();
    });
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _imageBytes == null) return;
    setState(() => _posting = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      String? imageUrl;
      if (_imageBytes != null && _imageExt != null) {
        imageUrl = await svc.uploadPostImage(_imageBytes!, _imageExt!);
      }
      await svc.createPost(body: text.isEmpty ? null : text, imageUrl: imageUrl);
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore: $e')));
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final canPost = !_posting &&
        (_controller.text.trim().isNotEmpty || _imageBytes != null);

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nuovo post',
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              FilledButton(
                onPressed: canPost ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: MarginaliaColors.primary,
                  foregroundColor: const Color(0xFFF2F5EA),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _posting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Color(0xFFF2F5EA)),
                      )
                    : const Text('Pubblica',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Text area
          Container(
            decoration: BoxDecoration(
              color: MarginaliaColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MarginaliaColors.rule, width: 1),
            ),
            child: TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 1000,
              style: const TextStyle(
                fontSize: 15,
                color: MarginaliaColors.ink,
                height: 1.55,
              ),
              decoration: const InputDecoration(
                hintText: 'Cosa stai leggendo? Condividi un pensiero…',
                hintStyle: TextStyle(
                  color: MarginaliaColors.inkFaint,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.all(14),
                counterStyle: TextStyle(
                  fontSize: 10,
                  color: MarginaliaColors.inkFaint,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Image preview
          if (_imageBytes != null) ...[
            const SizedBox(height: 10),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6, right: 6,
                  child: GestureDetector(
                    onTap: () => setState(() { _imageBytes = null; _imageExt = null; }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Toolbar: attach photo
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MarginaliaColors.rule),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined, size: 16,
                          color: MarginaliaColors.inkMuted),
                      SizedBox(width: 6),
                      Text('Foto', style: TextStyle(
                        fontSize: 12,
                        color: MarginaliaColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Instagram-style post card ────────────────────────────────────────────────

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({required this.post, required this.index});
  final Map<String, dynamic> post;
  final int index;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  late bool _liked;
  late int  _likesCount;

  @override
  void initState() {
    super.initState();
    _liked      = widget.post['is_liked']    as bool? ?? false;
    _likesCount = widget.post['likes_count'] as int?  ?? 0;
  }

  Future<void> _toggleLike() async {
    final newLiked = !_liked;
    final newCount = newLiked ? _likesCount + 1 : _likesCount - 1;
    setState(() {
      _liked      = newLiked;
      _likesCount = newCount < 0 ? 0 : newCount;
    });
    try {
      await ref
          .read(supabaseServiceProvider)
          .togglePostLike(widget.post['id'] as String, !newLiked);
    } catch (_) {
      setState(() {
        _liked      = !newLiked;
        _likesCount = widget.post['likes_count'] as int? ?? 0;
      });
    }
  }

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

  Color _accentFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };

  @override
  Widget build(BuildContext context) {
    final post        = widget.post;
    final profile     = post['profile']    as Map?;
    final name        = profile?['display_name'] as String? ?? 'Lettore';
    final avatarUrl   = profile?['avatar_url']   as String?;
    final userId      = post['user_id']    as String?;
    final body        = post['body']       as String?;
    final createdAt   = post['created_at'] as String?;
    final imageUrl    = post['image_url']  as String?;
    final highlight   = post['highlights'] as Map?;
    final hlContent   = highlight?['content']       as String?;
    final hlColor     = highlight?['color']         as String?;
    final hlBook      = highlight?['books']         as Map?;
    final hlBookTitle = hlBook?['title']  as String?;
    final hlAuthor    = hlBook?['author'] as String?;
    final initial     = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint        = MarginaliaDecorations.bookCoverColor(name);
    final timeAgo     = _timeAgo(createdAt);
    final accent      = _accentFor(hlColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── User header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: userId != null ? () => context.push('/user/$userId') : null,
                child: _AvatarCircle(
                  avatarUrl: avatarUrl,
                  initial: initial,
                  tint: tint,
                  size: 40,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: userId != null ? () => context.push('/user/$userId') : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.barlow(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: MarginaliaColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(
                          timeAgo,
                          style: GoogleFonts.barlow(
                            fontSize: 11,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Body text ──────────────────────────────────────────────────────
        if (body != null && body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              body,
              style: GoogleFonts.barlow(
                fontSize: 15,
                color: MarginaliaColors.ink,
                height: 1.65,
              ),
            ),
          ),

        // ── Post image (full-width, no horizontal padding) ─────────────────
        if (imageUrl != null && imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Image.network(
              imageUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        // ── Attached highlight quote ────────────────────────────────────────
        if (hlContent != null && hlContent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: _HighlightQuoteCard(
              content: hlContent,
              title: hlBookTitle,
              author: hlAuthor,
              accent: accent,
            ),
          ),

        // ── Action bar ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleLike,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _liked
                        ? MarginaliaColors.primaryFaint
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: _liked
                            ? MarginaliaColors.sienna
                            : MarginaliaColors.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$_likesCount',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _liked
                              ? MarginaliaColors.sienna
                              : MarginaliaColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Bottom separator ───────────────────────────────────────────────
        const Divider(
          height: 0.5,
          thickness: 0.5,
          color: MarginaliaColors.ruleFaint,
        ),
      ],
    )
        .animate(delay: (widget.index * 40).ms)
        .fadeIn(duration: 250.ms, curve: Curves.easeOut)
        .slideY(begin: 0.02, end: 0, duration: 250.ms);
  }
}

// ─── Highlight quote card (attached to post) ─────────────────────────────────

class _HighlightQuoteCard extends StatelessWidget {
  const _HighlightQuoteCard({
    required this.content,
    required this.accent,
    this.title,
    this.author,
  });
  final String  content;
  final Color   accent;
  final String? title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MarginaliaColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MarginaliaColors.ruleFaint,
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title!,
                    style: MarginaliaTextStyles.sectionTitle.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.2,
                      color: MarginaliaColors.inkMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (author != null && author!.isNotEmpty)
                  Text(
                    author!.toUpperCase(),
                    style: MarginaliaTextStyles.bookAuthor.copyWith(
                      fontSize: 8.5,
                      color: MarginaliaColors.inkFaint,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Container(height: 0.5, color: MarginaliaColors.ruleFaint),
            const SizedBox(height: 8),
          ],
          Text(
            content.length > 240
                ? '${content.substring(0, 240)}…'
                : content,
            style: MarginaliaTextStyles.highlightBodySmall.copyWith(
              fontSize: 13.5,
              height: 1.75,
            ),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"',
            style: GoogleFonts.ebGaramond(
              fontSize: 64,
              color: MarginaliaColors.ruleFaint,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Il feed è vuoto',
            style: GoogleFonts.ebGaramond(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Segui altri lettori dalla scheda Amici\nper vedere i loro post qui.',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              color: MarginaliaColors.inkMuted,
              fontSize: 13,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Not logged in ────────────────────────────────────────────────────────────

class _NotLoggedIn extends StatelessWidget {
  const _NotLoggedIn();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 32, color: MarginaliaColors.siennaLight),
            ),
            const SizedBox(height: 20),
            const Text(
              'Accedi per vedere il feed',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Il feed sociale richiede un account Marginalia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/auth'),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Accedi'),
            ),
          ],
        ),
      ),
    );
  }
}
