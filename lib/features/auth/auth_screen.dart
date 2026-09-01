import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../settings/privacy_policy_screen.dart';
import '../settings/terms_of_service_screen.dart';
import 'email_otp_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart' show AppleSignInCancelled;
import '../../core/providers/onboarding_provider.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/l10n/l10n_extension.dart';
import '../onboarding/shared/social_auth_buttons.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  String? _error;
  // ToS/EULA acceptance — enforced on the sign-up tab only (App Store
  // Guideline 1.2). Client-side gate; no DB column is stored for it.
  bool _acceptedTerms = false;

  StreamSubscription<AuthState>? _authSub;

  // True only while a SOCIAL sign-in round-trip is in flight. The listener
  // below pops ONLY for that flow — the email path already pops on success
  // itself, and reacting to its signedIn event too would pop TWICE (throwing
  // or dismissing the underlying route).
  bool _socialFlowInFlight = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _error = null));
    // Social sign-in finishes asynchronously: when the session lands, leave the
    // auth screen exactly like the email path does.
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn && _socialFlowInFlight) {
        _socialFlowInFlight = false;
        unawaited(_finishSignIn());
      }
    });
  }

  /// Decides where the reader goes once a session exists.
  ///
  /// This screen only exists AFTER onboarding was completed on this device, so
  /// nothing here would ever ask a brand-new account for a username — and a
  /// social sign-in does not just sign people in, it CREATES the account. Both
  /// Apple accounts made on 2026-09-01 ended up with `username = null` for
  /// exactly that reason. So: no username means this is really a sign-UP, and
  /// the reader is sent through onboarding instead of being dropped into the
  /// app with a half-made profile. A username means it was a plain login and we
  /// simply leave.
  Future<void> _finishSignIn() async {
    if (!mounted) return;
    String username = '';
    try {
      final profile = await ref.read(supabaseServiceProvider).fetchProfile();
      username = (profile?['username'] as String?)?.trim() ?? '';
    } catch (_) {
      // Never trap someone in onboarding because the profile fetch hiccuped:
      // on any doubt, treat it as a normal login.
      if (mounted) _leaveAuthScreen();
      return;
    }
    if (!mounted) return;
    if (username.isNotEmpty) {
      _leaveAuthScreen();
      return;
    }
    // Clear BOTH the in-memory flag and the marker file: the flag swaps the app
    // to OnboardingScreen right now, and the file keeps it that way if the app
    // is killed before the profile is finished. No pop here — the route this
    // screen lives on disappears along with the router.
    await OnboardingService.resetComplete();
    if (!mounted) return;
    ref.read(onboardingCompleteProvider.notifier).state = false;
  }

  /// Leaves this screen after a successful sign-in.
  ///
  /// A bare `context.pop()` is not safe here. Settings sends the reader to
  /// `/auth` with `go()` after an account deletion, and `go()` REPLACES the
  /// stack — so nothing sits underneath and go_router throws
  /// "GoError: There is nothing to pop". Thrown from the auth-state listener it
  /// is an uncaught async error, which the bootstrap gate catches and turns
  /// into the full-screen "Non siamo riusciti ad aprire l'app" — a real device
  /// hit exactly that on 2026-09-01, right after Sign in with Apple succeeded.
  /// The native Apple sheet is what exposed it: the old web flow came back
  /// through a deep link that rebuilt the stack, so there was always something
  /// to pop.
  void _leaveAuthScreen() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _tab.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Social sign-in (Apple/Google) via the Supabase OAuth web flow. Pre-flights
  /// the provider so an unconfigured dashboard shows a friendly message instead
  /// of Supabase's raw JSON error page. Success returns through the deep link
  /// and the auth listener pops this screen.
  Future<void> _social(String provider) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(supabaseServiceProvider);
      final enabled = await service.isOAuthProviderEnabled(provider);
      if (!mounted) return;
      if (!enabled) {
        setState(() => _error = context.l10n.authProviderNotEnabled);
        return;
      }
      _socialFlowInFlight = true;
      if (provider == 'apple') {
        await service.signInWithApple();
      } else {
        await service.signInWithGoogle();
      }
    } on AppleSignInCancelled {
      // Backing out of the native Apple sheet is a decision, not a failure —
      // leave the screen exactly as it was.
      _socialFlowInFlight = false;
    } on AuthException catch (e) {
      _socialFlowInFlight = false;
      if (mounted) setState(() => _error = _mapError(e.message));
    } catch (_) {
      _socialFlowInFlight = false;
      if (mounted) setState(() => _error = context.l10n.authOauthFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Sign-up tab only: block account creation until the EULA/ToS is accepted
    // (App Store Guideline 1.2). Sign-in is never gated.
    if (_tab.index == 1 && !_acceptedTerms) {
      setState(() => _error = context.l10n.authMustAcceptTerms);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(supabaseServiceProvider);
      if (_tab.index == 0) {
        await service.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        final res = await service.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
        // profiles upsert is best-effort — table may not exist yet
        if (res.user != null && _nameController.text.trim().isNotEmpty) {
          try {
            await Supabase.instance.client.from('profiles').upsert({
              'id': res.user!.id,
              'display_name': _nameController.text.trim(),
            });
          } catch (_) {}
        }
        if (res.session == null && mounted) {
          // Email confirmation required → take the user straight to in-app OTP
          // entry. Typing the 6-digit code is far more reliable on mobile than
          // a magic link that must round-trip through Safari / a deep link.
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EmailOtpScreen(email: _emailController.text.trim()),
          ));
          return;
        }
      }
      await _finishSignIn();
    } on AuthException catch (e) {
      setState(() => _error = _mapError(e.message));
    } catch (e) {
      setState(() => _error = context.l10n.authErrGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(context.l10n.authForgotPasswordTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.authForgotPasswordBody,
                style: TextStyle(fontSize: 13, color: ScriptaColors.inkMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: context.l10n.authEmail,
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: ScriptaColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) return;
                      setS(() => sending = true);
                      try {
                        // IMPORTANT: use the HTTPS deploy URL, NOT the custom
                        // marginalia:// scheme. Custom schemes only work on
                        // iOS/Android natively with the app installed; in any
                        // browser (desktop, iPhone Safari without app) they
                        // open about:blank.
                        //
                        // The HTTPS URL works everywhere: the web app picks
                        // up the recovery hash and fires AuthChangeEvent.
                        // passwordRecovery → router pushes /reset-password.
                        //
                        // For iOS app builds, configure Universal Links so
                        // this same HTTPS URL opens the app directly instead
                        // of Safari.
                        await Supabase.instance.client.auth
                            .resetPasswordForEmail(
                          email,
                          // Bare URL — Supabase appends its own hash
                          // fragment (#access_token=...&type=recovery).
                          // The app boots, supabase_flutter parses the
                          // fragment, fires AuthChangeEvent.passwordRecovery,
                          // and our listener in app.dart pushes
                          // /reset-password. Don't add a hash here or the
                          // two hashes collide and break the parse.
                          redirectTo:
                              'https://get-scripta.app/app',
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.l10n.authForgotPasswordSent(email),
                                ),
                                backgroundColor: ScriptaColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        }
                      } catch (_) {
                        setS(() => sending = false);
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.authForgotPasswordSend),
            ),
          ],
        ),
      ),
    );
  }

  String _mapError(String msg) {
    final l = context.l10n;
    if (msg.contains('Invalid login')) return l.authErrInvalidLogin;
    if (msg.contains('Email not confirmed')) return l.authErrNotConfirmed;
    if (msg.contains('already registered')) return l.authErrAlreadyRegistered;
    if (msg.contains('Password should be')) return l.authErrWeakPassword;
    // "Non dire più del dovuto": never surface the raw server error string to
    // the user (it can leak internal/auth details) — fall back to a generic one.
    return l.authErrGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _tab.index == 1;

    return Scaffold(
      backgroundColor: ScriptaColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Editorial header ─────────────────────────────────────────
                const SizedBox(height: 24),
                Center(
                  child: const ScriptaMark(size: 72)
                      .animate()
                      .fadeIn(duration: AirbnbMotion.longForm, curve: AirbnbMotion.enter)
                      .scale(
                        begin: const Offset(0.84, 0.84),
                        end: const Offset(1, 1),
                        duration: AirbnbMotion.longForm,
                        curve: Curves.easeOutBack,
                      ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'Scripta',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      color: ScriptaColors.ink,
                      letterSpacing: -0.8,
                      height: 1,
                    ),
                  ),
                ).animate().fadeIn(
                    delay: 80.ms,
                    duration: AirbnbMotion.emphasis,
                    curve: AirbnbMotion.enter),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    context.l10n.authSubtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: ScriptaColors.inkMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ).animate().fadeIn(
                    delay: 140.ms, duration: AirbnbMotion.emphasis),

                const SizedBox(height: 30),

                // ── Pill segmented control (Accedi / Registrati) ─────────────
                _AuthSegmented(tab: _tab).animate().fadeIn(
                    delay: 200.ms, duration: AirbnbMotion.emphasis),

                const SizedBox(height: 26),

                // Name (signup only)
                AnimatedSize(
                  duration: AirbnbMotion.standard,
                  curve: AirbnbMotion.enter,
                  child: isSignup
                      ? Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: _fieldDecoration(
                                hint: context.l10n.authName,
                                icon: Icons.person_outline,
                              ),
                              validator: (v) =>
                                  _tab.index == 1 && (v == null || v.trim().isEmpty)
                                      ? context.l10n.authNameRequired
                                      : null,
                            ),
                            const SizedBox(height: 14),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _fieldDecoration(
                    hint: context.l10n.authEmail,
                    icon: Icons.email_outlined,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return context.l10n.authEmailRequired;
                    if (!v.contains('@')) return context.l10n.authEmailInvalid;
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: _fieldDecoration(
                    hint: context.l10n.authPassword,
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: ScriptaColors.inkFaint,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return context.l10n.authPasswordRequired;
                    if (_tab.index == 1 && v.length < 6) return context.l10n.authPasswordTooShort;
                    return null;
                  },
                ),

                // "Forgot password" — login tab only
                if (!isSignup)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPassword,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        foregroundColor: ScriptaColors.primaryDark,
                      ),
                      child: Text(
                        context.l10n.authForgotPassword,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!),
                ],

                // ── Terms acceptance — directly ABOVE the primary CTA, signup
                // only (App Store Guideline 1.2). Login mode never shows it.
                if (isSignup) ...[
                  const SizedBox(height: 20),
                  _TermsAcceptanceRow(
                    accepted: _acceptedTerms,
                    onChanged: (v) =>
                        setState(() => _acceptedTerms = v ?? false),
                  ),
                ],

                const SizedBox(height: 22),

                // ── Primary CTA — full-width sage, 52px ──────────────────────
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ScriptaColors.primary,
                      foregroundColor: ScriptaColors.ink,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isSignup
                                ? context.l10n.authCreateAccount
                                : context.l10n.authSignIn,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 22),

                // ── "oppure" divider ─────────────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: ScriptaColors.rule, height: 1)),
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
                    const Expanded(
                        child: Divider(color: ScriptaColors.rule, height: 1)),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Social sign-in (Apple first per HIG) ─────────────────────
                SocialAuthButtons(
                  loading: _loading,
                  appleLabel: context.l10n.authContinueWithApple,
                  onApple: () => _social('apple'),
                  googleLabel: context.l10n.authContinueWithGoogle,
                  onGoogle: () => _social('google'),
                ),

                const SizedBox(height: 8),

                // Account creation is mandatory — no anonymous bypass.
                // (Previously a "Continue without account" link lived here;
                // removed 2026-05-27.)
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shared filled-field decoration for the restyled auth form: a soft cream
  /// surface, rounded 16px corners, a subtle rest border (Airbnb-light) and a
  /// sage focus ring. Keeps every field visually identical without repeating
  /// the OutlineInputBorder triplet five times.
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: ScriptaColors.inkFaint),
      suffixIcon: suffix,
      filled: true,
      fillColor: ScriptaColors.surfaceElevated,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(ScriptaColors.rule, 1),
      enabledBorder: border(ScriptaColors.rule, 1),
      focusedBorder: border(ScriptaColors.primaryDark, 1.5),
      // Brand red (0xFFB94A41) for validation errors — not a named palette
      // constant, so referenced as a literal to match the spec.
      errorBorder: border(const Color(0xFFB94A41), 1),
      focusedErrorBorder: border(const Color(0xFFB94A41), 1.5),
    );
  }
}

