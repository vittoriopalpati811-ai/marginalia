// ─── Phone-number sign-in sheet ─────────────────────────────────────────────
//
// Two-screen bottom sheet:
//   1. Enter E.164 phone number → POST to Supabase auth.signInWithOtp
//   2. Enter the 6-digit SMS code → verifyOtp → returns Session
//
// On success the sheet pops with `true`. Caller is responsible for advancing
// the onboarding flow (the auth state listener at the app root takes care of
// hiding the onboarding once a session exists, but onboarding step navigation
// stays in the parent).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme.dart';
import '../shared/onboarding_pill_button.dart';

Future<bool?> showPhoneAuthSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MarginaliaColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _PhoneAuthSheet(),
  );
}

class _PhoneAuthSheet extends ConsumerStatefulWidget {
  const _PhoneAuthSheet();

  @override
  ConsumerState<_PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends ConsumerState<_PhoneAuthSheet> {
  final _phoneCtrl = TextEditingController(text: '+39 ');
  final _otpCtrl   = TextEditingController();
  bool   _sending  = false;
  bool   _verifying = false;
  bool   _otpStage = false;
  String? _error;
  String  _sentPhone = '';

  static final _e164 = RegExp(r'^\+\d{8,15}$');

  String _normalize(String raw) =>
      raw.replaceAll(RegExp(r'[^\d+]'), '');

  Future<void> _send() async {
    final phone = _normalize(_phoneCtrl.text);
    if (!_e164.hasMatch(phone)) {
      setState(() => _error = context.l10n.authPhoneInvalid);
      return;
    }
    setState(() {
      _sending = true;
      _error   = null;
    });
    try {
      await ref.read(supabaseServiceProvider).sendPhoneOtp(phone);
      if (!mounted) return;
      setState(() {
        _otpStage  = true;
        _sentPhone = phone;
      });
    } catch (e) {
      setState(() => _error = context.l10n.authOauthFailed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final token = _otpCtrl.text.trim();
    if (token.length < 4) return;
    setState(() {
      _verifying = true;
      _error     = null;
    });
    try {
      await ref.read(supabaseServiceProvider).verifyPhoneOtp(
            phoneE164: _sentPhone,
            token: token,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = context.l10n.authPhoneOtpFailed);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: MarginaliaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          if (!_otpStage) ..._phoneStage(context) else ..._otpStageWidgets(context),
        ],
      ),
    );
  }

  List<Widget> _phoneStage(BuildContext context) => [
        Text(
          context.l10n.authPhoneTitle,
          style: GoogleFonts.ebGaramond(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.ink,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.authPhoneSubtitle,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: MarginaliaColors.inkMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d+\s]')),
            LengthLimitingTextInputFormatter(20),
          ],
          decoration: InputDecoration(
            hintText: context.l10n.authPhonePlaceholder,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: const Color(0xFFB54848),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OnboardingPrimaryPill(
          label: context.l10n.authPhoneSend,
          onPressed: _sending ? null : _send,
        ),
      ];

  List<Widget> _otpStageWidgets(BuildContext context) => [
        Text(
          context.l10n.authPhoneCodeTitle,
          style: GoogleFonts.ebGaramond(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.ink,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.authPhoneCodeSubtitle(_sentPhone),
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: MarginaliaColors.inkMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: GoogleFonts.ebGaramond(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: 6,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(
            hintText: '------',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: const Color(0xFFB54848),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OnboardingPrimaryPill(
          label: context.l10n.authPhoneCodeVerify,
          onPressed: _verifying ? null : _verify,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _sending ? null : _send,
            child: Text(context.l10n.authPhoneCodeResend),
          ),
        ),
      ];
}
