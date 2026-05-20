import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _passwordCtrl   = TextEditingController();
  final _confirmCtrl    = TextEditingController();

  bool   _obscure1  = true;
  bool   _obscure2  = true;
  bool   _loading   = false;
  bool   _done      = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text),
      );
      if (mounted) setState(() { _done = true; _loading = false; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      setState(() {
        _error = 'Errore imprevisto. Riprova.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
          child: _done ? _DoneState() : _FormState(
            formKey:    _formKey,
            passwordCtrl: _passwordCtrl,
            confirmCtrl:  _confirmCtrl,
            obscure1:   _obscure1,
            obscure2:   _obscure2,
            loading:    _loading,
            error:      _error,
            onToggle1:  () => setState(() => _obscure1 = !_obscure1),
            onToggle2:  () => setState(() => _obscure2 = !_obscure2),
            onSubmit:   _submit,
          ),
        ),
      ),
    );
  }
}

// ─── Form widget ──────────────────────────────────────────────────────────────

class _FormState extends StatelessWidget {
  const _FormState({
    required this.formKey,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.obscure1,
    required this.obscure2,
    required this.loading,
    required this.error,
    required this.onToggle1,
    required this.onToggle2,
    required this.onSubmit,
  });

  final GlobalKey<FormState>   formKey;
  final TextEditingController  passwordCtrl;
  final TextEditingController  confirmCtrl;
  final bool                   obscure1;
  final bool                   obscure2;
  final bool                   loading;
  final String?                error;
  final VoidCallback           onToggle1;
  final VoidCallback           onToggle2;
  final VoidCallback           onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_outlined,
              color: MarginaliaColors.primary,
              size: 30,
            ),
          ).animate().scale(
            begin: const Offset(0.5, 0.5),
            end:   const Offset(1.0, 1.0),
            duration: 400.ms,
            curve: Curves.elasticOut,
          ),

          const SizedBox(height: 24),

          const Text(
            'Nuova password',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0),

          const SizedBox(height: 6),

          Text(
            'Scegli una password di almeno 6 caratteri.',
            style: TextStyle(fontSize: 14, color: MarginaliaColors.inkMuted),
          ).animate(delay: 60.ms).fadeIn(duration: 300.ms),

          const SizedBox(height: 32),

          // Password
          TextFormField(
            controller:  passwordCtrl,
            obscureText: obscure1,
            decoration:  InputDecoration(
              hintText:   'Nuova password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(obscure1
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: onToggle1,
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Inserisci la nuova password';
              if (v.length < 6) return 'Almeno 6 caratteri';
              return null;
            },
          ).animate(delay: 100.ms).fadeIn(duration: 280.ms),

          const SizedBox(height: 14),

          // Confirm
          TextFormField(
            controller:  confirmCtrl,
            obscureText: obscure2,
            decoration:  InputDecoration(
              hintText:   'Conferma password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(obscure2
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: onToggle2,
              ),
            ),
            validator: (v) {
              if (v != passwordCtrl.text) return 'Le password non coincidono';
              return null;
            },
          ).animate(delay: 140.ms).fadeIn(duration: 280.ms),

          // Error
          if (error != null) ...[
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
                  const Icon(Icons.error_outline,
                      color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(
                          color: Color(0xFFDC2626), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ).animate().shake(),
          ],

          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Salva password'),
            ),
          ).animate(delay: 180.ms).fadeIn(duration: 280.ms),
        ],
      ),
    );
  }
}

// ─── Success state ────────────────────────────────────────────────────────────

class _DoneState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        const Icon(
          Icons.check_circle_outline_rounded,
          color: MarginaliaColors.primary,
          size: 72,
        )
            .animate()
            .scale(
              begin: const Offset(0.2, 0.2),
              end:   const Offset(1.0, 1.0),
              duration: 600.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: 24),
        const Text(
          'Password aggiornata!',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ).animate(delay: 200.ms).fadeIn(duration: 300.ms),
        const SizedBox(height: 8),
        Text(
          'Stai per essere reindirizzato…',
          style: TextStyle(fontSize: 14, color: MarginaliaColors.inkMuted),
          textAlign: TextAlign.center,
        ).animate(delay: 350.ms).fadeIn(duration: 300.ms),
      ],
    );
  }
}