// ─── Pill segmented control (Accedi / Registrati) ───────────────────────────
//
// A light, modern replacement for the old boxy TabBar: a pill track with a
// single sliding sage indicator. Driven by the same [TabController] the form
// reads (`_tab.index`), so all the existing mode logic is untouched — tapping a
// half animates the controller, which both slides the indicator AND rebuilds
// the form. Listens to the controller's animation for a smooth slide even when
// the index is changed programmatically.
class _AuthSegmented extends StatefulWidget {
  const _AuthSegmented({required this.tab});
  final TabController tab;

  @override
  State<_AuthSegmented> createState() => _AuthSegmentedState();
}

class _AuthSegmentedState extends State<_AuthSegmented> {
  @override
  void initState() {
    super.initState();
    widget.tab.animation?.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.tab.animation?.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Continuous 0..1 position from the controller's animation so the indicator
    // tracks the swipe/animation, not just the settled index.
    final t = (widget.tab.animation?.value ?? widget.tab.index.toDouble())
        .clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 4.0;
        final trackWidth = constraints.maxWidth;
        final slotWidth = (trackWidth - pad * 2) / 2;

        return Container(
          height: 48,
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: ScriptaColors.surfaceElevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ScriptaColors.rule),
          ),
          child: Stack(
            children: [
              // Sliding indicator
              Align(
                alignment: Alignment(-1 + 2 * t, 0),
                child: Container(
                  width: slotWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: ScriptaColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _segment(context, context.l10n.authSignIn, 0, t < 0.5),
                  _segment(context, context.l10n.authSignUp, 1, t >= 0.5),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(BuildContext context, String label, int index, bool active) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.tab.animateTo(index),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AirbnbMotion.fast,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? ScriptaColors.ink : ScriptaColors.inkMuted,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ─── Error banner ───────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
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
    ).animate().fadeIn(duration: AirbnbMotion.fast).shake(duration: 300.ms);
  }
}

// ─── Terms acceptance row (signup only) ─────────────────────────────────────
//
// A tappable checkbox plus a localized sentence whose "Terms of Service" and
// "Privacy Policy" substrings each open their respective in-app screen. Built
// as three l10n fragments so the two link spans stay trivially tappable across
// IT/EN word order. The TapGestureRecognizers are owned + disposed here.
class _TermsAcceptanceRow extends StatefulWidget {
  const _TermsAcceptanceRow({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool?> onChanged;

  @override
  State<_TermsAcceptanceRow> createState() => _TermsAcceptanceRowState();
}

class _TermsAcceptanceRowState extends State<_TermsAcceptanceRow> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = _openTerms;
    _privacyTap = TapGestureRecognizer()..onTap = _openPrivacy;
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  bool get _isIt => Localizations.localeOf(context).languageCode == 'it';

  void _openTerms() {
    final isIt = _isIt;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TermsOfServiceScreen(isItalian: isIt),
      ),
    );
  }

  void _openPrivacy() {
    final isIt = _isIt;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacyPolicyScreen(isItalian: isIt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: ScriptaColors.primaryDark,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: widget.accepted,
            onChanged: widget.onChanged,
            activeColor: ScriptaColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            side: const BorderSide(color: ScriptaColors.rule, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            // Tapping the text (not the links) toggles the checkbox too.
            onTap: () => widget.onChanged(!widget.accepted),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: ScriptaColors.inkMuted,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(text: context.l10n.signupAcceptPrefix),
                    TextSpan(
                      text: context.l10n.signupAcceptTerms,
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    TextSpan(text: context.l10n.signupAcceptAnd),
                    TextSpan(
                      text: context.l10n.signupAcceptPrivacy,
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
