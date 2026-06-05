import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';

// ─── Gradient presets (mirrors my_profile_screen.dart) ───────────────────────

class _GP {
  const _GP(this.key, this.label, this.a, this.b);
  final String key;
  final String label;
  final Color a;
  final Color b;
  List<Color> get colors => [a, b];
}

const _kGradients = [
  _GP('sepia',    'Sepia',    Color(0xFF6B4C3B), Color(0xFF2C1810)),
  _GP('forest',   'Forest',   Color(0xFF2D5A3D), Color(0xFF132A1E)),
  _GP('ocean',    'Ocean',    Color(0xFF1A3A5C), Color(0xFF09141F)),
  _GP('dusk',     'Dusk',     Color(0xFF6B3A7A), Color(0xFF1A0B26)),
  _GP('rose',     'Rose',     Color(0xFF7A3A4E), Color(0xFF2E1020)),
  _GP('graphite', 'Graphite', Color(0xFF3C3C3C), Color(0xFF141414)),
  _GP('amber',    'Amber',    Color(0xFF7A4E1A), Color(0xFF2C1A06)),
  _GP('slate',    'Slate',    Color(0xFF2A3A4E), Color(0xFF0D141E)),
];

_GP _gpFor(String key) =>
    _kGradients.firstWhere((g) => g.key == key, orElse: () => _kGradients.first);

// Render-time localized label for a gradient, keyed by the stable gradient id.
// The const _kGradients list above cannot use context.l10n, so the display
// label is resolved here at build time.
String _gradientLabel(BuildContext context, String key) => switch (key) {
      'sepia'    => context.l10n.gradientSepia,
      'forest'   => context.l10n.gradientForest,
      'ocean'    => context.l10n.gradientOcean,
      'dusk'     => context.l10n.gradientDusk,
      'rose'     => context.l10n.gradientRose,
      'graphite' => context.l10n.gradientGraphite,
      'amber'    => context.l10n.gradientAmber,
      'slate'    => context.l10n.gradientSlate,
      _          => context.l10n.gradientSepia,
    };

const _kPatterns = ['none', 'dots', 'lines', 'grid', 'circles'];

// Render-time localized label for a pattern, keyed by the stable pattern id.
String _patternLabel(BuildContext context, String key) => switch (key) {
      'none'    => context.l10n.patternNone,
      'dots'    => context.l10n.patternDots,
      'lines'   => context.l10n.patternLines,
      'grid'    => context.l10n.patternGrid,
      'circles' => context.l10n.patternCircles,
      _         => context.l10n.patternNone,
    };

