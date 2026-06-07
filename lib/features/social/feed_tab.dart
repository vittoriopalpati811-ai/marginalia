import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/content_filter_service.dart';
import '../../core/l10n/l10n_extension.dart';
import '../messages/giphy_picker.dart';
import 'report_sheet.dart';
import 'share_post_sheet.dart';

// ─── Content-filter helpers ──────────────────────────────────────────────────

/// Maps a flagged [ContentCategory] to its short localized label, used both in
/// the "blocked at creation" snackbar and (generically) for logging.
String _contentCategoryLabel(BuildContext context, ContentCategory category) {
  final l10n = context.l10n;
  return switch (category) {
    ContentCategory.violence => l10n.contentCategoryViolence,
    ContentCategory.spam => l10n.contentCategorySpam,
    ContentCategory.scam => l10n.contentCategoryScam,
    ContentCategory.sexual => l10n.contentCategorySexual,
  };
}

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

/// A single post by id — used by [PostDetailScreen] (deep `/post/:id` route +
/// profile post taps). Returns null when the post can't be loaded / found.
final singlePostProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, postId) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return null;
  try {
    return await svc.fetchPost(postId);
  } catch (_) {
    return null;
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
                      // Stable key per post — critical after a delete or
                      // reorder: without it, _PostCardState (like/count
                      // counters) would leak onto the post that slides
                      // into the same index. findChildIndexCallback below
                      // lets Flutter match the surviving cards by id so
                      // the deleted one is the only widget unmounted.
                      (ctx, i) => _PostCard(
                        key: ValueKey('post-${posts[i]['id']}'),
                        post: posts[i],
                        index: i,
                      ),
                      childCount: posts.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final id = key.value.replaceFirst('post-', '');
                        final idx = posts.indexWhere((p) => p['id'] == id);
                        return idx >= 0 ? idx : null;
                      },
                    ),
                  ),
          ),

          // ── Bottom padding (above nav bar) ───────────────────────────────
          // The shell (_ScaffoldWithNav) augments MediaQuery.padding.bottom
          // with its nav inset (56 + safe-area-bottom) so route content can
          // clear the floating bottom navbar. The CustomScrollView does NOT
          // automatically consume that inset, so without this the bottom-most
          // post stays hidden behind the bar. Consume it here (plus a
          // comfortable 20px) so the last post fully scrolls into view above
          // the navbar.
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 20,
            ),
          ),
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
        behavior: HitTestBehavior.opaque,
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

  // ── @mention autocomplete state ──────────────────────────────────────────
  // Matches the active "@token" immediately before the caret. Allows letters,
  // digits and underscore (usernames), up to 30 chars.
  static final RegExp _mentionTrigger = RegExp(r'(?:^|\s)@(\w{1,30})$');
  List<Map<String, dynamic>> _mentionSuggestions = [];
  bool _showMentions = false;
  // username (lowercase) -> user id, for the users the author actually tagged.
  final Map<String, String> _taggedUsernameToId = {};
  Timer? _mentionDebounce;

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Called on every keystroke. Detects an active "@token" before the caret and
  /// (debounced) queries [searchUsers] to populate the suggestion list. Hides
  /// the list when there is no active token.
  void _onComposerChanged(String text) {
    setState(() {}); // keep the publish button / counter in sync as before.

    final selection = _controller.selection;
    final caret = selection.baseOffset;
    if (caret < 0 || caret > text.length) {
      _hideMentions();
      return;
    }
    final beforeCaret = text.substring(0, caret);
    final match = _mentionTrigger.firstMatch(beforeCaret);
    if (match == null) {
      _hideMentions();
      return;
    }
    final token = match.group(1) ?? '';
    if (token.isEmpty) {
      _hideMentions();
      return;
    }

    // Debounce the network search so we do not hammer the backend per keystroke.
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results =
            await ref.read(supabaseServiceProvider).searchUsers(token);
        if (!mounted) return;
        setState(() {
          _mentionSuggestions = results;
          _showMentions = results.isNotEmpty;
        });
      } catch (_) {
        if (!mounted) return;
        _hideMentions();
      }
    });
  }

  void _hideMentions() {
    if (!_showMentions && _mentionSuggestions.isEmpty) return;
    setState(() {
      _showMentions = false;
      _mentionSuggestions = [];
    });
  }

  /// Replaces the active "@token" before the caret with "@<username> ",
  /// records the username -> id mapping, and hides the suggestion list.
  void _applyMention(Map<String, dynamic> user) {
    final id = user['id'] as String?;
    final username = user['username'] as String?;
    if (id == null || username == null || username.isEmpty) {
      _hideMentions();
      return;
    }

    final text = _controller.text;
    final caret = _controller.selection.baseOffset;
    final safeCaret = (caret < 0 || caret > text.length) ? text.length : caret;
    final beforeCaret = text.substring(0, safeCaret);
    final afterCaret = text.substring(safeCaret);
    final match = _mentionTrigger.firstMatch(beforeCaret);
    if (match == null) {
      _hideMentions();
      return;
    }

    // match.start may include the leading whitespace captured by `(?:^|\s)`;
    // keep that separator and replace only the "@token" portion.
    final atIndex = beforeCaret.lastIndexOf('@', safeCaret);
    final replaced = '${text.substring(0, atIndex)}@$username $afterCaret';
    final newCaret = atIndex + username.length + 2; // '@' + username + ' '

    _taggedUsernameToId[username.toLowerCase()] = id;
    _controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    setState(() {
      _showMentions = false;
      _mentionSuggestions = [];
    });
  }

  /// Scans the final composed text for "@username" tokens and maps each to a
  /// user id via [_taggedUsernameToId]. Unknown tokens are ignored. De-duped.
  List<String> _resolveTaggedIds(String text) {
    final ids = <String>{};
    for (final m in RegExp(r'@(\w+)').allMatches(text)) {
      final username = (m.group(1) ?? '').toLowerCase();
      final id = _taggedUsernameToId[username];
      if (id != null) ids.add(id);
    }
    return ids.toList();
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

  void _showSuccessOverlay(BuildContext ctx) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlowerWordsOverlay(
        onDone: () => entry.remove(),
      ),
    );
    Overlay.of(ctx).insert(entry);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _imageBytes == null) return;

    // First-line keyword filter: refuse obviously objectionable text BEFORE we
    // show the optimistic success overlay or hit the network, and let the user
    // edit. (Image moderation is server-side / out of scope; this only checks
    // the typed text.)
    final inspection = contentFilter.inspect(text);
    if (inspection.flagged) {
      final category = inspection.category!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.contentBlockedMessage(
              _contentCategoryLabel(context, category),
            ),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Drop the keyboard immediately so it doesn't hover over the success
    // animation or linger on the feed after the sheet closes.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _posting = true);

    // Capture context before async gap
    final ctx = context;

    // Show the success overlay immediately (optimistic)
    _showSuccessOverlay(ctx);

    // Close the sheet after the animation duration
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.of(ctx).pop();
    });

    try {
      final svc = ref.read(supabaseServiceProvider);
      String? imageUrl;
      if (_imageBytes != null && _imageExt != null) {
        imageUrl = await svc.uploadPostImage(_imageBytes!, _imageExt!);
      }
      final taggedIds = _resolveTaggedIds(text);
      await svc.createPost(
        body: text.isEmpty ? null : text,
        imageUrl: imageUrl,
        mentions: taggedIds,
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bottom = keyboard + media.padding.bottom;
    // Cap the sheet to the space below the status bar / notch so the header
    // (and its publish button) can never slide under the system clock when
    // isScrollControlled lets the sheet grow tall with the keyboard up.
    // Leave a comfortable ~52px gap below the top safe area so nothing is
    // clipped at the top, and subtract the keyboard inset so the whole sheet
    // (incl. the text box) stays fully visible above the keyboard.
    final topGap = media.padding.top + 52;
    final maxSheetHeight =
        (media.size.height - topGap - keyboard).clamp(220.0, media.size.height);
    final canPost = !_posting &&
        (_controller.text.trim().isNotEmpty || _imageBytes != null);

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
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
                  context.l10n.feedNewPostTitle,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (_posting)
                const SizedBox(
                  width: 44, height: 44,
                  child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna,
                    strokeWidth: 2,
                  ),
                )
              else
                _HoldToPublishButton(
                  enabled: canPost,
                  onComplete: _submit,
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Text area. A bounded maxHeight keeps the box fully visible (it
          // scrolls internally past ~6 lines) so it is never clipped at the
          // bottom, even with the keyboard up.
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
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
              // Return key dismisses the keyboard instead of inserting a
              // newline, per the founder's request ("dopo aver premuto invio").
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              style: const TextStyle(
                fontSize: 15,
                color: MarginaliaColors.ink,
                height: 1.55,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.feedComposerHint,
                hintStyle: const TextStyle(
                  color: MarginaliaColors.inkFaint,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                counterStyle: const TextStyle(
                  fontSize: 10,
                  color: MarginaliaColors.inkFaint,
                ),
              ),
              onChanged: _onComposerChanged,
            ),
          ),

          // ── @mention suggestions ──────────────────────────────────────────
          // Up to 6 matching users, shown directly under the text box while an
          // active "@token" sits before the caret. Tapping inserts the handle.
          if (_showMentions && _mentionSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: MarginaliaColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MarginaliaColors.rule, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final user in _mentionSuggestions.take(6))
                    _MentionSuggestionRow(
                      user: user,
                      onTap: () => _applyMention(user),
                    ),
                ],
              ),
            ),
          ],

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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_outlined, size: 16,
                          color: MarginaliaColors.inkMuted),
                      const SizedBox(width: 6),
                      Text(context.l10n.feedPhoto, style: const TextStyle(
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
      ),
    );
  }
}

