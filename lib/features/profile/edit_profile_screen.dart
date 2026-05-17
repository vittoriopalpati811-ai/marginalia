import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
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
  _GP('sepia',    'Seppia',   Color(0xFF6B4C3B), Color(0xFF2C1810)),
  _GP('forest',   'Foresta',  Color(0xFF2D5A3D), Color(0xFF132A1E)),
  _GP('ocean',    'Oceano',   Color(0xFF1A3A5C), Color(0xFF09141F)),
  _GP('dusk',     'Tramonto', Color(0xFF6B3A7A), Color(0xFF1A0B26)),
  _GP('rose',     'Rosa',     Color(0xFF7A3A4E), Color(0xFF2E1020)),
  _GP('graphite', 'Grafite',  Color(0xFF3C3C3C), Color(0xFF141414)),
  _GP('amber',    'Ambra',    Color(0xFF7A4E1A), Color(0xFF2C1A06)),
  _GP('slate',    'Ardesia',  Color(0xFF2A3A4E), Color(0xFF0D141E)),
];

_GP _gpFor(String key) =>
    _kGradients.firstWhere((g) => g.key == key, orElse: () => _kGradients.first);

const _kPatterns = ['none', 'dots', 'lines', 'grid', 'circles'];
const _kPatternLabels = {
  'none':    'Nessuno',
  'dots':    'Punti',
  'lines':   'Linee',
  'grid':    'Griglia',
  'circles': 'Cerchi',
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
  late final TextEditingController _readingTitleCtrl;
  late final TextEditingController _readingAuthorCtrl;

  late String _gradKey;
  late String _patKey;

  bool _uploadingAvatar = false;
  bool _uploadingCover  = false;
  bool _saving          = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl          = TextEditingController(text: p?['display_name'] as String? ?? '');
    _bioCtrl           = TextEditingController(text: p?['bio'] as String? ?? '');
    _readingTitleCtrl  = TextEditingController(text: p?['currently_reading_title'] as String? ?? '');
    _readingAuthorCtrl = TextEditingController(text: p?['currently_reading_author'] as String? ?? '');
    _gradKey = widget.initialGradient;
    _patKey  = widget.initialPattern;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _readingTitleCtrl.dispose();
    _readingAuthorCtrl.dispose();
    super.dispose();
  }

  // ── Photo helpers ────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final file = r.files.first;
    setState(() => _uploadingAvatar = true);
    try {
      await ref.read(supabaseServiceProvider).uploadAvatar(
            file.bytes!,
            (file.extension ?? 'jpg').toLowerCase(),
          );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto profilo aggiornata!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore upload: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickCover() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final file = r.files.first;
    setState(() => _uploadingCover = true);
    try {
      await ref.read(supabaseServiceProvider).uploadCover(
            file.bytes!,
            (file.extension ?? 'jpg').toLowerCase(),
          );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto copertina aggiornata!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore upload: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      await Future.wait([
        svc.updateProfileInfo(
          displayName: _nameCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
          currentlyReadingTitle:  _readingTitleCtrl.text.trim(),
          currentlyReadingAuthor: _readingAuthorCtrl.text.trim(),
        ),
        svc.updateProfileAppearance(_gradKey, _patKey),
      ]);
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore salvataggio: $e')));
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final gp  = _gpFor(_gradKey);
    final p   = widget.initialProfile;
    final avatarUrl = p?['avatar_url'] as String?;
    final coverUrl  = p?['cover_url']  as String?;
    final name      = _nameCtrl.text;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Top hero (cover preview + avatar) ─────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200 + top,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background (cover or gradient)
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    Image.network(coverUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _GradientBox(gp: gp, pat: _patKey))
                  else
                    _GradientBox(gp: gp, pat: _patKey),

                  // Dim overlay
                  Container(color: Colors.black.withAlpha(30)),

                  // Back + title bar
                  Positioned(
                    top: top + 4,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                        ),
                        const Expanded(
                          child: Text(
                            'Modifica profilo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // Change cover button
                        _PhotoBtn(
                          icon: Icons.image_outlined,
                          label: 'Copertina',
                          loading: _uploadingCover,
                          onTap: _pickCover,
                        ),
                      ],
                    ),
                  ),

                  // Avatar + change avatar button
                  Positioned(
                    left: 24,
                    bottom: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Avatar circle
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                MarginaliaDecorations.bookCoverColor(name),
                                gp.b,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                                color: Colors.white.withAlpha(70), width: 2.5),
                          ),
                          child: _uploadingAvatar
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 1.5))
                              : avatarUrl != null && avatarUrl.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(avatarUrl,
                                          fit: BoxFit.cover,
                                          width: 72,
                                          height: 72,
                                          errorBuilder: (_, __, ___) =>
                                              _InitialText(initial)))
                                  : _InitialText(initial),
                        ),
                        const SizedBox(width: 10),
                        _PhotoBtn(
                          icon: Icons.account_circle_outlined,
                          label: 'Foto',
                          loading: _uploadingAvatar,
                          onTap: _pickAvatar,
                        ),
                      ],
                    ),
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
                  _SectionLabel('INFORMAZIONI'),
                  const SizedBox(height: 10),

                  _Field(
                    controller: _nameCtrl,
                    label: 'Nome visualizzato',
                    hint: 'es. Marco Rossi',
                    icon: Icons.person_outline,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  _Field(
                    controller: _bioCtrl,
                    label: 'Bio',
                    hint: 'Racconta di te come lettore…',
                    icon: Icons.edit_note_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  _SectionLabel('IN LETTURA'),
                  const SizedBox(height: 10),

                  _Field(
                    controller: _readingTitleCtrl,
                    label: 'Titolo del libro',
                    hint: 'es. Il nome della rosa',
                    icon: Icons.menu_book_outlined,
                  ),
                  const SizedBox(height: 12),

                  _Field(
                    controller: _readingAuthorCtrl,
                    label: 'Autore',
                    hint: 'es. Umberto Eco',
                    icon: Icons.person_search_outlined,
                  ),
                  const SizedBox(height: 28),

                  // ── Gradient picker ────────────────────────────────────────
                  _SectionLabel('SFONDO PROFILO'),
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
                            child: Text('Anteprima',
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

                  // Swatches
                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: _kGradients.length,
                      itemBuilder: (_, i) {
                        final g   = _kGradients[i];
                        final sel = g.key == _gradKey;
                        return GestureDetector(
                          onTap: () => setState(() => _gradKey = g.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 52,
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
                      itemCount: _kGradients.length,
                      itemBuilder: (_, i) {
                        final g   = _kGradients[i];
                        final sel = g.key == _gradKey;
                        return SizedBox(
                          width: 52,
                          child: Text(g.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                color: sel
                                    ? MarginaliaColors.ink
                                    : MarginaliaColors.inkFaint,
                              )),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Pattern picker ─────────────────────────────────────────
                  _SectionLabel('PATTERN'),
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
                            _kPatternLabels[pk] ?? pk,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel
                                  ? MarginaliaColors.primary
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
                          : const Text(
                              'Salva',
                              style: TextStyle(
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