// ─── EditProfileScreen ────────────────────────────────────────────────────────

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.initialProfile,
    required this.initialGradient,
    required this.initialPattern,
    required this.onSaved,
  });

  /// The raw profile map from Supabase (may be null if first load).
  final Map<String, dynamic>? initialProfile;
  final String initialGradient;
  final String initialPattern;

  /// Called after a successful save so the parent can invalidate providers.
  final VoidCallback onSaved;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _readingTitleCtrl;
  late final TextEditingController _readingAuthorCtrl;

  late String _gradKey;
  late String _patKey;

  bool _uploadingAvatar = false;
  bool _uploadingCover  = false;
  bool _saving          = false;

  // Username availability
  bool? _usernameAvailable;   // null = unchecked, true = ok, false = taken
  bool  _checkingUsername = false;
  Timer? _usernameDebounce;

  // Local URL cache — updated immediately after a successful upload so the
  // preview refreshes without waiting for the parent to invalidate the provider.
  String? _localAvatarUrl;
  String? _localCoverUrl;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl          = TextEditingController(text: p?['display_name'] as String? ?? '');
    _bioCtrl           = TextEditingController(text: p?['bio'] as String? ?? '');
    _usernameCtrl      = TextEditingController(text: p?['username'] as String? ?? '');
    _readingTitleCtrl  = TextEditingController(text: p?['currently_reading_title'] as String? ?? '');
    _readingAuthorCtrl = TextEditingController(text: p?['currently_reading_author'] as String? ?? '');
    _gradKey = widget.initialGradient;
    _patKey  = widget.initialPattern;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _usernameCtrl.dispose();
    _readingTitleCtrl.dispose();
    _readingAuthorCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    final cleaned = value.trim().toLowerCase();
    if (cleaned.isEmpty) {
      setState(() { _usernameAvailable = null; _checkingUsername = false; });
      return;
    }
    setState(() { _checkingUsername = true; _usernameAvailable = null; });
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final available = await ref
            .read(supabaseServiceProvider)
            .isUsernameAvailable(cleaned);
        if (mounted) setState(() { _usernameAvailable = available; _checkingUsername = false; });
      } catch (_) {
        if (mounted) setState(() => _checkingUsername = false);
      }
    });
  }

  // ── Photo helpers ────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    // Flip the spinner BEFORE awaiting pickFiles: on web, withData:true
    // can block 1-3s reading a 5-10MB iPhone photo, with no visible
    // feedback otherwise (the iOS file sheet has already dismissed).
    setState(() => _uploadingAvatar = true);
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      // Previously we returned silently here — that's exactly why the user
      // reported "the avatar doesn't save": iOS Safari + file_picker sometimes
      // returns a result with bytes == null (the picker UI dismisses but the
      // FileReader never populated the buffer). Surface a clear error so the
      // user knows to retry, ideally with a smaller image.
      if (r == null || r.files.isEmpty) {
        return; // user genuinely cancelled, no error
      }
      final file = r.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.editProfilePhotoReadFailed),
              backgroundColor: const Color(0xFF8B2E2E),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      final url = await ref.read(supabaseServiceProvider).uploadAvatar(
            file.bytes!,
            (file.extension ?? 'jpg').toLowerCase(),
          );
      // Update local cache so the preview refreshes immediately in this screen.
      if (mounted) setState(() => _localAvatarUrl = url);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.editProfilePhotoUpdated)),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[edit_profile] avatar upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.editProfilePhotoUpdateError}: $e'),
            backgroundColor: const Color(0xFF8B2E2E),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickCover() async {
    if (_uploadingCover) return;
    setState(() => _uploadingCover = true);
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (r == null || r.files.isEmpty) {
        return;
      }
      final file = r.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.editProfilePhotoReadFailed),
              backgroundColor: const Color(0xFF8B2E2E),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      final url = await ref.read(supabaseServiceProvider).uploadCover(
            file.bytes!,
            (file.extension ?? 'jpg').toLowerCase(),
          );
      // Update local cache so the cover preview refreshes immediately.
      if (mounted) setState(() => _localCoverUrl = url);
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.editProfileCoverUpdated)),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[edit_profile] cover upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.editProfileCoverUpdateError}: $e'),
            backgroundColor: const Color(0xFF8B2E2E),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Block if username is being checked or is already taken
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isNotEmpty && _usernameAvailable == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.editProfileUsernameUnavailable)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      await Future.wait([
        svc.updateProfileInfo(
          displayName: _nameCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
          currentlyReadingTitle:  _readingTitleCtrl.text.trim(),
          currentlyReadingAuthor: _readingAuthorCtrl.text.trim(),
          username: username.isEmpty ? null : username,
        ),
        svc.updateProfileAppearance(_gradKey, _patKey),
      ]);
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gp  = _gpFor(_gradKey);
    final p   = widget.initialProfile;
    // _local* takes priority: updated immediately after upload without waiting
    // for the parent provider to re-fetch from Supabase.
    final avatarUrl = _localAvatarUrl ?? p?['avatar_url'] as String?;
    final coverUrl  = _localCoverUrl  ?? p?['cover_url']  as String?;
    final name      = _nameCtrl.text;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      // Slim cream app bar replaces the 200px green "preview hero" the user
      // flagged as redundant ("quella è già visibile nella sezione
      // personale dell'account"). The user's profile screen already shows
      // the avatar + cover; this screen now reads as a settings form, not
      // a second presentation of the same card.
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0.3,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: MarginaliaColors.ink,
        ),
        title: Text(
          context.l10n.profileEditProfile,
          style: GoogleFonts.ebGaramond(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.ink,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Photos row (avatar + cover) ───────────────────────────────────
          // Compact, functional row at the top of the form — small circular
          // avatar preview and a wider cover thumbnail, each with its own
          // tap-to-pick affordance. Replaces the old immersive hero.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(context.l10n.editProfilePhotosLabel),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Avatar preview (tappable) ───────────────────────
                      GestureDetector(
                        onTap: _uploadingAvatar ? null : _pickAvatar,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                MarginaliaDecorations.bookCoverColor(name),
                                gp.b,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                                color: MarginaliaColors.rule, width: 1),
                          ),
                          child: _uploadingAvatar
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 1.5))
                              : avatarUrl != null && avatarUrl.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(avatarUrl,
                                          fit: BoxFit.cover,
                                          width: 64,
                                          height: 64,
                                          errorBuilder: (_, __, ___) =>
                                              _InitialText(initial)))
                                  : _InitialText(initial),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Cover preview (tappable, wider) ─────────────────
                      Expanded(
                        child: GestureDetector(
                          onTap: _uploadingCover ? null : _pickCover,
                          child: Container(
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: MarginaliaColors.rule, width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (coverUrl != null && coverUrl.isNotEmpty)
                                    Image.network(coverUrl, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _GradientBox(gp: gp, pat: _patKey))
                                  else
                                    _GradientBox(gp: gp, pat: _patKey),
                                  if (_uploadingCover)
                                    Container(
                                      color: Colors.black.withAlpha(80),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 1.5),
                                      ),
                                    )
                                  else
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(110),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.image_outlined,
                                                size: 13,
                                                color: Colors.white),
                                            const SizedBox(width: 4),
                                            Text(
                                              context.l10n.editProfileCoverBadge,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Form fields ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(context.l10n.editProfileInformationLabel),
                  const SizedBox(height: 10),

                  _Field(
                    controller: _nameCtrl,
                    label: context.l10n.editProfileDisplayName,
                    hint: context.l10n.editProfileDisplayNameHint,
                    icon: Icons.person_outline,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // Username field with live availability check
                  _UsernameField(
                    controller: _usernameCtrl,
                    available: _usernameAvailable,
                    checking: _checkingUsername,
                    onChanged: _onUsernameChanged,
                  ),
                  const SizedBox(height: 12),

                  _Field(
                    controller: _bioCtrl,
                    label: context.l10n.editProfileBioLabel,
                    hint: context.l10n.editProfileBioHint,
                    icon: Icons.edit_note_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  _SectionLabel(context.l10n.editProfileCurrentlyReadingLabel),
                  const SizedBox(height: 10),

                  _Field(
                    controller: _readingTitleCtrl,
                    label: context.l10n.editProfileBookTitleHint,
                    hint: context.l10n.editProfileBookTitleExample,
                    icon: Icons.menu_book_outlined,
                  ),
                  const SizedBox(height: 12),

                  _Field(
                    controller: _readingAuthorCtrl,
                    label: context.l10n.editProfileAuthorLabel,
                    hint: context.l10n.editProfileAuthorExample,
                    icon: Icons.person_search_outlined,
                  ),
                  const SizedBox(height: 28),

                  // ── Gradient picker ────────────────────────────────────────
                  _SectionLabel(context.l10n.editProfileBackgroundLabel),
                  const SizedBox(height: 12),

                  // Live mini-preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 72,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _GradientBox(gp: gp, pat: _patKey),
                          Center(
                            child: Text(context.l10n.editProfilePreviewLabel,
                                style: TextStyle(
                                    color: Colors.white.withAlpha(180),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Swatches — each item carries its own label so scrolling
                  // keeps colour + name aligned. Previously two parallel
                  // ListViews each owned their own scroll offset, so dragging
                  // the swatch row left the labels behind.
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: _kGradients.length,
                      itemBuilder: (_, i) {
                        final g   = _kGradients[i];
                        final sel = g.key == _gradKey;
                        return GestureDetector(
                          onTap: () => setState(() => _gradKey = g.key),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: g.colors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: sel ? Colors.white : Colors.transparent,
                                    width: 2.5,
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                              color: g.a.withAlpha(90),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2))
                                        ]
                                      : null,
                                ),
                                child: sel
                                    ? const Center(
                                        child: Icon(Icons.check,
                                            color: Colors.white, size: 16))
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 52,
                                child: Text(_gradientLabel(context, g.key),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                      color: sel
                                          ? MarginaliaColors.ink
                                          : MarginaliaColors.inkFaint,
                                    )),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Pattern picker ─────────────────────────────────────────
                  _SectionLabel(context.l10n.editProfilePatternLabel),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: _kPatterns.length,
                      itemBuilder: (_, i) {
                        final pk  = _kPatterns[i];
                        final sel = pk == _patKey;
                        return GestureDetector(
                          onTap: () => setState(() => _patKey = pk),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 64,
                            decoration: BoxDecoration(
                              color: sel
                                  ? MarginaliaColors.primaryFaint
                                  : MarginaliaColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? MarginaliaColors.primary
                                    : MarginaliaColors.rule,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Center(
                              child: pk == 'none'
                                  ? const Icon(Icons.block,
                                      size: 18, color: MarginaliaColors.inkFaint)
                                  : SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CustomPaint(
                                        painter: _PatternPainter(pk,
                                            color: MarginaliaColors.primary
                                                .withAlpha(120)),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: _kPatterns.length,
                      itemBuilder: (_, i) {
                        final pk  = _kPatterns[i];
                        final sel = pk == _patKey;
                        return SizedBox(
                          width: 64,
                          child: Text(
                            _patternLabel(context, pk),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel
                                  ? MarginaliaColors.primaryDark
                                  : MarginaliaColors.inkFaint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Save button ────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: MarginaliaColors.primary,
                        foregroundColor: const Color(0xFFF1EEE7),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.8, color: Color(0xFFF1EEE7)),
                            )
                          : Text(
                              context.l10n.save,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

class _GradientBox extends StatelessWidget {
  const _GradientBox({required this.gp, required this.pat});
  final _GP gp;
  final String pat;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gp.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        if (pat != 'none') CustomPaint(painter: _PatternPainter(pat)),
      ],
    );
  }
}

class _InitialText extends StatelessWidget {
  const _InitialText(this.initial);
  final String initial;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFFF1EEE7),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _PhotoBtn extends StatelessWidget {
  const _PhotoBtn({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child:
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 14),
                  const SizedBox(width: 5),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: MarginaliaColors.inkFaint,
          letterSpacing: 0.8,
        ),
      );
}

// ─── Username field with live availability feedback ───────────────────────────

class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.available,
    required this.checking,
    required this.onChanged,
  });
  final TextEditingController controller;
  final bool? available;   // null = not checked yet
  final bool  checking;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget? suffix;
    Color borderColor = MarginaliaColors.rule;

    if (checking) {
      suffix = const Padding(
        padding: EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: MarginaliaColors.inkFaint),
        ),
      );
    } else if (available == true) {
      suffix = const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Icon(Icons.check_circle_outline,
            size: 18, color: Color(0xFF4A7A35)),
      );
      borderColor = const Color(0xFF4A7A35);
    } else if (available == false) {
      suffix = const Padding(
        padding: EdgeInsets.only(right: 12),
        child: Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFBF4A4A)),
      );
      borderColor = const Color(0xFFBF4A4A);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MarginaliaColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              fontSize: 15,
              color: MarginaliaColors.ink,
              height: 1.4,
            ),
            decoration: InputDecoration(
              labelText: context.l10n.editProfileUsernameLabel,
              hintText: context.l10n.editProfileUsernameHint,
              prefixIcon: const Icon(Icons.alternate_email,
                  size: 18, color: MarginaliaColors.inkFaint),
              suffixIcon: suffix,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.fromLTRB(0, 14, 14, 14),
              labelStyle: const TextStyle(
                  color: MarginaliaColors.inkMuted, fontSize: 13),
            ),
          ),
        ),
        if (available == false)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 4),
            child: Text(
              context.l10n.editProfileUsernameUnavailable,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFBF4A4A),
                  fontWeight: FontWeight.w500),
            ),
          ),
        if (available == true)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 4),
            child: Text(
              context.l10n.editProfileUsernameAvailable,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF4A7A35),
                  fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MarginaliaColors.rule),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: 1,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 15,
          color: MarginaliaColors.ink,
          height: 1.4,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: MarginaliaColors.inkFaint),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
          labelStyle: const TextStyle(
            color: MarginaliaColors.inkMuted,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Pattern painter (same as in my_profile_screen.dart) ─────────────────────

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, {this.color});
  final String pattern;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to bounds so patterns don't bleed outside their container.
    canvas.clipRect(Offset.zero & size);

    final paint = Paint()
      ..color = (color ?? Colors.white).withAlpha(color != null ? 255 : 20)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    switch (pattern) {
      case 'dots':
        _dots(canvas, size, paint..style = PaintingStyle.fill);
      case 'lines':
        _lines(canvas, size, paint);
      case 'grid':
        _grid(canvas, size, paint);
      case 'circles':
        _circles(canvas, size, paint);
    }
  }

  void _dots(Canvas canvas, Size size, Paint paint) {
    const spacing = 22.0;
    const r = 1.4;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  void _lines(Canvas canvas, Size size, Paint paint) {
    const spacing = 20.0;
    final diag = size.width + size.height;
    for (double d = -size.height; d < size.width; d += spacing) {
      canvas.drawLine(Offset(d, 0), Offset(d + diag, diag), paint);
    }
  }

  void _grid(Canvas canvas, Size size, Paint paint) {
    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _circles(Canvas canvas, Size size, Paint paint) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    const step = 36.0;
    final maxR = math.sqrt(cx * cx + cy * cy) + step;
    for (double r = step; r < maxR; r += step) {
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.color != color;
}