// ─── @mention suggestion row ──────────────────────────────────────────────────

/// A single tappable row in the composer's @mention autocomplete list:
/// avatar (or initial) + display name + "@username".
class _MentionSuggestionRow extends StatelessWidget {
  const _MentionSuggestionRow({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayName = user['display_name'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    final avatarUrl = user['avatar_url'] as String?;
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final tint = MarginaliaDecorations.bookCoverColor(displayName);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _AvatarCircle(
              avatarUrl: avatarUrl,
              initial: initial,
              tint: tint,
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (displayName.isNotEmpty)
                    Text(
                      displayName,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: MarginaliaColors.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        color: MarginaliaColors.inkFaint,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Post success: multilingual word-flowers animation ────────────────────────

const _kPostWords = [
  'Posted!',
  'Publié!',
  'Published!',
  'Publicado!',
  '投稿済み!',
];

class _FlowerWordsOverlay extends StatefulWidget {
  const _FlowerWordsOverlay({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_FlowerWordsOverlay> createState() => _FlowerWordsOverlayState();
}

class _FlowerWordsOverlayState extends State<_FlowerWordsOverlay>
    with TickerProviderStateMixin {
  final List<_WordParticle> _particles = [];
  late final AnimationController _master;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Generate 15 particles — the 5 words repeated/shuffled with varied params
    final rng = math.Random(42);
    final words = [..._kPostWords, ..._kPostWords, ..._kPostWords];
    words.shuffle(rng);
    for (int i = 0; i < 15; i++) {
      _particles.add(_WordParticle(
        word:       words[i % words.length],
        startDelay: rng.nextDouble() * 0.35,          // 0–35% into animation
        dx:         (rng.nextDouble() - 0.5) * 1.8,   // horizontal drift –0.9..+0.9 of screen width fraction
        dy:         -(0.35 + rng.nextDouble() * 0.45), // rise 35–80% of screen height
        rotation:   (rng.nextDouble() - 0.5) * 0.5,   // ±0.25 rad
        fontSize:   11.0 + rng.nextDouble() * 5.0,    // 11–16px
        color:      _kWordColors[i % _kWordColors.length],
      ));
    }

    _master.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), widget.onDone);
    });
  }

  static const _kWordColors = [
    Color(0xFF3A6624), // deep matcha
    Color(0xFF4A7A35), // matcha
    Color(0xFF6A9E52), // matcha light
    Color(0xFF2D5A3D), // dark forest
    Color(0xFF5C8C48), // mid matcha
  ];

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _master,
          builder: (_, __) {
            return Stack(
              children: _particles.map((p) {
                // Normalize time within this particle's window
                final start = p.startDelay;
                final t = ((_master.value - start) / (1.0 - start)).clamp(0.0, 1.0);
                if (t <= 0) return const SizedBox.shrink();

                final rise   = Curves.easeOut.transform(t);
                final fade   = t < 0.7 ? 1.0 : 1.0 - ((t - 0.7) / 0.3);
                final scale  = 0.4 + 0.6 * Curves.elasticOut.transform(math.min(t * 2, 1.0));

                // Start near center-bottom of screen
                final baseX = size.width  * 0.5 + p.dx * size.width  * 0.5;
                final baseY = size.height * 0.78 + p.dy * size.height * rise;

                return Positioned(
                  left: baseX,
                  top:  baseY,
                  child: Transform.rotate(
                    angle: p.rotation * rise,
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: Text(
                          p.word,
                          style: TextStyle(
                            fontSize:   p.fontSize,
                            fontWeight: FontWeight.w700,
                            color:      p.color,
                            letterSpacing: -0.2,
                            shadows: const [
                              Shadow(
                                color:  Color(0x40000000),
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _WordParticle {
  const _WordParticle({
    required this.word,
    required this.startDelay,
    required this.dx,
    required this.dy,
    required this.rotation,
    required this.fontSize,
    required this.color,
  });
  final String word;
  final double startDelay;
  final double dx;
  final double dy;
  final double rotation;
  final double fontSize;
  final Color color;
}

// ─── Hold-to-publish button (Liftoff-style) ──────────────────────────────────
//
// Long-press 1.8s → matcha circle ORIGINATES at the button position and
// expands radially to fill the screen. Mid-hold the message changes to
// "Continua a tenere!". When full, a checkmark + "Postato!" replaces it
// and the post is sent. Release early → circle shrinks back to the button.

class _HoldToPublishButton extends StatefulWidget {
  const _HoldToPublishButton({required this.enabled, required this.onComplete});
  final bool         enabled;
  final VoidCallback onComplete;

  @override
  State<_HoldToPublishButton> createState() => _HoldToPublishButtonState();
}

class _HoldToPublishButtonState extends State<_HoldToPublishButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlay;
  bool _holding   = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addStatusListener(_onAnimStatus);
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completed) {
      _completed = true;
      // Brief "Postato!" display, then submit
      Future.delayed(const Duration(milliseconds: 900), () {
        _removeOverlay();
        widget.onComplete();
      });
    } else if (status == AnimationStatus.dismissed) {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() { _holding = false; _completed = false; });
  }

  /// Returns the button's center position in global screen coordinates.
  Offset _buttonCenter() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      final size = MediaQuery.of(context).size;
      return Offset(size.width / 2, size.height / 2);
    }
    final pos = box.localToGlobal(Offset.zero);
    return pos + Offset(box.size.width / 2, box.size.height / 2);
  }

  void _onHoldStart() {
    if (!widget.enabled || _holding) return;
    setState(() => _holding = true);

    final origin = _buttonCenter();
    final l10n   = context.l10n;

    _overlay = OverlayEntry(
      builder: (_) => _HoldCircleOverlay(
        controller:    _ctrl,
        origin:        origin,
        keepHolding:   l10n.feedKeepHolding,
        published:     l10n.feedPostPublished,
      ),
    );
    Overlay.of(context).insert(_overlay!);
    _ctrl.forward(from: 0);
  }

  void _onHoldEnd() {
    if (!_holding || _completed) return;
    // Released early → shrink back
    _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onAnimStatus);
    _overlay?.remove();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _buttonKey,
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd:   (_) => _onHoldEnd(),
      onLongPressCancel:    _onHoldEnd,
      // Hold-to-publish ONLY (founder's choice): a plain tap just reminds you to
      // hold; the liftoff animation + actual publish happen on long-press.
      onTap: widget.enabled
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.feedHoldToPublishToast),
                  duration: const Duration(seconds: 1),
                ),
              )
          : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _holding ? 0.92 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: widget.enabled
                ? (_holding
                    ? MarginaliaColors.sienna.withAlpha(180)
                    : MarginaliaColors.sienna)
                : MarginaliaColors.rule,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            context.l10n.feedPublishLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: widget.enabled
                  ? const Color(0xFFF2F5EA)
                  : MarginaliaColors.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Full-screen hold circle overlay (Liftoff style) ─────────────────────────
//
// The matcha circle originates AT THE BUTTON (origin) and grows to cover
// the whole screen. Three timed text phases:
//   0–28%   → no text (just the growing circle)
//   28–78%  → "Continua a tenere!" centered, fades in/out
//   78–100% → checkmark + "Postato!" replaces it

class _HoldCircleOverlay extends StatelessWidget {
  const _HoldCircleOverlay({
    required this.controller,
    required this.origin,
    required this.keepHolding,
    required this.published,
  });

  final AnimationController controller;
  final Offset              origin;
  final String              keepHolding;
  final String              published;

  static const _matcha = Color(0xFF4A7A35);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Radius needed to reach the furthest screen corner from `origin`
    final dx1 = origin.dx, dx2 = size.width  - origin.dx;
    final dy1 = origin.dy, dy2 = size.height - origin.dy;
    final maxX = dx1 > dx2 ? dx1 : dx2;
    final maxY = dy1 > dy2 ? dy1 : dy2;
    final maxR = math.sqrt(maxX * maxX + maxY * maxY) * 1.05; // small overshoot

    return Material(
      color: Colors.transparent,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            // Smoother growth than elastic — fast at start, settles at end
            final expand = CurvedAnimation(
              parent: controller,
              curve: const Interval(0.0, 0.92, curve: Curves.easeOutCubic),
            );
            final keepFade = _bumpInterval(controller.value, 0.28, 0.55, 0.78);
            final doneFade = CurvedAnimation(
              parent: controller,
              curve: const Interval(0.80, 1.0, curve: Curves.easeOut),
            ).value;

            final r = expand.value * maxR;

            return Stack(
              children: [
                // Expanding matcha circle, anchored at button origin
                Positioned(
                  left: origin.dx - r,
                  top:  origin.dy - r,
                  width:  r * 2,
                  height: r * 2,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: _matcha,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Mid-hold encouragement
                if (keepFade > 0.01)
                  Center(
                    child: Opacity(
                      opacity: keepFade,
                      child: Text(
                        keepHolding,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),

                // Final confirmation
                if (doneFade > 0.01)
                  Center(
                    child: Opacity(
                      opacity: doneFade,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            published,
                            style: GoogleFonts.ebGaramond(
                              fontSize: 36,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Returns a triangular envelope: 0 at `start`, 1 at `peak`, 0 at `end`.
  /// Used to fade text in and back out within a single animation phase.
  double _bumpInterval(double t, double start, double peak, double end) {
    if (t <= start || t >= end) return 0;
    if (t <= peak) return ((t - start) / (peak - start)).clamp(0.0, 1.0);
    return (1 - (t - peak) / (end - peak)).clamp(0.0, 1.0);
  }
}

// ─── Instagram-style post card ────────────────────────────────────────────────

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({super.key, required this.post, required this.index});
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

  Future<void> _showPostMenu(BuildContext context) async {
    final svc = ref.read(supabaseServiceProvider);
    final postId = widget.post['id'] as String?;
    final postUserId = widget.post['user_id'] as String?;
    final isOwner = svc.userId != null && svc.userId == postUserId;
    final body = widget.post['body'] as String? ?? '';

    // Capture messenger + l10n ONCE, here, while this card's context is
    // guaranteed mounted. Every menu action below reuses these instead of
    // touching `context` after an await — so a rebuild that unmounts this
    // card (e.g. after a delete invalidates postsProvider) can never make a
    // callback throw and leave an orphaned modal barrier ("tutto nero").
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    if (!isOwner) {
      // Non-owner: Report (real backend) + Block user.
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PostMenuSheet(
          items: [
            _MenuAction(
              icon: Icons.flag_outlined,
              label: l10n.feedReport,
              color: MarginaliaColors.inkMuted,
              onTap: () async {
                Navigator.pop(ctx);
                if (postId == null) return;
                await showReportSheet(
                  context,
                  ref,
                  contentType: 'post',
                  contentId: postId,
                  reportedUserId: postUserId,
                );
              },
            ),
            _MenuAction(
              icon: Icons.block,
              label: l10n.blockUser,
              color: const Color(0xFFB54848),
              onTap: () async {
                Navigator.pop(ctx);
                if (postUserId == null) return;
                final confirmed = await confirmBlockUser(context);
                if (!confirmed) return;
                try {
                  await svc.blockUser(postUserId);
                  // Drop the blocked author's posts from the feed/timeline.
                  ref.invalidate(postsProvider);
                  ref.invalidate(feedProvider);
                  ref.invalidate(followingProfilesProvider);
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.userBlocked)),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.feedErrorPrefix(e.toString()))),
                  );
                }
              },
            ),
          ],
        ),
      );
      return;
    }

    // Owner: edit + delete
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PostMenuSheet(
        items: [
          _MenuAction(
            icon: Icons.edit_outlined,
            label: context.l10n.feedEdit,
            color: MarginaliaColors.ink,
            onTap: () async {
              Navigator.pop(ctx);
              if (postId == null) return;
              await _showEditDialog(context, postId, body);
            },
          ),
          _MenuAction(
            icon: Icons.delete_outline,
            label: context.l10n.feedDeletePost,
            color: const Color(0xFFDC2626),
            onTap: () async {
              Navigator.pop(ctx);
              if (postId == null) return;
              // messenger + l10n were captured at the top of _showPostMenu,
              // while this card was guaranteed mounted — safe to use across
              // the awaits below even after the card unmounts.
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(l10n.feedDeleteConfirmTitle),
                  content: Text(l10n.feedDeleteConfirmBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      child: Text(l10n.feedDeleteAction),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                await svc.deletePost(postId);
                // Provider-driven removal: refetch the list and let the
                // SliverChildBuilderDelegate's ValueKey + findChildIndexCallback
                // unmount this card naturally. No local `_deleted` flag —
                // an optimistic flag combined with the rebuild can leave
                // a zombie state and render a blank screen.
                ref.invalidate(postsProvider);
              } catch (e) {
                // Use the pre-captured messenger; `context` may already be
                // deactivated here.
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.feedErrorPrefix(e.toString()))),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, String postId, String currentBody) async {
    final ctrl = TextEditingController(text: currentBody);
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(context.l10n.feedEdit),
          content: TextField(
            controller: ctrl,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: context.l10n.feedWritePost,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final newBody = ctrl.text.trim();
                      if (newBody.isEmpty) return;
                      setS(() => saving = true);
                      try {
                        await ref.read(supabaseServiceProvider).updatePost(postId, newBody);
                        if (ctx.mounted) Navigator.pop(ctx);
                        ref.invalidate(postsProvider);
                      } catch (e) {
                        setS(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(context.l10n.feedErrorPrefix(e.toString()))));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.feedSaveAction),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
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

  Future<void> _openComments(BuildContext context) async {
    final postId = widget.post['id'] as String?;
    if (postId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Render above the shell's floating bottom navbar so the comment input
      // field is fully tappable above the keyboard.
      useRootNavigator: true,
      // Pass the post's owner id so the comments sheet can let the post owner
      // moderate (delete) ANY comment on their post, not just their own.
      builder: (_) => _CommentsSheet(
        postId: postId,
        postOwnerId: widget.post['user_id'] as String?,
      ),
    );
  }

  Future<void> _sharePost(BuildContext context) async {
    final postId = widget.post['id'] as String?;
    if (postId == null) return;
    // First ~80 chars of the body become the message preview that rides along
    // with the shared-post card in the chat.
    final body = (widget.post['body'] as String? ?? '').trim();
    final preview = body.isEmpty
        ? null
        : (body.length > 80 ? '${body.substring(0, 80)}…' : body);
    await showSharePostSheet(context, postId: postId, previewText: preview);
  }

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

  Color _accentFor(String? c) => switch (c) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };

  @override
  Widget build(BuildContext context) {
    final post          = widget.post;
    final profile       = post['profile']    as Map?;
    final name          = profile?['display_name']         as String? ?? 'Reader';
    final avatarUrl     = profile?['avatar_url']           as String?;
    final readingTitle  = profile?['currently_reading_title'] as String?;
    final userId        = post['user_id']    as String?;
    final body          = post['body']       as String?;
    // id -> {username, display_name} for every user tagged in this post; used
    // to render tappable @username spans. May be absent on older cached rows.
    final mentionedProfiles =
        (post['mentioned_profiles'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final createdAt     = post['created_at'] as String?;
    final imageUrl      = post['image_url']  as String?;
    final highlight     = post['highlights'] as Map?;
    final hlContent     = highlight?['content']       as String?;
    final hlColor       = highlight?['color']         as String?;
    final hlBook        = highlight?['books']         as Map?;
    final hlBookTitle   = hlBook?['title']  as String?;
    final hlAuthor      = hlBook?['author'] as String?;
    final initial       = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint          = MarginaliaDecorations.bookCoverColor(name);
    final timeAgo       = _timeAgo(context, createdAt);
    final accent        = _accentFor(hlColor);

    // Current user check for menu
    final currentUserId = ref.read(supabaseServiceProvider).userId;
    final isOwner = currentUserId != null && currentUserId == userId;

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── User header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  behavior: HitTestBehavior.opaque,
                  onTap: userId != null ? () => context.push('/user/$userId') : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name row: username + "· leggendo X"
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: MarginaliaColors.ink,
                                letterSpacing: -0.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (readingTitle != null && readingTitle.isNotEmpty) ...[
                            Text(
                              ' · ',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                color: MarginaliaColors.inkFaint,
                              ),
                            ),
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 10,
                              color: MarginaliaColors.primaryDark,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                readingTitle,
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: MarginaliaColors.primaryDark,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (timeAgo.isNotEmpty)
                        Text(
                          timeAgo,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 3-dot menu — visible on EVERY post so reporting (non-owner) and
              // edit/delete (owner) are always one tap away. 40×40 tap target,
              // subtle inkMuted glyph (20px), no layout shift. `_showPostMenu`
              // already branches owner → edit/delete vs non-owner → report+block.
              Semantics(
                button: true,
                label: context.l10n.feedReport,
                child: GestureDetector(
                  onTap: () => _showPostMenu(context),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Icon(
                        PhosphorIconsRegular.dotsThreeOutline,
                        size: 20,
                        color: MarginaliaColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Body text ──────────────────────────────────────────────────────
        if (body != null && body.isNotEmpty)
          Padding(
            // Indented to line up with the username (avatar stays in the gutter).
            padding: const EdgeInsets.fromLTRB(64, 8, 16, 0),
            child: _GatedText(
              text: body,
              alreadyOwn: isOwner,
              child: _MentionText(
                body: body,
                mentionedProfiles: mentionedProfiles,
              ),
            ),
          ),

        // ── Post image — smaller, rounded box, indented under the username ──
        if (imageUrl != null && imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 10, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 180,
                        color: MarginaliaColors.surfaceElevated,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: MarginaliaColors.sienna,
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  height: 64,
                  color: MarginaliaColors.surfaceElevated,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined,
                            size: 18, color: MarginaliaColors.inkFaint),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.feedImageUnavailable,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Attached highlight quote ────────────────────────────────────────
        if (hlContent != null && hlContent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 10, 16, 0),
            child: _HighlightQuoteCard(
              content: hlContent,
              title: hlBookTitle,
              author: hlAuthor,
              accent: accent,
            ),
          ),

        // ── Action bar ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(54, 8, 14, 12),
          child: Row(
            children: [
              // Like button
              GestureDetector(
                onTap: _toggleLike,
                // Opaque so the whole padded pill is tappable, not just the
                // painted icon/number (the row uses transparent fills).
                behavior: HitTestBehavior.opaque,
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
                        _liked
                            ? PhosphorIconsFill.heart
                            : PhosphorIconsRegular.heart,
                        size: 17,
                        color: _liked
                            ? MarginaliaColors.primaryDark
                            : MarginaliaColors.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$_likesCount',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _liked
                              ? MarginaliaColors.primaryDark
                              : MarginaliaColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Comment button — tapping the icon/label opens the comments
              // sheet. Opaque hit-testing makes the whole padded area
              // clickable (the fill is transparent, so without this only the
              // glyphs registered taps and the bar felt "dead").
              GestureDetector(
                onTap: () => _openComments(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Phosphor's chat bubble — same thick-stroke vocabulary
                      // as the navbar icons, much closer to the user's
                      // visual reference than Material's hairline outlined.
                      Icon(
                        PhosphorIconsRegular.chatCircle,
                        size: 18,
                        color: MarginaliaColors.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        context.l10n.feedCommentAction,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Share button — paper plane opens the "send to chats" sheet for
              // this post. Same icon vocabulary + sizing/color as like/comment.
              GestureDetector(
                onTap: () => _sharePost(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    PhosphorIconsRegular.paperPlaneTilt,
                    size: 18,
                    color: MarginaliaColors.inkFaint,
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
    );

    // Only the first screenful gets the staggered entrance animation.
    // `flutter_animate`'s `.animate()` REPLAYS on every rebuild — and a
    // SliverList rebuilds recycled cards constantly while scrolling, which
    // made every card re-run its fade/slide mid-scroll and felt like the
    // scroll was "stuttering". Cards beyond the initial reveal render
    // statically so scrolling stays smooth.
    if (widget.index >= 6) return card;
    return card
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

// ─── Gated (tap-to-reveal) text ──────────────────────────────────────────────
//
// Wraps post/comment body text. The keyword inspection is run ONCE in
// initState (memoized) — never inside build — so scrolling a long feed stays
// cheap. When flagged, the text is hidden behind a tappable warning box
// ("Potentially inappropriate content — tap to show"); revealing is local
// state. When clean (or once revealed) the supplied [child] renders normally.
//
// `alreadyOwn` lets a caller skip gating for the author's own content (their
// own view never needs the warning); gating everyone is also fine.

class _GatedText extends StatefulWidget {
  const _GatedText({
    required this.text,
    required this.child,
    this.alreadyOwn = false,
  });

  /// The raw body text to inspect. The visible rendering is [child].
  final String text;
  final Widget child;

  /// When true the author is viewing their own content → never gate it.
  final bool alreadyOwn;

  @override
  State<_GatedText> createState() => _GatedTextState();
}

class _GatedTextState extends State<_GatedText> {
  late final bool _flagged;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    // Memoize the inspection: compute the (cheap) keyword scan exactly once
    // per mounted item instead of on every rebuild.
    _flagged = !widget.alreadyOwn && contentFilter.inspect(widget.text).flagged;
  }

  @override
  Widget build(BuildContext context) {
    if (!_flagged || _revealed) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _revealed = true),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MarginaliaColors.rule, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.visibility_off_outlined,
              size: 18,
              color: MarginaliaColors.inkMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.contentHiddenTitle,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.contentRevealAction,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MarginaliaColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Post body with tappable @mentions ───────────────────────────────────────

/// Renders a post body as rich text where each "@username" that resolves to a
/// tagged user becomes a tappable span opening that user's profile. Unknown
/// "@username" tokens (not in [mentionedProfiles]) render as plain text.
///
/// [mentionedProfiles] is the per-post map id -> {username, display_name} built
/// by SupabaseService. We reverse it to username -> id so we can resolve the
/// tokens scanned out of the body.
///
/// Stateful so the [TapGestureRecognizer]s it creates are disposed correctly.
class _MentionText extends StatefulWidget {
  const _MentionText({required this.body, required this.mentionedProfiles});

  final String body;
  final Map<String, dynamic> mentionedProfiles;

  @override
  State<_MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<_MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dispose any recognizers from a previous build before rebuilding spans.
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    const baseStyle = TextStyle(
      fontSize: 15,
      color: MarginaliaColors.ink,
      height: 1.65,
    );
    final textStyle = GoogleFonts.manrope(
      fontSize: baseStyle.fontSize,
      color: baseStyle.color,
      height: baseStyle.height,
    );
    final mentionStyle = GoogleFonts.manrope(
      fontSize: 15,
      height: 1.65,
      color: MarginaliaColors.primaryDark,
      fontWeight: FontWeight.w600,
    );

    // Reverse the id -> {username,...} map into username (lowercase) -> id.
    final idByUsername = <String, String>{};
    widget.mentionedProfiles.forEach((id, value) {
      if (value is Map) {
        final username = (value['username'] as String? ?? '').toLowerCase();
        if (username.isNotEmpty) idByUsername[username] = id;
      }
    });

    final spans = <InlineSpan>[];
    final body = widget.body;
    final pattern = RegExp(r'@(\w+)');
    var index = 0;
    for (final match in pattern.allMatches(body)) {
      // Plain run before this @token.
      if (match.start > index) {
        spans.add(TextSpan(text: body.substring(index, match.start)));
      }
      final token = match.group(0)!; // includes the leading '@'
      final username = (match.group(1) ?? '').toLowerCase();
      final userId = idByUsername[username];
      if (userId != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => context.push('/user/$userId');
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: token,
          style: mentionStyle,
          recognizer: recognizer,
        ));
      } else {
        // Not a tagged user → render the token as plain text.
        spans.add(TextSpan(text: token));
      }
      index = match.end;
    }
    // Trailing plain run.
    if (index < body.length) {
      spans.add(TextSpan(text: body.substring(index)));
    }

    return Text.rich(
      TextSpan(style: textStyle, children: spans),
    );
  }
}

// ─── Single post detail screen ───────────────────────────────────────────────
//
// Opens ONE post full-screen and reuses the very same `_PostCard` the feed
// renders, so every interaction (like, comment sheet, owner menu) works
// identically — they all operate by postId and don't depend on the feed list.
//
// Reached from:
//   • the `/post/:id` deep route (notification taps), and
//   • tapping a post in a profile timeline.
//
// Because `_PostCard` is private to this file, this screen lives here too so it
// can construct it directly with the fetched post Map.

class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(singlePostProvider(postId));

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MarginaliaColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          context.l10n.postDetailTitle,
          style: GoogleFonts.ebGaramond(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.ink,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: MarginaliaColors.sienna,
        backgroundColor: MarginaliaColors.surface,
        strokeWidth: 1.5,
        onRefresh: () async {
          ref.invalidate(singlePostProvider(postId));
          await ref
              .read(singlePostProvider(postId).future)
              .catchError((_) => null);
        },
        child: postAsync.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            children: const [
              Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(
                  child: CircularProgressIndicator(
                    color: MarginaliaColors.sienna,
                    strokeWidth: 1.5,
                  ),
                ),
              ),
            ],
          ),
          error: (_, __) => _PostDetailEmpty(),
          data: (post) => post == null
              ? _PostDetailEmpty()
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  children: [
                    // Same card as the feed → identical like / comment / menu.
                    _PostCard(post: post, index: 0),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PostDetailEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works in the not-found state.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 120, 40, 40),
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
                context.l10n.postUnavailable,
                textAlign: TextAlign.center,
                style: GoogleFonts.ebGaramond(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.ink,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Comments sheet ───────────────────────────────────────────────────────────

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId, this.postOwnerId});
  final String postId;
  // Owner of the post these comments belong to. The post owner is allowed to
  // delete (moderate) ANY comment, so this is passed down to each bubble.
  final String? postOwnerId;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _ctrl        = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _inputFocus  = FocusNode();
  bool _submitting   = false;
  Uint8List? _imageBytes;
  String?    _imageExt;
  String?    _gifUrl;
  List<Map<String, dynamic>> _topLevelComments = [];
  Map<String, List<Map<String, dynamic>>> _repliesByParent = {};
  bool _loading = true;

  // Reply mode
  String? _replyingToId;
  String? _replyingToName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await ref
          .read(supabaseServiceProvider)
          .fetchPostComments(widget.postId);
      if (mounted) {
        final topLevel = comments
            .where((c) => c['parent_comment_id'] == null)
            .toList();
        final byParent = <String, List<Map<String, dynamic>>>{};
        for (final c in comments) {
          final pid = c['parent_comment_id'] as String?;
          if (pid != null) byParent.putIfAbsent(pid, () => []).add(c);
        }
        setState(() {
          _topLevelComments = topLevel;
          _repliesByParent  = byParent;
          _loading          = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startReply(String commentId, String commenterName) {
    setState(() {
      _replyingToId   = commentId;
      _replyingToName = commenterName;
    });
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() {
        _replyingToId   = null;
        _replyingToName = null;
      });

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    setState(() {
      _imageBytes = r.files.first.bytes;
      _imageExt   = (r.files.first.extension ?? 'jpg').toLowerCase();
      _gifUrl     = null;
    });
  }

  Future<void> _pickGif() async {
    final url = await showGifPicker(context);
    if (url != null && mounted) {
      setState(() {
        _gifUrl     = url;
        _imageBytes = null;
        _imageExt   = null;
      });
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _imageBytes == null && _gifUrl == null) return;

    // Same first-line keyword filter as post creation: block clearly
    // objectionable comment text before sending, and let the user edit.
    if (text.isNotEmpty) {
      final inspection = contentFilter.inspect(text);
      if (inspection.flagged) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.contentBlockedMessage(
                _contentCategoryLabel(context, inspection.category!),
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      String? imageUrl;
      if (_imageBytes != null && _imageExt != null) {
        imageUrl = await svc.uploadCommentImage(_imageBytes!, _imageExt!);
      }
      await svc.addPostComment(
        widget.postId,
        content:         text.isEmpty ? null : text,
        imageUrl:        imageUrl,
        gifUrl:          _gifUrl,
        parentCommentId: _replyingToId,
      );
      _ctrl.clear();
      setState(() {
        _imageBytes     = null;
        _imageExt       = null;
        _gifUrl         = null;
        _submitting     = false;
        _replyingToId   = null;
        _replyingToName = null;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
        setState(() => _submitting = false);
      }
    }
  }

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
  Widget build(BuildContext context) {
    // Only the keyboard inset: the input bar should dock immediately on top of
    // the keyboard, not float above it. (Adding padding.bottom here stacked the
    // home-indicator inset on top of the keyboard, lifting the bar too high.)
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    final canSend = !_submitting &&
        (_ctrl.text.trim().isNotEmpty || _imageBytes != null || _gifUrl != null);
    final isReplying = _replyingToId != null;

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.feedComments,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MarginaliaColors.ink,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close,
                      size: 20, color: MarginaliaColors.inkMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5, color: MarginaliaColors.ruleFaint),

          // Comments list
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: MarginaliaColors.sienna,
                        strokeWidth: 1.5,
                      ),
                    ),
                  )
                : _topLevelComments.isEmpty && _repliesByParent.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            context.l10n.feedNoComments,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              color: MarginaliaColors.inkMuted,
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          for (final c in _topLevelComments) ...[
                            _CommentBubble(
                              comment: c,
                              postOwnerId: widget.postOwnerId,
                              timeAgo: _timeAgo(context, c['created_at'] as String?),
                              onReply: () => _startReply(
                                c['id'] as String,
                                (c['profiles'] as Map?)?['display_name']
                                        as String? ??
                                    'Reader',
                              ),
                              onDeleted: _load,
                            ),
                            for (final reply
                                in _repliesByParent[c['id']] ?? [])
                              Padding(
                                padding: const EdgeInsets.only(left: 40),
                                child: _CommentBubble(
                                  comment: reply,
                                  postOwnerId: widget.postOwnerId,
                                  timeAgo:
                                      _timeAgo(context, reply['created_at'] as String?),
                                  onReply: () => _startReply(
                                    c['id'] as String,
                                    (reply['profiles'] as Map?)?[
                                                'display_name'] as String? ??
                                        'Reader',
                                  ),
                                  onDeleted: _load,
                                  isReply: true,
                                ),
                              ),
                          ],
                        ],
                      ),
          ),

          const Divider(height: 0.5, thickness: 0.5, color: MarginaliaColors.ruleFaint),

          // "Rispondendo a…" banner
          if (isReplying)
            Container(
              color: MarginaliaColors.surfaceElevated,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded,
                      size: 14, color: MarginaliaColors.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.feedReplyingTo(_replyingToName ?? ''),
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: MarginaliaColors.inkMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: const Icon(Icons.close,
                        size: 16, color: MarginaliaColors.inkMuted),
                  ),
                ],
              ),
            ),

          // Attachment preview
          if (_imageBytes != null || _gifUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _imageBytes != null
                        ? Image.memory(_imageBytes!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover)
                        : Image.network(_gifUrl!,
                            height: 100,
                            width: double.infinity,
                            fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _imageBytes = null;
                        _imageExt   = null;
                        _gifUrl     = null;
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(160),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Input row — docks right above the keyboard: keyboard inset + 8px.
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, bottom + 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Photo button
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: MarginaliaColors.rule),
                    ),
                    child: const Icon(Icons.image_outlined,
                        size: 18, color: MarginaliaColors.inkMuted),
                  ),
                ),
                const SizedBox(width: 6),
                // GIF button
                GestureDetector(
                  onTap: _pickGif,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.surfaceElevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: MarginaliaColors.rule),
                    ),
                    child: Center(
                      child: Text(
                        'GIF',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: MarginaliaColors.inkMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: MarginaliaColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: MarginaliaColors.rule),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _inputFocus,
                      maxLines: null,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: MarginaliaColors.ink,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: isReplying
                            ? context.l10n.feedReplyHint(_replyingToName ?? '')
                            : context.l10n.feedCommentHint,
                        hintStyle: TextStyle(
                          color: MarginaliaColors.inkFaint,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                GestureDetector(
                  onTap: canSend ? _submit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: canSend
                          ? MarginaliaColors.sienna
                          : MarginaliaColors.rule,
                      shape: BoxShape.circle,
                    ),
                    child: _submitting
                        ? const Center(
                            child: SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: Colors.white),
                            ),
                          )
                        : Icon(PhosphorIconsFill.paperPlaneTilt,
                            size: 15, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Comment bubble ───────────────────────────────────────────────────────────

class _CommentBubble extends ConsumerStatefulWidget {
  const _CommentBubble({
    required this.comment,
    required this.timeAgo,
    required this.onReply,
    required this.onDeleted,
    this.postOwnerId,
    this.isReply = false,
  });
  final Map<String, dynamic> comment;
  // Owner of the post this comment belongs to. When the current user is the
  // post owner they may delete (moderate) ANY comment, not only their own.
  final String? postOwnerId;
  final String timeAgo;
  final VoidCallback onReply;
  // Called after the comment is deleted so the sheet can refresh its list.
  final VoidCallback onDeleted;
  final bool isReply;

  @override
  ConsumerState<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends ConsumerState<_CommentBubble> {
  late bool _liked;
  late int  _likeCount;

  @override
  void initState() {
    super.initState();
    _liked     = widget.comment['has_liked']  as bool? ?? false;
    _likeCount = widget.comment['like_count'] as int?  ?? 0;
  }

  Future<void> _toggleLike() async {
    final svc      = ref.read(supabaseServiceProvider);
    final wasLiked = _liked;
    setState(() {
      _liked     = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      if (!wasLiked) {
        await svc.likeComment(widget.comment['id'] as String);
      } else {
        await svc.unlikeComment(widget.comment['id'] as String);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked     = wasLiked;
          _likeCount += wasLiked ? 1 : -1;
        });
      }
    }
  }

  // Overflow ("...") menu for a single comment. Delete is offered when the
  // current user is the comment's author OR the owner of the post (so the post
  // owner can moderate any comment on their own post). Everyone else sees a
  // "Report" placeholder, mirroring _PostCard's _showPostMenu.
  Future<void> _showCommentMenu(BuildContext context) async {
    final svc           = ref.read(supabaseServiceProvider);
    final commentId     = widget.comment['id'] as String?;
    final commentUserId = widget.comment['user_id'] as String?;
    final currentUserId = svc.userId;
    final isAuthor    = currentUserId != null && currentUserId == commentUserId;
    final isPostOwner = currentUserId != null &&
        widget.postOwnerId != null &&
        currentUserId == widget.postOwnerId;
    final canDelete = isAuthor || isPostOwner;

    // Capture messenger + l10n once, while this bubble is guaranteed mounted —
    // the delete refreshes the list and unmounts this bubble, so reusing the
    // raw context after the await would throw.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    if (!canDelete) {
      // Neither the author nor the post owner: Report (real backend) + Block.
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PostMenuSheet(
          items: [
            _MenuAction(
              icon: Icons.flag_outlined,
              label: l10n.feedReport,
              color: MarginaliaColors.inkMuted,
              onTap: () async {
                Navigator.pop(ctx);
                if (commentId == null) return;
                await showReportSheet(
                  context,
                  ref,
                  contentType: 'comment',
                  contentId: commentId,
                  reportedUserId: commentUserId,
                );
              },
            ),
            _MenuAction(
              icon: Icons.block,
              label: l10n.blockUser,
              color: const Color(0xFFB54848),
              onTap: () async {
                Navigator.pop(ctx);
                if (commentUserId == null) return;
                final confirmed = await confirmBlockUser(context);
                if (!confirmed) return;
                try {
                  await svc.blockUser(commentUserId);
                  // Comments by a blocked user are filtered server-side; reload
                  // the list so this one disappears immediately.
                  widget.onDeleted();
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.userBlocked)),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.feedErrorPrefix(e.toString()))),
                  );
                }
              },
            ),
          ],
        ),
      );
      return;
    }

    // Author and/or post owner: delete.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PostMenuSheet(
        items: [
          _MenuAction(
            icon: Icons.delete_outline,
            label: l10n.feedDeleteAction,
            color: const Color(0xFFDC2626),
            onTap: () async {
              Navigator.pop(ctx);
              if (commentId == null) return;
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Text(l10n.feedDeleteConfirmTitle),
                  content: Text(l10n.feedDeleteConfirmBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626)),
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      child: Text(l10n.feedDeleteAction),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                // The author deletes via the plain RLS-guarded path. When the
                // current user is the post owner moderating SOMEONE ELSE's
                // comment, that RLS DELETE policy (user_id = auth.uid()) would
                // silently no-op, so route through the SECURITY DEFINER RPC
                // `delete_post_comment_as_owner` (migration 038) which permits
                // the post owner OR the comment author. Called via svc.client
                // so no change to SupabaseService is required.
                if (isAuthor) {
                  await svc.deletePostComment(commentId);
                } else {
                  await svc.client.rpc(
                    'delete_post_comment_as_owner',
                    params: {'p_comment_id': commentId},
                  );
                }
                // Refresh the comments list via the sheet's reload callback.
                widget.onDeleted();
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.feedErrorPrefix(e.toString()))),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile   = widget.comment['profiles'] as Map?;
    final name      = profile?['display_name'] as String? ?? 'Reader';
    final avatarUrl = profile?['avatar_url']   as String?;
    final content   = widget.comment['content']   as String?;
    final imageUrl  = widget.comment['image_url'] as String?;
    final gifUrl    = widget.comment['gif_url']   as String?;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint      = MarginaliaDecorations.bookCoverColor(name);
    final avatarSize = widget.isReply ? 26.0 : 32.0;

    // The comment author's own view is never gated.
    final currentUserId = ref.read(supabaseServiceProvider).userId;
    final isAuthor = currentUserId != null &&
        currentUserId == (widget.comment['user_id'] as String?);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarCircle(
            avatarUrl: avatarUrl,
            initial: initial,
            tint: tint,
            size: avatarSize,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + time + overflow menu
                Row(
                  children: [
                    // Name + time fill the available width so the overflow
                    // dots get pushed to the trailing edge (mirrors _PostCard).
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: GoogleFonts.manrope(
                                fontSize: widget.isReply ? 12.0 : 12.5,
                                fontWeight: FontWeight.w700,
                                color: MarginaliaColors.ink,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.timeAgo,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: MarginaliaColors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 3-dot overflow: delete (author) / report (others).
                    GestureDetector(
                      onTap: () => _showCommentMenu(context),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(8, 2, 2, 2),
                        child: Icon(
                          PhosphorIconsRegular.dotsThree,
                          size: 18,
                          color: MarginaliaColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Bubble with text and/or media
                Container(
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surfaceElevated,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (content != null && content.isNotEmpty)
                        _GatedText(
                          text: content,
                          alreadyOwn: isAuthor,
                          child: Text(
                            content,
                            style: GoogleFonts.manrope(
                              fontSize: 13.5,
                              color: MarginaliaColors.ink,
                              height: 1.55,
                            ),
                          ),
                        ),
                      if ((imageUrl != null || gifUrl != null) &&
                          (content != null && content.isNotEmpty))
                        const SizedBox(height: 6),
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : Container(
                                        height: 120,
                                        color: MarginaliaColors.ruleFaint,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: MarginaliaColors.sienna,
                                          ),
                                        ),
                                      ),
                            errorBuilder: (_, __, ___) => Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: MarginaliaColors.ruleFaint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    size: 20,
                                    color: MarginaliaColors.inkFaint),
                              ),
                            ),
                          ),
                        ),
                      if (gifUrl != null && gifUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            gifUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: MarginaliaColors.ruleFaint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(Icons.gif,
                                    size: 24,
                                    color: MarginaliaColors.inkFaint),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Like + reply actions
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleLike,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                        child: Row(
                          children: [
                            Icon(
                              _liked
                                  ? PhosphorIconsFill.heart
                                  : PhosphorIconsRegular.heart,
                              size: 15,
                              color: _liked
                                  ? MarginaliaColors.primaryDark
                                  : MarginaliaColors.inkFaint,
                            ),
                            if (_likeCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '$_likeCount',
                                style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  color: _liked
                                      ? MarginaliaColors.primaryDark
                                      : MarginaliaColors.inkFaint,
                                  fontWeight: _liked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!widget.isReply)
                      GestureDetector(
                        onTap: widget.onReply,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                          child: Text(
                            context.l10n.feedReplyAction,
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              color: MarginaliaColors.inkFaint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Post menu sheet ─────────────────────────────────────────────────────────

class _MenuAction {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

class _PostMenuSheet extends StatelessWidget {
  const _PostMenuSheet({required this.items});
  final List<_MenuAction> items;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              // Translucent surface over a blurred backdrop = liquid glass.
              color: MarginaliaColors.surface.withAlpha(225),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withAlpha(46), width: 0.6),
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MarginaliaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ...items.map(
                  (a) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: a.onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(a.icon,
                                  size: 20,
                                  color: a.color ?? MarginaliaColors.ink),
                              const SizedBox(width: 14),
                              Text(
                                a.label,
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: a.color ?? MarginaliaColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
            context.l10n.feedEmptyTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.feedEmptyFollowing,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
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
                  size: 32, color: MarginaliaColors.primaryDark),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.profileLoginRequired,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.profileLoginBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/auth'),
              icon: const Icon(Icons.login, size: 16),
              label: Text(context.l10n.authSignIn),
            ),
          ],
        ),
      ),
    );
  }
}

