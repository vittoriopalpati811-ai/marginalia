import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/scripta_mark.dart';
import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';

/// Length of the email OTP Supabase sends. The Auth dashboard is configured to
/// 8 digits; the field's maxLength + auto-submit follow this constant, so if the
/// dashboard length ever changes, update only here. (The earlier 6 truncated the
/// 8-digit code, so signup could never be confirmed — founder, 2026-06-21.)
const int _kOtpLength = 8;

/// Email-confirmation OTP entry. Shown straight after signup when Supabase
/// requires email confirmation (signUp returns a null session). The user types
/// the code from the email; we verify it directly against Supabase
/// (no magic-link round-trip), which yields a session and signs them in.
class EmailOtpScreen extends ConsumerStatefulWidget {
  const EmailOtpScreen({super.key, required this.email, this.onVerified});

  final String email;

  /// Optional success hook. When provided, a successful verification pops this
  /// screen and invokes [onVerified] instead of routing to `/`. Used by the
  /// onboarding flow (which runs in a standalone MaterialApp with no go_router
  /// mounted yet) so the caller can continue the onboarding steps itself.
  /// When null (the auth_screen path) the screen routes to `/` as before.
  final VoidCallback? onVerified;

  @override
  ConsumerState<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends ConsumerState<EmailOtpScreen> {
  final _codeCtrl = TextEditingController();
  final _focus = FocusNode();

  bool _loading = false;
  bool _resending = false;
  // One-shot: once a code verifies, never run _verify again. Autofill,
  // onChanged-at-full-length and the Verify button could otherwise re-fire it
  // after success (the OTP is single-use, so a 2nd attempt errors), which was a
  // path into the post-signup loop.
  bool _verified = false;
  String? _error;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Give Supabase a moment, then allow a resend after a 30s cooldown.
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (_verified || _loading) return; // one-shot — never re-verify
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = context.l10n.otpErrorInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(supabaseServiceProvider).verifyEmailSignupOtp(
            email: widget.email,
            token: code,
          );
      if (!mounted) return;
      _verified = true; // lock before navigating so nothing re-enters _verify
      // Verified → a session now exists. In the onboarding flow there is no
      // go_router mounted yet, so the caller passes [onVerified]: pop back and
      // let it continue the onboarding steps. In the auth_screen flow the
      // router's auth redirect sends the user into the app, so route to `/`.
      if (widget.onVerified != null) {
        Navigator.of(context).pop();
        widget.onVerified!.call();
      } else {
        context.go('/');
      }
    } on AuthException catch (_) {
      // Never surface the raw server string (can leak details); generic message.
      setState(() {
        _error = context.l10n.otpErrorInvalid;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = context.l10n.authErrGeneric;
        _loading = false;
      });
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(supabaseServiceProvider).resendSignupOtp(widget.email);
      messenger.showSnackBar(SnackBar(content: Text(l10n.otpResent)));
      _startCooldown();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.authErrGeneric)));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: const ScriptaMark(size: 56)
                    .animate()
                    .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                    .scale(
                      begin: const Offset(0.82, 0.82),
                      end: const Offset(1, 1),
                      duration: 500.ms,
                      curve: Curves.easeOutBack,
                    ),
              ),
              const SizedBox(height: 22),
              Text(
                l10n.otpTitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.ebGaramond(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: ScriptaColors.ink,
                  letterSpacing: -0.5,
                ),
              ).animate().fadeIn(delay: 80.ms, duration: 400.ms),
              const SizedBox(height: 8),
              Text(
                l10n.otpSubtitle(widget.email),
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: ScriptaColors.inkMuted,
                  height: 1.5,
                ),
              ).animate().fadeIn(delay: 140.ms, duration: 400.ms),
              const SizedBox(height: 30),

              // One-time code field. Supabase sends an 8-digit email OTP (the
              // length is set in the Auth dashboard); keep [_kOtpLength] in sync
              // with it. A shorter config still works — the user just taps
              // Verify instead of it auto-submitting.
              TextField(
                controller: _codeCtrl,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: _kOtpLength,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: ScriptaColors.ink,
                ),
                onChanged: (v) {
                  if (_error != null) setState(() => _error = null);
                  if (v.length == _kOtpLength) _verify();
                },
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '•' * _kOtpLength,
                  hintStyle: TextStyle(
                    letterSpacing: 6,
                    color: ScriptaColors.inkFaint.withAlpha(120),
                  ),
                  filled: true,
                  fillColor: ScriptaColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: ScriptaColors.rule),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: ScriptaColors.rule),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                        color: ScriptaColors.primaryDark, width: 1.5),
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFDC2626), fontSize: 13)),
                      ),
                    ],
                  ),
                ).animate().shake(),
              ],

              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n.otpVerifyCta),
                ),
              ),

              const SizedBox(height: 18),

              Center(
                child: TextButton(
                  onPressed: (_cooldown > 0 || _resending) ? null : _resend,
                  child: Text(
                    _cooldown > 0
                        ? l10n.otpResendIn(_cooldown)
                        : l10n.otpResend,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: _cooldown > 0
                          ? ScriptaColors.inkFaint
                          : ScriptaColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
