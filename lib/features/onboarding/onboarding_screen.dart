import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/theme.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kTotalSteps = 7;

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;

  // Login mode flag (toggled from "Hai già un account? Accedi")
  bool _loginMode = false;

  // Step 1 — Auth
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _authLoading = false;
  String? _authError;

  // Step 2 — Username
  final _usernameCtrl = TextEditingController();
  bool? _usernameAvailable; // null = not checked, true = available, false = taken
  bool _usernameChecking = false;
  Timer? _usernameDebounce;

  // Step 3 — Display name
  final _nameCtrl = TextEditingController();

  // Step 4 — Avatar
  Uint8List? _avatarBytes;
  String? _avatarExt;

  // Step 5 — Cover
  Uint8List? _coverBytes;
  String? _coverExt;

  // Step 6 — Completing
  bool _completing = false;

  @override
  void dispose() {
    _pageController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goTo(int step) {
    if (!mounted) return;
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  void _next() => _goTo(_step + 1);

  // ── Step 1: Auth ────────────────────────────────────────────────────────────

  Future<void> _submitAuth() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      final svc = ref.read(supabaseServiceProvider);
      if (_loginMode) {
        await svc.signInWithEmail(email, password);
        // Check if profile already has username — if so skip to completion.
        final profile = await svc.fetchProfile();
        final hasUsername =
            (profile?['username'] as String?)?.isNotEmpty ?? false;
        if (!mounted) return;
        if (hasUsername) {
          // Pre-fill name from profile if available.
          final displayName = profile?['display_name'] as String? ?? '';
          if (displayName.isNotEmpty) _nameCtrl.text = displayName;
          _goTo(6); // jump straight to complete
        } else {
          _goTo(2); // let them pick a username
        }
      } else {
        final res = await svc.signUpWithEmail(email, password);
        if (!mounted) return;
        if (res.session == null) {
          // Email confirmation required.
          _showConfirmEmailDialog();
          return;
        }
        _goTo(2);
      }
    } on AuthException catch (e) {
      setState(() => _authError = _mapAuthError(e.message));
    } catch (e) {
      setState(() => _authError = 'Errore imprevisto. Riprova.');
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  void _showConfirmEmailDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Controlla la tua email'),
        content: Text(
          'Abbiamo inviato un link di conferma a ${_emailCtrl.text.trim()}.\n'
          'Clicca il link e poi torna ad accedere.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _loginMode = true);
            },
            child: const Text('Ok, vado ad accedere'),
          ),
        ],
      ),
    );
  }

  String _mapAuthError(String msg) {
    if (msg.contains('Invalid login')) return 'Email o password errati.';
    if (msg.contains('Email not confirmed')) {
      return 'Conferma la tua email prima di accedere.';
    }
    if (msg.contains('already registered')) {
      return 'Questa email è già registrata. Prova ad accedere.';
    }
    if (msg.contains('Password should be')) {
      return 'La password deve essere di almeno 6 caratteri.';
    }
    return msg;
  }

  // ── Step 2: Username availability check ─────────────────────────────────────

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    setState(() {
      _usernameAvailable = null;
      _usernameChecking = value.trim().isNotEmpty;
    });
    if (value.trim().isEmpty) return;
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      try {
        final available = await ref
            .read(supabaseServiceProvider)
            .isUsernameAvailable(value.trim());
        if (mounted) {
          setState(() {
            _usernameAvailable = available;
            _usernameChecking = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _usernameChecking = false);
      }
    });
  }

  // ── Step 4: Pick avatar ──────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? 'jpg').toLowerCase();
    setState(() {
      _avatarBytes = file.bytes;
      _avatarExt = ext;
    });
  }

  // ── Step 5: Pick cover ───────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? 'jpg').toLowerCase();
    setState(() {
      _coverBytes = file.bytes;
      _coverExt = ext;
    });
  }

  // ── Step 6: Complete ─────────────────────────────────────────────────────────

  Future<void> _complete() async {
    if (_completing) return;
    setState(() => _completing = true);
    HapticFeedback.mediumImpact();

    try {
      final svc = ref.read(supabaseServiceProvider);

      // Upload avatar if picked
      if (_avatarBytes != null) {
        await svc.uploadAvatar(_avatarBytes!, _avatarExt ?? 'jpg');
      }

      // Upload cover if picked
      if (_coverBytes != null) {
        await svc.uploadCover(_coverBytes!, _coverExt ?? 'jpg');
      }

      // Update profile (username + display name — avatar/cover already updated by upload methods)
      await svc.updateProfileInfo(
        displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        username:
            _usernameCtrl.text.trim().isEmpty ? null : _usernameCtrl.text.trim().toLowerCase(),
      );

      // Mark onboarding done
      await OnboardingService.markComplete();
      if (mounted) {
        ref.read(onboardingCompleteProvider.notifier).state = true;
      }
    } catch (_) {
      // Even on error, still mark complete — profile data can be edited later.
      await OnboardingService.markComplete();
      if (mounted) {
        ref.read(onboardingCompleteProvider.notifier).state = true;
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarginaliaColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            if (_step > 0) _ProgressDots(current: _step, total: _kTotalSteps),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomeStep(
                    onStart: _next,
                    onLogin: () {
                      setState(() => _loginMode = true);
                      _next();
                    },
                  ),
                  _AuthStep(
                    loginMode: _loginMode,
                    emailCtrl: _emailCtrl,
                    passwordCtrl: _passwordCtrl,
                    obscurePassword: _obscurePassword,
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    loading: _authLoading,
                    error: _authError,
                    onSubmit: _submitAuth,
                  ),
                  _UsernameStep(
                    usernameCtrl: _usernameCtrl,
                    available: _usernameAvailable,
                    checking: _usernameChecking,
                    onChanged: _onUsernameChanged,
                    onContinue: _next,
                    onSkip: _next,
                  ),
                  _NameStep(
                    nameCtrl: _nameCtrl,
                    onContinue: _next,
                    onSkip: _next,
                  ),
                  _AvatarStep(
                    avatarBytes: _avatarBytes,
                    onPickAvatar: _pickAvatar,
                    onContinue: _next,
                    onSkip: _next,
                  ),
                  _CoverStep(
                    coverBytes: _coverBytes,
                    onPickCover: _pickCover,
                    onContinue: _next,
                    onSkip: _next,
                  ),
                  _CompleteStep(
                    username: _usernameCtrl.text.trim(),
                    completing: _completing,
                    onEnter: _complete,
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

// ─── Progress dots ─────────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? MarginaliaColors.primary
                  : MarginaliaColors.primary.withAlpha(50),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Step 0: Welcome ─────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onStart, required this.onLogin});
  final VoidCallback onStart;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: MarginaliaColors.primary.withAlpha(40),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.auto_stories,
              size: 48,
              color: MarginaliaColors.primary,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, curve: Curves.easeOut)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1), duration: 500.ms),

          const SizedBox(height: 28),

          // Title
          Text(
            'Marginalia',
            style: GoogleFonts.ebGaramond(
              fontSize: 48,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -1.0,
              height: 1,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms, curve: Curves.easeOut),

          const SizedBox(height: 10),

          // Subtitle
          Text(
            'Riscopri quello che hai letto.',
            style: GoogleFonts.barlow(
              fontSize: 15,
              color: MarginaliaColors.inkMuted,
              fontWeight: FontWeight.w400,
            ),
          )
              .animate()
              .fadeIn(delay: 180.ms, duration: 400.ms, curve: Curves.easeOut),

          const SizedBox(height: 52),

          // CTA button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: onStart,
              child: Text(
                'Inizia →',
                style: GoogleFonts.barlow(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 260.ms, duration: 400.ms, curve: Curves.easeOut)
              .slideY(begin: 0.1, end: 0, delay: 260.ms, duration: 400.ms),

          const SizedBox(height: 16),

          // Login link
          TextButton(
            onPressed: onLogin,
            child: Text(
              'Hai già un account? Accedi',
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: MarginaliaColors.inkMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 320.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

// ─── Step 1: Auth ────────────────────────────────────────────────────────────

class _AuthStep extends StatelessWidget {
  const _AuthStep({
    required this.loginMode,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final bool loginMode;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            loginMode ? 'Accedi' : 'Crea il tuo account',
            style: GoogleFonts.ebGaramond(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),

          Text(
            loginMode
                ? 'Bentornato in Marginalia.'
                : 'Il tuo profilo letterario ti aspetta.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 50.ms, duration: 250.ms),

          const SizedBox(height: 32),

          // Email field
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          const SizedBox(height: 14),

          // Password field
          TextField(
            controller: passwordCtrl,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: onToggleObscure,
              ),
            ),
          ).animate().fadeIn(delay: 120.ms, duration: 250.ms),

          // Error
          if (error != null) ...[
            const SizedBox(height: 14),
            _ErrorBanner(message: error!),
          ],

          const SizedBox(height: 28),

          // Submit button
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Continua →',
                      style: GoogleFonts.barlow(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ).animate().fadeIn(delay: 160.ms, duration: 250.ms),
        ],
      ),
    );
  }
}

// ─── Step 2: Username ────────────────────────────────────────────────────────

class _UsernameStep extends StatelessWidget {
  const _UsernameStep({
    required this.usernameCtrl,
    required this.available,
    required this.checking,
    required this.onChanged,
    required this.onContinue,
    required this.onSkip,
  });

  final TextEditingController usernameCtrl;
  final bool? available;
  final bool checking;
  final ValueChanged<String> onChanged;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  Widget _suffixIcon() {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (available == true) {
      return const Icon(Icons.check_circle, color: Color(0xFF4A7A35), size: 20);
    }
    if (available == false) {
      return const Icon(Icons.cancel, color: Color(0xFFDC2626), size: 20);
    }
    return const SizedBox.shrink();
  }

  bool get _canContinue =>
      usernameCtrl.text.trim().isNotEmpty && available == true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            'Scegli il tuo @username',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            'Gli altri ti troveranno con questo nome.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          TextField(
            controller: usernameCtrl,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'username',
              prefixText: '@',
              prefixStyle: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.primary,
              ),
              suffixIcon: _suffixIcon(),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          if (available == false) ...[
            const SizedBox(height: 8),
            Text(
              'Username già in uso. Prova un altro.',
              style: GoogleFonts.barlow(
                fontSize: 12,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _canContinue ? onContinue : null,
              child: Text(
                'Continua →',
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: onSkip,
            child: Text(
              'Salta',
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Step 3: Display name ─────────────────────────────────────────────────────

class _NameStep extends StatelessWidget {
  const _NameStep({
    required this.nameCtrl,
    required this.onContinue,
    required this.onSkip,
  });

  final TextEditingController nameCtrl;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            'Come ti chiami?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            'Questo nome apparirà sul tuo profilo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onContinue(),
            decoration: const InputDecoration(
              hintText: 'Il tuo nome',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(
                'Continua →',
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: onSkip,
            child: Text(
              'Salta',
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Step 4: Avatar ───────────────────────────────────────────────────────────

class _AvatarStep extends StatelessWidget {
  const _AvatarStep({
    required this.avatarBytes,
    required this.onPickAvatar,
    required this.onContinue,
    required this.onSkip,
  });

  final Uint8List? avatarBytes;
  final VoidCallback onPickAvatar;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            'Aggiungi una foto profilo',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            'Facoltativa, puoi aggiungerla in seguito.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 40),

          // Avatar circle
          Center(
            child: GestureDetector(
              onTap: onPickAvatar,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MarginaliaColors.primaryFaint,
                  border: Border.all(
                    color: MarginaliaColors.primary,
                    width: 2,
                  ),
                  image: avatarBytes != null
                      ? DecorationImage(
                          image: MemoryImage(avatarBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: avatarBytes == null
                    ? const Icon(
                        Icons.person,
                        size: 64,
                        color: MarginaliaColors.primary,
                      )
                    : null,
              ),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 300.ms).scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1, 1),
                delay: 80.ms,
                duration: 300.ms,
              ),

          const SizedBox(height: 24),

          // Pick button
          Center(
            child: OutlinedButton.icon(
              onPressed: onPickAvatar,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                'Scegli foto',
                style: GoogleFonts.barlow(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MarginaliaColors.primary,
                side: const BorderSide(color: MarginaliaColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(
                'Continua →',
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: onSkip,
            child: Text(
              'Salta',
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Step 5: Cover ────────────────────────────────────────────────────────────

class _CoverStep extends StatelessWidget {
  const _CoverStep({
    required this.coverBytes,
    required this.onPickCover,
    required this.onContinue,
    required this.onSkip,
  });

  final Uint8List? coverBytes;
  final VoidCallback onPickCover;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          Text(
            'Aggiungi una foto copertina',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            'Appare in cima al tuo profilo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          // Cover placeholder — 16:7 aspect ratio
          GestureDetector(
            onTap: onPickCover,
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Container(
                decoration: BoxDecoration(
                  color: MarginaliaColors.primaryFaint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: MarginaliaColors.primary,
                    width: 1.5,
                  ),
                  image: coverBytes != null
                      ? DecorationImage(
                          image: MemoryImage(coverBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: coverBytes == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_outlined,
                              size: 36,
                              color: MarginaliaColors.primary.withAlpha(160),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Foto copertina',
                              style: GoogleFonts.barlow(
                                fontSize: 13,
                                color: MarginaliaColors.primary.withAlpha(160),
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 300.ms),

          const SizedBox(height: 20),

          Center(
            child: OutlinedButton.icon(
              onPressed: onPickCover,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                'Scegli immagine',
                style: GoogleFonts.barlow(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MarginaliaColors.primary,
                side: const BorderSide(color: MarginaliaColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(
                'Continua →',
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: onSkip,
            child: Text(
              'Salta',
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Step 6: Complete ─────────────────────────────────────────────────────────

class _CompleteStep extends StatefulWidget {
  const _CompleteStep({
    required this.username,
    required this.completing,
    required this.onEnter,
  });

  final String username;
  final bool completing;
  final VoidCallback onEnter;

  @override
  State<_CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends State<_CompleteStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _checkScale = CurvedAnimation(
      parent: _checkCtrl,
      curve: Curves.elasticOut,
    );
    // Start the animation after a short delay so the page slide finishes first.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _checkCtrl.forward();
    });
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayUsername =
        widget.username.isNotEmpty ? '@${widget.username}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Animated checkmark
          Center(
            child: ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: MarginaliaColors.primaryFaint,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MarginaliaColors.primary.withAlpha(60),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 52,
                  color: MarginaliaColors.primary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Tutto pronto! 🎉',
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 350.ms),

          const SizedBox(height: 10),

          Text(
            displayUsername.isNotEmpty
                ? 'Benvenuto in Marginalia, $displayUsername'
                : 'Benvenuto in Marginalia',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 15,
              color: MarginaliaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 500.ms, duration: 350.ms),

          const SizedBox(height: 52),

          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: widget.completing ? null : widget.onEnter,
              child: widget.completing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Entra nella tua libreria →',
                      style: GoogleFonts.barlow(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ).animate().fadeIn(delay: 600.ms, duration: 350.ms),
        ],
      ),
    );
  }
}

// ─── Shared: Error banner ─────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.barlow(
                color: const Color(0xFFDC2626),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).shake(duration: 300.ms);
  }
}
