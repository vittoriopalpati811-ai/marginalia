import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tab.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
          _showConfirmEmail();
          return;
        }
      }
      if (mounted) context.pop();
    } on AuthException catch (e) {
      setState(() => _error = _mapError(e.message));
    } catch (e) {
      setState(() => _error = context.l10n.authErrGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showConfirmEmail() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.l10n.onboardingCheckEmailTitle),
        content: Text(
          context.l10n.onboardingCheckEmailBody(_emailController.text.trim()),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _tab.animateTo(0);
            },
            child: Text(context.l10n.onboardingCheckEmailCta),
          ),
        ],
      ),
    );
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
                style: TextStyle(fontSize: 13, color: MarginaliaColors.inkMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: context.l10n.authEmail,
                  prefixIcon: const Icon(Icons.email_outlined),
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
                        await Supabase.instance.client.auth
                            .resetPasswordForEmail(
                          email,
                          redirectTo: 'marginalia://reset-password',
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.l10n.authForgotPasswordSent(email),
                                ),
                                backgroundColor: MarginaliaColors.primary,
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
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Column(
        children: [
          // ── Header con gradient ────────────────────────────────────────────
          _AuthHeader(tab: _tab),

          // ── Form ──────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Nome (solo registrazione)
                    AnimatedSize(
                      duration: 250.ms,
                      curve: Curves.easeOut,
                      child: _tab.index == 1
                          ? Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    hintText: context.l10n.authName,
                                    prefixIcon: const Icon(Icons.person_outline),
                                  ),
                                  validator: (v) => _tab.index == 1 && (v == null || v.trim().isEmpty)
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
                      decoration: InputDecoration(
                        hintText: context.l10n.authEmail,
                        prefixIcon: const Icon(Icons.email_outlined),
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
                      decoration: InputDecoration(
                        hintText: context.l10n.authPassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return context.l10n.authPasswordRequired;
                        if (_tab.index == 1 && v.length < 6) return context.l10n.authPasswordTooShort;
                        return null;
                      },
                    ),

                    // "Forgot password" — solo nel tab login
                    if (_tab.index == 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            foregroundColor: MarginaliaColors.sienna,
                          ),
                          child: Text(
                            context.l10n.authForgotPassword,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
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
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 52,
                      child: FilledButton(
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
                            : Text(_tab.index == 0 ? context.l10n.authSignIn : context.l10n.authCreateAccount),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // GDPR Article 7 consent — shown only on signup tab
                    if (_tab.index == 1) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 12,
                              color: MarginaliaColors.inkMuted,
                              height: 1.5,
                            ),
                            children: [
                              const TextSpan(
                                text:
                                    'By creating an account you agree to our ',
                              ),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: const TextStyle(
                                  color: MarginaliaColors.sienna,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () async {
                                    final uri = Uri.parse(
                                        'https://marginalia.app/privacy');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                              ),
                              const TextSpan(
                                text: ' and confirm you are 16 or older.',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(context.l10n.authContinueWithoutAccount),
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

// ─── Header ───────────────────────────────────────────────────────────────────

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.tab});
  final TabController tab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MarginaliaDecorations.gradientHeader,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Logo
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_stories, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'Marginalia',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.authSubtitle,
              style: TextStyle(
                color: Colors.white.withAlpha(180),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: tab,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: MarginaliaColors.sienna,
                unselectedLabelColor: Colors.white.withAlpha(200),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: [
                  Tab(text: context.l10n.authSignIn),
                  Tab(text: context.l10n.authSignUp),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}
