import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/onboarding_provider.dart';
import '../../core/providers/health_provider.dart';
import '../../core/providers/calendar_provider.dart';
import '../../core/services/gender_service.dart';
import '../../core/services/locale_service.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/theme.dart';
import '../auth/email_otp_screen.dart';
import 'shared/social_auth_buttons.dart';
import 'steps/reading_goal_step.dart';
import 'steps/currently_reading_step.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kTotalSteps = 11;
// Step indices (keep in sync with the PageView children below):
// 0: Welcome   · 1: Auth   · 2: Username  · 3: Name   · 4: Avatar
// 5: Cover     · 6: Goal   · 7: Currently · 8: Permissions · 9: Gender · 10: Complete
const _kStepComplete = 10;

// ─── Screen ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;

  // Language selection is the very first thing shown — before the PageView.
  // Once chosen it persists and the onboarding slides appear.
  bool _languageChosen = false;

  // Login mode flag (toggled from "Hai già un account? Accedi")
  bool _loginMode = false;

  // Auth auto-advance: listens for AuthChangeEvent.signedIn so that a user who
  // signs in WHILE on the Welcome/Auth steps doesn't land back on the Welcome
  // screen. Covers Google/Apple OAuth (returns via deep link) AND email
  // login/signup-confirmation — without this they'd be bounced to the auth step
  // forever. The actual advance is funnelled through [_continueAfterSignIn].
  StreamSubscription<AuthState>? _authSub;
  bool _handlingSignIn = false;

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
  bool _pickingAvatar = false;

  // Step 5 — Cover
  Uint8List? _coverBytes;
  String? _coverExt;
  bool _pickingCover = false;

  // Step 6 — Reading goal
  final _goalCtrl = TextEditingController(text: '15');

  // Step 7 — Currently reading
  final _crTitleCtrl  = TextEditingController();
  final _crAuthorCtrl = TextEditingController();

  // Step 9 — Gender (privacy-sensitive, stored ONLY on-device)
  // 'female' | 'male' | 'unspecified', or null until the user chooses.
  String? _gender;

  // Step 10 — Completing
  bool _completing = false;

  @override
  void initState() {
    super.initState();

    // Any signedIn event while we sit on a pre-auth step means the user just
    // authenticated (OAuth deep-link return, OR an email login whose session
    // lands without us driving the navigation). Auto-advance past Welcome+Auth
    // to the next required step. The email signup→OTP path drives the advance
    // itself via [_continueAfterSignIn] (and sets _handlingSignIn first), so the
    // guard below stops this listener from double-advancing.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event != AuthChangeEvent.signedIn) return;
      if (_handlingSignIn) return;
      // Only act if we're still on a pre-auth step (Welcome=0 or Auth=1).
      if (_step > 1) return;
      _continueAfterSignIn();
    });
  }

  /// Advances the onboarding once a session exists, regardless of HOW the user
  /// signed in (OAuth, email login, or email-confirmation OTP). Returning users
  /// with a complete profile skip straight to Complete; new users start at the
  /// Username step. Idempotent-guarded via [_handlingSignIn] so the auth
  /// listener and an explicit caller can't both run it.
  Future<void> _continueAfterSignIn() async {
    if (_handlingSignIn) return;
    _handlingSignIn = true;
    try {
      final svc = ref.read(supabaseServiceProvider);
      final profile = await svc.fetchProfile();
      final hasUsername =
          (profile?['username'] as String?)?.isNotEmpty ?? false;
      if (!mounted) return;
      // Pre-fill display name from existing profile if any
      final displayName = profile?['display_name'] as String? ?? '';
      if (displayName.isNotEmpty && _nameCtrl.text.isEmpty) {
        _nameCtrl.text = displayName;
      }
      // Returning user with full profile → straight to Complete
      // New user → start with Username (step 2)
      _goTo(hasUsername ? _kStepComplete : 2);
    } catch (_) {
      // If we can't load the profile, advance to Username step anyway so
      // the user isn't stuck on Welcome.
      if (mounted) _goTo(2);
    } finally {
      _handlingSignIn = false;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _pageController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    _crTitleCtrl.dispose();
    _crAuthorCtrl.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  // ── Language selection ───────────────────────────────────────────────────────

  Future<void> _onLanguageChosen(Locale locale) async {
    // Persist and apply immediately — the whole app re-renders in the chosen language.
    await LocaleService.setLocale(locale);
    if (mounted) {
      ref.read(localeProvider.notifier).state = locale;
      setState(() => _languageChosen = true);
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goTo(int step) {
    if (!mounted) return;
    setState(() => _step = step);
    // The PageView uses NeverScrollableScrollPhysics, so animateToPage is the
    // ONLY way to move the visible page. On the OAuth deep-link return the app
    // resumes and the signedIn event can fire BEFORE the PageView is laid out
    // again — at which point the controller has no clients and animateToPage
    // throws, leaving the page stuck on Auth while _step has already advanced
    // (the "stuck after Apple/Google login, must reopen" bug). Animate only
    // when the controller is attached; otherwise defer to the next frame and
    // jump (there is no client to animate from) so the page always catches up.
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(step);
      });
    }
  }

  void _next() => _goTo(_step + 1);

  // Triggers the iOS Health + Calendar permission prompts from the permissions
  // onboarding step, so the system sheets appear WITH context (the step explains
  // why) instead of silently on first library load.
  Future<void> _requestContextPermissions() async {
    try {
      await requestHealthPermissions();
    } catch (_) {/* non-fatal */}
    try {
      // Reading the provider runs CalendarService.fetchTodayEvents(), which
      // triggers the EventKit permission prompt.
      await ref.read(calendarSnapshotProvider.future);
    } catch (_) {/* non-fatal */}
  }

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
        // Email LOGIN. Drive the advance ourselves (set the guard first so the
        // auth listener's signedIn event doesn't race us). _continueAfterSignIn
        // sends returning users straight to Complete, new ones to Username.
        _handlingSignIn = true;
        await svc.signInWithEmail(email, password);
        if (!mounted) {
          _handlingSignIn = false;
          return;
        }
        _handlingSignIn = false;
        await _continueAfterSignIn();
      } else {
        final res = await svc.signUpWithEmail(email, password);
        if (!mounted) return;
        if (res.session == null) {
          // Email confirmation required → take the user straight to in-app OTP
          // entry (no go_router mounted yet, so we pass onVerified and continue
          // the onboarding ourselves once the code is verified). Typing the
          // 6-digit code is far more reliable on mobile than a magic link.
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EmailOtpScreen(
              email: email,
              onVerified: _continueAfterSignIn,
            ),
          ));
          return;
        }
        // Confirmation disabled → session already exists; continue straight on.
        await _continueAfterSignIn();
      }
    } on AuthException catch (e) {
      _handlingSignIn = false;
      setState(() => _authError = _mapAuthError(e.message, context));
    } catch (e) {
      _handlingSignIn = false;
      setState(() => _authError = context.l10n.authErrGeneric);
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  String _mapAuthError(String msg, BuildContext ctx) {
    final l = ctx.l10n;
    if (msg.contains('Invalid login')) return l.authErrInvalidLogin;
    if (msg.contains('Email not confirmed')) return l.authErrNotConfirmed;
    if (msg.contains('already registered')) return l.authErrAlreadyRegistered;
    if (msg.contains('Password should be')) return l.authErrWeakPassword;
    // "Non dire più del dovuto": don't surface the raw server error string.
    return l.authErrGeneric;
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
  //
  // On web, `withData: true` reads the entire file into a Uint8List
  // synchronously after the user picks. iPhone photos can be 5-10 MB, which
  // blocks for 1-3 seconds with no visible feedback (the iOS file sheet has
  // already dismissed). We surface a loading state so the user understands
  // the wait, and guard against double-taps while the read is in flight.

  Future<void> _pickAvatar() async {
    if (_pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      if (!mounted) return;
      setState(() {
        _avatarBytes = file.bytes;
        _avatarExt = ext;
      });
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  // ── Step 5: Pick cover ───────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    if (_pickingCover) return;
    setState(() => _pickingCover = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      if (!mounted) return;
      setState(() {
        _coverBytes = file.bytes;
        _coverExt = ext;
      });
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  // ── Step 6: Complete ─────────────────────────────────────────────────────────

  Future<void> _complete() async {
    if (_completing) return;
    setState(() => _completing = true);
    HapticFeedback.mediumImpact();

    // Privacy-sensitive: persist the chosen gender ONLY on-device. Done first
    // (and outside the Supabase calls) so the local write happens even if a
    // later network step fails. GenderService.write is internally guarded.
    await GenderService.write(_gender ?? 'unspecified');

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

      // Mirror the (otherwise on-device-only) gender choice to the profile so
      // the server can tailor recommendations. The DB column is 'f' | 'm' | null:
      // 'unspecified' and a skipped choice both map to null (we never store the
      // "prefer not to say" answer server-side). The on-device GenderService copy
      // written in _complete() above stays the source of truth for local UI.
      try {
        final genderForProfile = switch (_gender) {
          'female' => 'f',
          'male' => 'm',
          _ => null,
        };
        await svc.updateProfileGender(genderForProfile);
      } catch (_) {
        // Non-fatal — gender personalisation still works from the local copy.
      }

      // Save annual reading goal if user entered a valid number
      final goalText  = _goalCtrl.text.trim();
      final goalValue = int.tryParse(goalText);
      if (goalValue != null && goalValue > 0 && goalValue < 1000) {
        try {
          await svc.saveReadingGoal(
            year: DateTime.now().year,
            targetBooks: goalValue,
          );
        } catch (_) {
          // Goal save is non-fatal — user can set it later from stats screen.
        }
      }

      // Save "currently reading" if user entered a title
      final crTitle = _crTitleCtrl.text.trim();
      if (crTitle.isNotEmpty) {
        try {
          await svc.updateCurrentlyReading(
            title: crTitle,
            author: _crAuthorCtrl.text.trim().isEmpty
                ? null
                : _crAuthorCtrl.text.trim(),
          );
        } catch (_) { /* non-fatal */ }
      }

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
      backgroundColor: ScriptaColors.surface,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
          child: !_languageChosen
              ? _LanguageStep(
                  key: const ValueKey('language'),
                  onChosen: _onLanguageChosen,
                )
              : Column(
                  key: const ValueKey('onboarding'),
                  children: [
                    // Progress dots
                    if (_step > 0) _ProgressDots(current: _step, total: _kTotalSteps),

                    // Pages
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                  _StepScroll(child: _WelcomeStep(
                    onStart: _next,
                    onLogin: () {
                      setState(() => _loginMode = true);
                      _next();
                    },
                  )),
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
                  _StepScroll(child: _UsernameStep(
                    usernameCtrl: _usernameCtrl,
                    available: _usernameAvailable,
                    checking: _usernameChecking,
                    onChanged: _onUsernameChanged,
                    onContinue: _next,
                    onSkip: _next,
                  )),
                  _StepScroll(child: _NameStep(
                    nameCtrl: _nameCtrl,
                    onContinue: _next,
                    onSkip: _next,
                  )),
                  _StepScroll(child: _AvatarStep(
                    avatarBytes: _avatarBytes,
                    picking:     _pickingAvatar,
                    onPickAvatar: _pickAvatar,
                    onContinue: _next,
                    onSkip: _next,
                  )),
                  _StepScroll(child: _CoverStep(
                    coverBytes: _coverBytes,
                    picking:    _pickingCover,
                    onPickCover: _pickCover,
                    onContinue: _next,
                    onSkip: _next,
                  )),
                  _StepScroll(child: ReadingGoalStep(
                    goalCtrl: _goalCtrl,
                    onContinue: _next,
                    onSkip: _next,
                  )),
                  CurrentlyReadingStep(
                    titleCtrl:  _crTitleCtrl,
                    authorCtrl: _crAuthorCtrl,
                    onContinue: _next,
                    onSkip:     _next,
                  ),
                  _StepScroll(child: _PermissionsStep(
                    onAllow: () async {
                      await _requestContextPermissions();
                      _next();
                    },
                    onSkip: _next,
                  )),
                  _StepScroll(child: _GenderStep(
                    selected: _gender,
                    onSelect: (g) {
                      setState(() => _gender = g);
                      ref.read(genderProvider.notifier).state = g;
                      _next();
                    },
                  )),
                  _StepScroll(child: _CompleteStep(
                    username: _usernameCtrl.text.trim(),
                    completing: _completing,
                    onEnter: _complete,
                  )),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ─── Step −1: Language selection (pre-step) ──────────────────────────────────
//
// Shown BEFORE the onboarding PageView.
// Both languages are displayed in their own script — no translation needed.
// Cards use a soft press + scale animation; the whole screen fades out once
// a language is chosen.

class _LanguageStep extends StatefulWidget {
  const _LanguageStep({super.key, required this.onChosen});
  final Future<void> Function(Locale) onChosen;

  @override
  State<_LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends State<_LanguageStep> {
  String? _choosing; // language code being animated, null = idle

  Future<void> _choose(String code) async {
    if (_choosing != null) return;
    setState(() => _choosing = code);
    HapticFeedback.lightImpact();
    // Small pause so the press-state is visible before transition.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await widget.onChosen(Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // ── Brand mark — the very first thing a new reader sees ──────────
          const ScriptaMark(size: 84)
              .animate()
              .fadeIn(duration: 700.ms, curve: Curves.easeOut)
              .scale(
                begin: const Offset(0.82, 0.82),
                end: const Offset(1, 1),
                duration: 700.ms,
                curve: Curves.easeOutBack,
              ),

          const SizedBox(height: 22),

          // ── Wordmark ──────────────────────────────────────────────────────
          Text(
            'Scripta',
            style: GoogleFonts.ebGaramond(
              fontSize: 44,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -1.0,
              height: 1,
            ),
          )
              .animate()
              .fadeIn(delay: 120.ms, duration: 700.ms, curve: Curves.easeOut)
              .slideY(
                  begin: -0.06,
                  end: 0,
                  delay: 120.ms,
                  duration: 700.ms,
                  curve: Curves.easeOut),

          const SizedBox(height: 8),

          // ── Thin rule ─────────────────────────────────────────────────────
          Container(
            height: 0.8,
            width: 160,
            color: ScriptaColors.ruleFaint,
          )
              .animate()
              .fadeIn(delay: 150.ms, duration: 500.ms),

          const SizedBox(height: 36),

          // ── Prompt ────────────────────────────────────────────────────────
          Text(
            context.l10n.onboardingLangChoose,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: ScriptaColors.inkFaint,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w500,
            ),
          )
              .animate()
              .fadeIn(delay: 220.ms, duration: 500.ms),

          const Spacer(flex: 1),

          // ── Language cards ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _LangCard(
                  code: 'it',
                  label: 'Italiano',
                  sublabel: 'Italian',
                  emoji: '🇮🇹',
                  delay: 340.ms,
                  isSelected: _choosing == 'it',
                  isDisabled: _choosing != null && _choosing != 'it',
                  onTap: () => _choose('it'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _LangCard(
                  code: 'en',
                  label: 'English',
                  sublabel: 'Inglese',
                  emoji: '🇬🇧',
                  delay: 440.ms,
                  isSelected: _choosing == 'en',
                  isDisabled: _choosing != null && _choosing != 'en',
                  onTap: () => _choose('en'),
                ),
              ),
            ],
          ),

          const Spacer(flex: 3),

          // ── Footnote ─────────────────────────────────────────────────────
          Text(
            context.l10n.onboardingLangChangeLater,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: ScriptaColors.inkFaint,
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .fadeIn(delay: 600.ms, duration: 500.ms),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    required this.code,
    required this.label,
    required this.sublabel,
    required this.emoji,
    required this.delay,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  final String code;
  final String label;
  final String sublabel;
  final String emoji;
  final Duration delay;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..scale(isSelected ? 1.04 : (isDisabled ? 0.96 : 1.0)),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? ScriptaColors.primaryFaint
              : ScriptaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? ScriptaColors.primary
                : ScriptaColors.rule,
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: ScriptaColors.primary.withAlpha(30),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x0A261E1D),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isDisabled ? 0.35 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                // Flag emoji
                Text(emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 14),
                // Language name in its own language
                Text(
                  label,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? ScriptaColors.primaryDark
                        : ScriptaColors.ink,
                    letterSpacing: -0.3,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                // Subtitle in the OTHER language
                Text(
                  sublabel,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: ScriptaColors.inkFaint,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: delay, duration: 500.ms, curve: Curves.easeOut)
        .slideY(
          begin: 0.12,
          end: 0,
          delay: delay,
          duration: 500.ms,
          curve: Curves.easeOutCubic,
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
                  ? ScriptaColors.primary
                  : ScriptaColors.primary.withAlpha(50),
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
    // Airbnb-style staggered entrance: logo → wordmark → subtitle → CTA → login
    // link, each ~50 ms apart with deep easeOutQuart fade + slight slideY.
    // Press feedback via PressableSpring on the primary CTA.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StaggeredListItem(
            index: 0,
            duration: AirbnbMotion.longForm,
            // The real brand mark with a slow, gentle float — alive but calm,
            // the "memorabile" anchor of the welcome moment.
            child: const ScriptaMark(size: 104)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(
                  begin: -3,
                  end: 3,
                  duration: 2600.ms,
                  curve: Curves.easeInOut,
                ),
          ),

          const SizedBox(height: 28),

          StaggeredListItem(
            index: 1,
            child: Text(
              'Scripta',
              style: GoogleFonts.ebGaramond(
                fontSize: 48,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.ink,
                letterSpacing: -1.0,
                height: 1,
              ),
            ),
          ),

          const SizedBox(height: 10),

          StaggeredListItem(
            index: 2,
            child: Text(
              context.l10n.onboardingWelcomeSubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: ScriptaColors.inkMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          const SizedBox(height: 52),

          StaggeredListItem(
            index: 3,
            child: PressableSpring(
              onPressed: onStart,
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ScriptaColors.primary,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(
                  context.l10n.onboardingStart,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          StaggeredListItem(
            index: 4,
            child: TextButton(
              onPressed: onLogin,
              child: Text(
                context.l10n.onboardingHaveAccount,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: ScriptaColors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 1: Auth (social-first, mandatory) ──────────────────────────────────
//
// Layout (Airbnb-style — social buttons first, email collapsible below):
//   - Editorial heading + subtitle
//   - 3 social pills (Apple / Google / Phone) — staggered cascade entrance
//   - "oppure" divider
//   - "Continua con email" toggle → reveals email/password block
//
// There is no "skip" option here: account creation is required to continue
// past this screen. The router-level OnboardingScreen owns the only way out.

class _AuthStep extends ConsumerStatefulWidget {
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
  ConsumerState<_AuthStep> createState() => _AuthStepState();
}

class _AuthStepState extends ConsumerState<_AuthStep> {
  bool _emailExpanded = false;
  bool _socialLoading = false;
  String? _socialError;

  Future<void> _runSocial(Future<dynamic> Function() op) async {
    if (_socialLoading) return;
    setState(() {
      _socialLoading = true;
      _socialError   = null;
    });
    try {
      await op();
    } catch (e) {
      if (!mounted) return;
      // Specific case: provider not enabled in Supabase dashboard.
      // Until Google OAuth credentials are configured, give the user a
      // helpful nudge instead of a generic "sign-in failed".
      final msg = e.toString().toLowerCase();
      final isProviderNotEnabled = msg.contains('provider is not enabled') ||
          msg.contains('unsupported provider') ||
          msg.contains('provider_not_enabled');
      setState(() => _socialError = isProviderNotEnabled
          ? context.l10n.authProviderNotEnabled
          : context.l10n.authOauthFailed);
    } finally {
      if (mounted) setState(() => _socialLoading = false);
    }
  }

  Future<void> _onGoogle() async {
    if (_socialLoading) return;
    setState(() {
      _socialLoading = true;
      _socialError   = null;
    });
    final svc = ref.read(supabaseServiceProvider);
    // Pre-flight: if Google OAuth isn't enabled in Supabase, calling
    // signInWithOAuth would redirect the browser to a raw JSON error page
    // on the Supabase domain ("Unsupported provider: provider is not
    // enabled") — which the user has no way to dismiss. Detect that case
    // here and show the friendly inline message instead.
    final enabled = await svc.isOAuthProviderEnabled('google');
    if (!mounted) return;
    if (!enabled) {
      setState(() {
        _socialLoading = false;
        _socialError   = context.l10n.authProviderNotEnabled;
      });
      return;
    }
    setState(() => _socialLoading = false);
    await _runSocial(svc.signInWithGoogle);
  }

  Future<void> _onApple() async {
    if (_socialLoading) return;
    setState(() {
      _socialLoading = true;
      _socialError   = null;
    });
    final svc = ref.read(supabaseServiceProvider);
    // Same pre-flight as Google: a friendly inline message instead of the raw
    // Supabase JSON error page when the provider isn't configured yet.
    final enabled = await svc.isOAuthProviderEnabled('apple');
    if (!mounted) return;
    if (!enabled) {
      setState(() {
        _socialLoading = false;
        _socialError   = context.l10n.authProviderNotEnabled;
      });
      return;
    }
    setState(() => _socialLoading = false);
    await _runSocial(svc.signInWithApple);
  }

  // Phone/SMS removed entirely — no Twilio dependency at launch. Will be
  // reintroduced if/when an SMS provider becomes cost-effective.

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // ── Editorial heading ────────────────────────────────────────────
          Text(
            widget.loginMode
                ? context.l10n.onboardingAuthLoginTitle
                : context.l10n.onboardingAuthCreateTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(duration: AirbnbMotion.standard, curve: AirbnbMotion.enter),

          const SizedBox(height: 6),

          Text(
            widget.loginMode
                ? context.l10n.onboardingAuthLoginSubtitle
                : context.l10n.onboardingAuthCreateSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 60.ms, duration: AirbnbMotion.standard),

          const SizedBox(height: 28),

          // ── Social auth (Apple first per HIG, then Google) ───────────────
          SocialAuthButtons(
            loading: _socialLoading,
            appleLabel: context.l10n.authContinueWithApple,
            onApple: _onApple,
            googleLabel: context.l10n.authContinueWithGoogle,
            onGoogle: _onGoogle,
          ),

          if (_socialError != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _socialError!),
          ],

          const SizedBox(height: 22),

          // ── "oppure" divider ─────────────────────────────────────────────
          Row(
            children: [
              const Expanded(child: Divider(color: ScriptaColors.rule, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  context.l10n.authOrDivider,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ScriptaColors.inkFaint,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: ScriptaColors.rule, height: 1)),
            ],
          ).animate().fadeIn(delay: 220.ms, duration: AirbnbMotion.standard),

          const SizedBox(height: 14),

          // ── Email toggle / form ──────────────────────────────────────────
          AnimatedSize(
            duration: AirbnbMotion.standard,
            curve: AirbnbMotion.enter,
            child: _emailExpanded
                ? _EmailForm(
                    emailCtrl: widget.emailCtrl,
                    passwordCtrl: widget.passwordCtrl,
                    obscurePassword: widget.obscurePassword,
                    onToggleObscure: widget.onToggleObscure,
                    loading: widget.loading,
                    error: widget.error,
                    onSubmit: widget.onSubmit,
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton.icon(
                      icon: const Icon(Icons.email_outlined, size: 18),
                      label: Text(context.l10n.authContinueWithEmail),
                      style: TextButton.styleFrom(
                        foregroundColor: ScriptaColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => setState(() => _emailExpanded = true),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool                  obscurePassword;
  final VoidCallback          onToggleObscure;
  final bool                  loading;
  final String?               error;
  final VoidCallback          onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: context.l10n.authEmail,
            prefixIcon: const Icon(Icons.email_outlined),
            filled: true,
            fillColor: ScriptaColors.surfaceElevated,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: ScriptaColors.primaryDark, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordCtrl,
          obscureText: obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: context.l10n.authPassword,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onToggleObscure,
            ),
            filled: true,
            fillColor: ScriptaColors.surfaceElevated,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: ScriptaColors.primaryDark, width: 1.5),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(message: error!),
        ],
        const SizedBox(height: 20),
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
                    context.l10n.onboardingContinue,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
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
            context.l10n.onboardingUsernameTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            context.l10n.onboardingUsernameSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          TextField(
            controller: usernameCtrl,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: context.l10n.onboardingLangUsernameHint,
              prefixText: '@',
              prefixStyle: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                color: ScriptaColors.primaryDark,
              ),
              suffixIcon: _suffixIcon(),
              filled: true,
              fillColor: ScriptaColors.surfaceElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: ScriptaColors.primaryDark, width: 1.5),
              ),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          if (available == false) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.onboardingUsernameTaken,
              style: GoogleFonts.manrope(
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
                context.l10n.onboardingContinue,
                style: GoogleFonts.manrope(
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
              context.l10n.onboardingSkip,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
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
            context.l10n.onboardingNameTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            context.l10n.onboardingNameSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onContinue(),
            decoration: InputDecoration(
              hintText: context.l10n.authName,
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),

          const Spacer(),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(
                context.l10n.onboardingContinue,
                style: GoogleFonts.manrope(
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
              context.l10n.onboardingSkip,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
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
    required this.picking,
    required this.onPickAvatar,
    required this.onContinue,
    required this.onSkip,
  });

  final Uint8List?   avatarBytes;
  final bool         picking;
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
            context.l10n.onboardingAvatarTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            context.l10n.onboardingAvatarSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 40),

          // Avatar circle
          Center(
            child: GestureDetector(
              onTap: picking ? null : onPickAvatar,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ScriptaColors.primaryFaint,
                      border: Border.all(
                        color: ScriptaColors.primary,
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
                            color: ScriptaColors.primary,
                          )
                        : null,
                  ),
                  // While picking, dim the circle and overlay a spinner so
                  // the user sees that the (potentially slow) file read is
                  // happening in our app, not stuck on iOS.
                  if (picking)
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.32),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
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
              onPressed: picking ? null : onPickAvatar,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                context.l10n.onboardingAvatarPick,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ScriptaColors.primaryDark,
                side: const BorderSide(color: ScriptaColors.primaryDark),
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
                context.l10n.onboardingContinue,
                style: GoogleFonts.manrope(
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
              context.l10n.onboardingSkip,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
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
    required this.picking,
    required this.onPickCover,
    required this.onContinue,
    required this.onSkip,
  });

  final Uint8List?   coverBytes;
  final bool         picking;
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
            context.l10n.onboardingCoverTitle,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.4,
            ),
          ).animate().fadeIn(duration: 250.ms),

          const SizedBox(height: 6),
          Text(
            context.l10n.onboardingCoverSubtitle,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 40.ms, duration: 250.ms),

          const SizedBox(height: 32),

          // Cover placeholder — 16:7 aspect ratio
          GestureDetector(
            onTap: picking ? null : onPickCover,
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: ScriptaColors.primaryFaint,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ScriptaColors.primary,
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
                                  color: ScriptaColors.primary.withAlpha(160),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  context.l10n.onboardingCoverPlaceholder,
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    color: ScriptaColors.primary.withAlpha(160),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  if (picking)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.32),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 300.ms),

          const SizedBox(height: 20),

          Center(
            child: OutlinedButton.icon(
              onPressed: picking ? null : onPickCover,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                context.l10n.onboardingCoverPick,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ScriptaColors.primaryDark,
                side: const BorderSide(color: ScriptaColors.primaryDark),
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
                context.l10n.onboardingContinue,
                style: GoogleFonts.manrope(
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
              context.l10n.onboardingSkip,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
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


// Step 6 (Reading goal) and Step 7 (Currently reading) live in
//   steps/reading_goal_step.dart
//   steps/currently_reading_step.dart

// ─── Step 8: Complete ─────────────────────────────────────────────────────────

// ─── Step 8: Health + Calendar permissions ───────────────────────────────────
//
// Asks for the daily-highlight personalisation permissions WITH an explanation,
// so the iOS Health/Calendar sheets don't appear out of context. Read-only,
// on-device.

class _PermissionsStep extends StatelessWidget {
  const _PermissionsStep({required this.onAllow, required this.onSkip});

  final Future<void> Function() onAllow;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final title = isIt
        ? 'Una frase cucita\nsul tuo momento'
        : 'A highlight tuned\nto your moment';
    final body = isIt
        ? 'Col tuo permesso, Scripta usa i passi di oggi (Salute) e gli impegni in calendario per scegliere la citazione giusta per l’ora, il meteo e il ritmo della tua giornata.'
        : 'With your permission, Scripta uses today’s steps (Health) and your calendar to pick the right quote for the time, weather and rhythm of your day.';
    final note = isIt
        ? 'Tutto resta sul tuo iPhone. Niente viene caricato.'
        : 'Everything stays on your iPhone. Nothing is uploaded.';
    final allow = isIt ? 'Consenti accesso' : 'Allow access';
    final later = isIt ? 'Più tardi' : 'Maybe later';

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          // Icons pop in one after the other (soft elastic) — "this matters,
          // but it's safe", instead of two static squares.
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PermIcon(icon: Icons.favorite_rounded)
                    .animate()
                    .fadeIn(duration: 380.ms)
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      end: const Offset(1, 1),
                      duration: 520.ms,
                      curve: Curves.elasticOut,
                    ),
                const SizedBox(width: 14),
                const _PermIcon(icon: Icons.event_rounded)
                    .animate()
                    .fadeIn(delay: 110.ms, duration: 380.ms)
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      end: const Offset(1, 1),
                      delay: 110.ms,
                      duration: 520.ms,
                      curve: Curves.elasticOut,
                    ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.12,
              color: ScriptaColors.ink,
            ),
          )
              .animate()
              .fadeIn(delay: 240.ms, duration: 380.ms)
              .slideY(
                  begin: -0.06,
                  end: 0,
                  delay: 240.ms,
                  duration: 380.ms,
                  curve: AirbnbMotion.enter),
          const SizedBox(height: 16),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15,
              height: 1.6,
              color: ScriptaColors.inkMuted,
            ),
          ).animate().fadeIn(delay: 330.ms, duration: 360.ms),
          const SizedBox(height: 12),
          Text(
            note,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              color: ScriptaColors.inkFaint,
            ),
          ).animate().fadeIn(delay: 410.ms, duration: 360.ms),
          const Spacer(),
          GestureDetector(
            onTap: () => onAllow(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: ScriptaColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  allow,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 480.ms, duration: 380.ms)
              .slideY(
                  begin: 0.1,
                  end: 0,
                  delay: 480.ms,
                  duration: 380.ms,
                  curve: AirbnbMotion.enter),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onSkip,
            child: Text(
              later,
              style: GoogleFonts.manrope(
                color: ScriptaColors.inkMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ).animate().fadeIn(delay: 560.ms, duration: 360.ms),
        ],
      ),
    );
  }
}

class _PermIcon extends StatelessWidget {
  const _PermIcon({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: ScriptaColors.siennaFaint,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 30, color: ScriptaColors.sienna),
      );
}

// ─── Step 9: Gender (local, privacy-preserving) ──────────────────────────────
//
// Asks how the user identifies SO the daily phrase can gently tailor its tone
// (e.g. cycle-aware nudges). Styled like _PermissionsStep. Tapping a card
// selects that value AND advances immediately. The answer is stored ONLY
// on-device — see GenderService / genderProvider. Strings inlined it/en (no .arb
// edits), matching _PermissionsStep's approach.

class _GenderStep extends StatelessWidget {
  const _GenderStep({required this.selected, required this.onSelect});

  /// Currently-selected value, used only to show a brief pressed state on the
  /// chosen card while the page-slide to the next step plays out.
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final title = isIt
        ? 'Per personalizzare\nle frasi, come ti identifichi?'
        : 'To tailor your phrases,\nhow do you identify?';
    final note = isIt
        ? 'Serve solo per mostrarti spunti pertinenti — resta sul tuo telefono.'
        : 'Only used to show you relevant nudges — it stays on your phone.';
    final female = isIt ? 'Donna' : 'Woman';
    final male = isIt ? 'Uomo' : 'Man';
    final unspecified = isIt ? 'Preferisco non dirlo' : 'Prefer not to say';

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              height: 1.12,
              color: ScriptaColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            note,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              height: 1.6,
              color: ScriptaColors.inkMuted,
            ),
          ),
          const SizedBox(height: 36),
          // Cards settle in one after the other — soft, respectful pacing for
          // a sensitive question (selection feedback stays instant).
          _GenderOption(
            label: female,
            value: 'female',
            isSelected: selected == 'female',
            onTap: () => onSelect('female'),
          )
              .animate()
              .fadeIn(delay: 140.ms, duration: 380.ms)
              .slideY(
                  begin: 0.12,
                  end: 0,
                  delay: 140.ms,
                  duration: 400.ms,
                  curve: AirbnbMotion.enter),
          const SizedBox(height: 12),
          _GenderOption(
            label: male,
            value: 'male',
            isSelected: selected == 'male',
            onTap: () => onSelect('male'),
          )
              .animate()
              .fadeIn(delay: 220.ms, duration: 380.ms)
              .slideY(
                  begin: 0.12,
                  end: 0,
                  delay: 220.ms,
                  duration: 400.ms,
                  curve: AirbnbMotion.enter),
          const SizedBox(height: 12),
          _GenderOption(
            label: unspecified,
            value: 'unspecified',
            isSelected: selected == 'unspecified',
            onTap: () => onSelect('unspecified'),
          )
              .animate()
              .fadeIn(delay: 300.ms, duration: 380.ms)
              .slideY(
                  begin: 0.12,
                  end: 0,
                  delay: 300.ms,
                  duration: 400.ms,
                  curve: AirbnbMotion.enter),
          const Spacer(),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isSelected
              ? ScriptaColors.primaryFaint
              : ScriptaColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? ScriptaColors.primary : ScriptaColors.rule,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isSelected ? ScriptaColors.primaryDark : ScriptaColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

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
                  color: ScriptaColors.primaryFaint,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ScriptaColors.primary.withAlpha(60),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 52,
                  color: ScriptaColors.primary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            context.l10n.onboardingCompleteTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: ScriptaColors.ink,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(delay: 400.ms, duration: 350.ms),

          const SizedBox(height: 10),

          Text(
            displayUsername.isNotEmpty
                ? context.l10n.onboardingCompleteBody(displayUsername)
                : context.l10n.onboardingCompleteBodyAnon,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15,
              color: ScriptaColors.inkMuted,
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
                      context.l10n.onboardingEnter,
                      style: GoogleFonts.manrope(
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
              style: GoogleFonts.manrope(
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

// ─── Shared: adaptive scroll shell ───────────────────────────────────────────
//
// Wraps a fixed-layout onboarding step so it keeps its designed vertical
// distribution (Spacer / MainAxisAlignment.center pin the CTA to the bottom or
// centre) on tall screens, but scrolls — instead of throwing a RenderFlex
// overflow — on short viewports (many Android phones, landscape, large text
// scale, or a raised keyboard).
//
// How it works: SingleChildScrollView gives unbounded height; ConstrainedBox
// forces a minimum equal to the viewport; IntrinsicHeight then sizes the child
// to max(viewport, content). When content < viewport the Spacer fills the gap
// (look unchanged); when content > viewport the view scrolls. All wrapped steps
// use intrinsic-height-friendly children (no nested scrollables / unbounded
// images) — steps that already scroll (_AuthStep, CurrentlyReadingStep) must
// NOT be wrapped, as SingleChildScrollView has no intrinsic dimensions.
class _StepScroll extends StatelessWidget {
  const _StepScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

