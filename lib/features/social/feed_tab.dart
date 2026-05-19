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

/// Posts from people I follow + my own.
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

/// Shared highlights from people I follow (legacy feed).
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

// ─── FeedTab ──────────────────────────────────────────────────────────────────

class FeedTab extends ConsumerWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(supabaseServiceProvider);
    if (!svc.isAuthenticated) return _NotLoggedIn();

    final postsAsync = ref.watch(postsProvider);
    final feedAsync  = ref.watch(feedProvider);

    return CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [

          // ── Post section header ───────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('POST', style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: MarginaliaColors.inkFaint,
                    letterSpacing: 0.8,
                  )),
                  SizedBox(width: 12),
                  Expanded(child: Divider(color: MarginaliaColors.ruleFaint, height: 1)),
                ],
              ),
            ),
          ),

          // ── Posts list ────────────────────────────────────────────────────
          postsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna, strokeWidth: 1.5)),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (posts) => posts.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        'Ancora nessun post. Sii il primo a scrivere qualcosa!',
                        style: TextStyle(
                          fontSize: 13,
                          color: MarginaliaColors.inkMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _PostCard(post: posts[i], index: i),
                        childCount: posts.length,
                      ),
                    ),
                  ),
          ),

          // ── Divider between posts and shared highlights ────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Text('HIGHLIGHT CONDIVISI',
                    style: MarginaliaTextStyles.sectionTitle.copyWith(
                      fontSize: 9,
                      letterSpacing: 2.5,
                      color: MarginaliaColors.inkFaint,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: MarginaliaColors.ruleFaint, height: 1)),
                ],
              ),
            ),
          ),

          // ── Legacy shared-highlights feed ─────────────────────────────────
          feedAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna, strokeWidth: 1.5)),
              ),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (items) => items.isEmpty
                ? SliverToBoxAdapter(child: _EmptyFeed())
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _FeedCard(item: items[i], index: i),
                        childCount: items.length,
                      ),
                    ),
                  ),
          ),
        ],
      );
  }
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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

          // Image preview (if picked)
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

// ─── Post card ────────────────────────────────────────────────────────────────

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
    _liked      = widget.post['is_liked'] as bool? ?? false;
    _likesCount = widget.post['likes_count'] as int? ?? 0;
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
      // Revert optimistic update on error
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
    if (diff.inMinutes < 1) return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
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
    final profile     = post['profile'] as Map?;
    final name        = profile?['display_name'] as String? ?? 'Lettore';
    final avatarUrl   = profile?['avatar_url'] as String?;
    final userId      = post['user_id'] as String?;
    final body        = post['body'] as String?;
    final createdAt   = post['created_at'] as String?;
    final imageUrl    = post['image_url'] as String?;
    final highlight   = post['highlights'] as Map?;
    final hlContent   = highlight?['content'] as String?;
    final hlColor     = highlight?['color'] as String?;
    final hlBook      = highlight?['books'] as Map?;
    final hlBookTitle = hlBook?['title'] as String?;
    final hlAuthor    = hlBook?['author'] as String?;
    final initial     = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarTint  = MarginaliaDecorations.bookCoverColor(name);
    final timeAgo     = _timeAgo(createdAt);
    final accent      = _accentFor(hlColor);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── User header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: userId != null
                      ? () => context.push('/user/$userId')
                      : null,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [avatarTint, MarginaliaColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? ClipOval(
                            child: Image.network(avatarUrl,
                                fit: BoxFit.cover,
                                width: 38,
                                height: 38,
                                errorBuilder: (_, __, ___) => Center(
                                    child: Text(initial,
                                        style: const TextStyle(
                                          color: Color(0xFFF1EEE7),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        )))),
                          )
                        : Center(
                            child: Text(initial,
                                style: const TextStyle(
                                  color: Color(0xFFF1EEE7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                  ),
                ),
                const SizedBox(width: 10),

                // Name + time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: userId != null
                            ? () => context.push('/user/$userId')
                            : null,
                        child: Text(
                          name,
                          style: GoogleFonts.barlow(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.ink,
                            letterSpacing: -0.1,
                          ),
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
              ],
            ),
          ),

          // ── Post body ──────────────────────────────────────────────────────
          if (body != null && body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                body,
                style: GoogleFonts.barlow(
                  fontSize: 14.5,
                  color: MarginaliaColors.ink,
                  height: 1.6,
                ),
              ),
            ),

          // ── Post image ────────────────────────────────────────────────────
          if (imageUrl != null && imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // ── Attached highlight ─────────────────────────────────────────────
          if (hlContent != null && hlContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
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
                    // Book attribution row
                    if (hlBookTitle != null && hlBookTitle.isNotEmpty) ...[
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hlBookTitle,
                              style: MarginaliaTextStyles.sectionTitle.copyWith(
                                fontSize: 9,
                                letterSpacing: 1.2,
                                color: MarginaliaColors.inkMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hlAuthor != null && hlAuthor.isNotEmpty)
                            Text(
                              hlAuthor.toUpperCase(),
                              style: MarginaliaTextStyles.bookAuthor.copyWith(
                                fontSize: 8.5,
                                color: MarginaliaColors.inkFaint,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(height: 0.6, color: MarginaliaColors.ruleFaint),
                      const SizedBox(height: 8),
                    ],
                    // Quote text — EB Garamond italic
                    Text(
                      hlContent.length > 240
                          ? '${hlContent.substring(0, 240)}…'
                          : hlContent,
                      style: MarginaliaTextStyles.highlightBodySmall.copyWith(
                        fontSize: 13.5,
                        height: 1.75,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

          // ── Like button ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleLike,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
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
                          _liked
                              ? Icons.favorite
                              : Icons.favorite_border,
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
        ],
      ),
    )
        .animate(delay: (widget.index * 40).ms)
        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 280.ms);
  }
}

