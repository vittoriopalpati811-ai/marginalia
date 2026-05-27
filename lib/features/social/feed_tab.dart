import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../messages/giphy_picker.dart';

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
      await svc.createPost(body: text.isEmpty ? null : text, imageUrl: imageUrl);
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
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
                hintText: 'What are you reading? Share a thought…',
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

// ─── [LEGACY — kept for reference, no longer used] ────────────────────────────
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color  color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = (size.shortestSide / 2) - 3;
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = color.withAlpha(40)..style = PaintingStyle.stroke..strokeWidth = 3,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.5707963, // -π/2 = 12 o'clock
      progress * 6.2831853, // full circle = 2π
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
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
  bool _deleted = false;

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

    if (!isOwner) {
      // Non-owner: only "Report" option (placeholder)
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _PostMenuSheet(
          items: [
            _MenuAction(
              icon: Icons.flag_outlined,
              label: 'Segnala post',
              color: MarginaliaColors.inkMuted,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post segnalato. Grazie!')),
                );
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
            label: 'Edit post',
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
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(context.l10n.feedDeleteConfirmTitle),
                  content: Text(context.l10n.feedDeleteConfirmBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(context.l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(context.l10n.feedDeleteAction),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                try {
                  await svc.deletePost(postId);
                  if (mounted) {
                    setState(() => _deleted = true);
                    ref.invalidate(postsProvider);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(context.l10n.feedErrorPrefix(e.toString()))));
                  }
                }
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
      builder: (_) => _CommentsSheet(postId: postId),
    );
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
    if (_deleted) return const SizedBox.shrink();

    final post          = widget.post;
    final profile       = post['profile']    as Map?;
    final name          = profile?['display_name']         as String? ?? 'Reader';
    final avatarUrl     = profile?['avatar_url']           as String?;
    final readingTitle  = profile?['currently_reading_title'] as String?;
    final userId        = post['user_id']    as String?;
    final body          = post['body']       as String?;
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
    final timeAgo       = _timeAgo(createdAt);
    final accent        = _accentFor(hlColor);

    // Current user check for menu
    final currentUserId = ref.read(supabaseServiceProvider).userId;
    final isOwner = currentUserId != null && currentUserId == userId;

    return Column(
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
                              color: MarginaliaColors.siennaLight,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                readingTitle,
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: MarginaliaColors.siennaLight,
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
              // 3-dot menu
              GestureDetector(
                onTap: () => _showPostMenu(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                  child: Icon(
                    Icons.more_horiz,
                    size: 20,
                    color: isOwner
                        ? MarginaliaColors.inkMuted
                        : MarginaliaColors.inkFaint,
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
              style: GoogleFonts.manrope(
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
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      height: 220,
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
                height: 72,
                color: MarginaliaColors.surfaceElevated,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image_outlined,
                          size: 18, color: MarginaliaColors.inkFaint),
                      const SizedBox(width: 6),
                      Text(
                        'Immagine non disponibile',
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
              // Like button
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
                        style: GoogleFonts.manrope(
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
              const SizedBox(width: 4),
              // Comment button
              GestureDetector(
                onTap: () => _openComments(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 16,
                        color: MarginaliaColors.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Commenta',
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

// ─── Comments sheet ───────────────────────────────────────────────────────────

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId});
  final String postId;

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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24)   return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final bottom  = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
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
                    'Commenti',
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
                              timeAgo: _timeAgo(c['created_at'] as String?),
                              onReply: () => _startReply(
                                c['id'] as String,
                                (c['profiles'] as Map?)?['display_name']
                                        as String? ??
                                    'Reader',
                              ),
                            ),
                            for (final reply
                                in _repliesByParent[c['id']] ?? [])
                              Padding(
                                padding: const EdgeInsets.only(left: 40),
                                child: _CommentBubble(
                                  comment: reply,
                                  timeAgo:
                                      _timeAgo(reply['created_at'] as String?),
                                  onReply: () => _startReply(
                                    c['id'] as String,
                                    (reply['profiles'] as Map?)?[
                                                'display_name'] as String? ??
                                        'Reader',
                                  ),
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
                      'Rispondendo a $_replyingToName',
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

          // Input row
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, bottom + 16),
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
                            ? 'Reply to $_replyingToName…'
                            : 'Write a comment…',
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
                        : const Icon(Icons.send_rounded,
                            size: 16, color: Colors.white),
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
    this.isReply = false,
  });
  final Map<String, dynamic> comment;
  final String timeAgo;
  final VoidCallback onReply;
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
                // Name + time
                Row(
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.manrope(
                        fontSize: widget.isReply ? 12.0 : 12.5,
                        fontWeight: FontWeight.w700,
                        color: MarginaliaColors.ink,
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
                        Text(
                          content,
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            color: MarginaliaColors.ink,
                            height: 1.55,
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
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 14,
                              color: _liked
                                  ? MarginaliaColors.sienna
                                  : MarginaliaColors.inkFaint,
                            ),
                            if (_likeCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '$_likeCount',
                                style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  color: _liked
                                      ? MarginaliaColors.sienna
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
                            'Rispondi',
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
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(0, 8, 0, bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ...items.map(
            (a) => InkWell(
              onTap: a.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(a.icon, size: 20, color: a.color ?? MarginaliaColors.ink),
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
            'Your feed is empty',
            style: GoogleFonts.ebGaramond(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow other readers from the Friends tab\nto see their posts here.',
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
                  size: 32, color: MarginaliaColors.siennaLight),
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

