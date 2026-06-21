import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps any thrown error to a short, friendly, LOCALIZED message that is safe to
/// show a user. It never leaks the raw exception text — no table names, SQL
/// error codes, ORM details, stack traces or backend internals (which an
/// attacker could use to fingerprint the stack; see the 2026-06-20 "detailed
/// error messages help attackers" note). Keep raw `$e` only in debugPrint logs.
extension SafeError on BuildContext {
  String safeError(Object error) => safeErrorMessage(
        error,
        en: Localizations.localeOf(this).languageCode == 'en',
      );
}

/// Locale-explicit variant for call sites that don't have a BuildContext handy.
String safeErrorMessage(Object error, {required bool en}) {
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();
    if (code == '42501' ||
        msg.contains('row-level security') ||
        msg.contains('permission') ||
        msg.contains('forbidden')) {
      return en
          ? "You don't have permission to do that."
          : 'Non hai i permessi per farlo.';
    }
    if (code == '23505' || msg.contains('duplicate')) {
      return en ? 'That already exists.' : 'Esiste già.';
    }
    if (msg.contains('rate') ||
        msg.contains('too many') ||
        msg.contains('slow down')) {
      return en
          ? 'Too many attempts — try again in a moment.'
          : 'Troppi tentativi — riprova tra poco.';
    }
    return en
        ? 'Something went wrong. Please try again.'
        : 'Qualcosa è andato storto. Riprova.';
  }
  if (error is AuthException) {
    return en
        ? 'Authentication failed. Please try again.'
        : 'Autenticazione non riuscita. Riprova.';
  }
  if (error is StorageException) {
    return en
        ? "Couldn't upload right now. Please try again."
        : 'Caricamento non riuscito. Riprova.';
  }
  final s = error.toString();
  if (s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException') ||
      s.contains('TimeoutException') ||
      s.contains('Connection')) {
    return en
        ? 'No connection. Check your network and try again.'
        : 'Nessuna connessione. Controlla la rete e riprova.';
  }
  return en
      ? 'Something went wrong. Please try again.'
      : 'Qualcosa è andato storto. Riprova.';
}