// ─── Legacy shared-highlight feed card ───────────────────────────────────────

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, required this.index});
  final Map<String, dynamic> item;
  final int index;

  String? get _content {
    try { return (item['highlights'] as Map?)?['content'] as String?; }
    catch (_) { return null; }
  }

  String? get _bookTitle {
    try { return ((item['highlights'] as Map?)?['books'] as Map?)?['title'] as String?; }
    catch (_) { return null; }
  }

  String? get _bookAuthor {
    try { return ((item['highlights'] as Map?)?['books'] as Map?)?['author'] as String?; }
    catch (_) { return null; }
  }

  String? get _kindleColor {
    try { return (item['highlights'] as Map?)?['color'] as String?; }
    catch (_) { return null; }
  }

  String? get _sharedBy => item['shared_by'] as String?;

  String? get _userName {
    try { return (item['profile'] as Map?)?['display_name'] as String? ?? 'Utente'; }
    catch (_) { return null; }
  }

  String? get _jamTitle {
    try { return (item['jams'] as Map?)?['title'] as String?; }
    catch (_) { return null; }
  }

  String? get _jamId {
    try { return (item['jams'] as Map?)?['id'] as String?; }
    catch (_) { return null; }
  }

  String? get _sharedAt => item['shared_at'] as String?;

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m fa';
    if (diff.inHours < 24) return '${diff.inHours}h fa';
    if (diff.inDays < 7) return '${diff.inDays}g fa';
    return '${(diff.inDays / 7).round()}w fa';
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
    final name      = _userName ?? 'Utente';
    final content   = _content ?? '';
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = MarginaliaDecorations.bookCoverColor(name);
    final accent    = _accentFor(_kindleColor);
    final timeAgo   = _timeAgo(_sharedAt);
    final jamTitle  = _jamTitle;
    final jamId     = _jamId;
    final bookTitle = _bookTitle;
    final bookAuthor = _bookAuthor;
    final userId    = _sharedBy;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: MarginaliaDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: userId != null
                      ? () => context.push('/user/$userId')
                      : null,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [avatarColor, MarginaliaColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                            color: Color(0xFFF1EEE7),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: userId != null
                            ? () => context.push('/user/$userId')
                            : null,
                        child: Text(name,
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: MarginaliaColors.ink,
                              letterSpacing: -0.1,
                            )),
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(timeAgo,
                            style: GoogleFonts.barlow(
                              fontSize: 11,
                              color: MarginaliaColors.inkFaint,
                            )),
                    ],
                  ),
                ),
                if (jamTitle != null)
                  GestureDetector(
                    onTap: jamId != null
                        ? () => context.push(
                            '/jam/$jamId?name=${Uri.encodeComponent(jamTitle)}')
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.primaryFaint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.group_outlined,
                              size: 10, color: MarginaliaColors.primary),
                          const SizedBox(width: 4),
                          Text(jamTitle,
                              style: GoogleFonts.barlowCondensed(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.primary,
                                letterSpacing: 0.5,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Highlight card
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Container(
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
                  if (bookTitle != null && bookTitle.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            bookTitle,
                            style: MarginaliaTextStyles.sectionTitle.copyWith(
                              fontSize: 9,
                              letterSpacing: 1.2,
                              color: MarginaliaColors.inkMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (bookAuthor != null && bookAuthor.isNotEmpty)
                          Text(
                            bookAuthor.toUpperCase(),
                            style: MarginaliaTextStyles.bookAuthor.copyWith(
                              fontSize: 8.5,
                              color: MarginaliaColors.inkFaint,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(height: 0.6, color: MarginaliaColors.ruleFaint),
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
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 280.ms);
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 16, 40, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.dynamic_feed_outlined,
                  size: 26, color: MarginaliaColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun highlight condiviso',
              style: GoogleFonts.barlow(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Segui altri lettori dalla scheda Amici\nper vedere i loro highlight qui.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                fontSize: 13,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Not logged in state ──────────────────────────────────────────────────────

class _NotLoggedIn extends StatelessWidget {
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
