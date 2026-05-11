import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        children: [
          // ─── Account ─────────────────────────────────────────────────────
          _SectionHeader('ACCOUNT'),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.person_outline, color: MarginaliaColors.accent),
              title: Text(user.email ?? 'Utente'),
              subtitle: const Text('Connesso'),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(supabaseServiceProvider).signOut();
                },
                child: const Text('Esci', style: TextStyle(color: Colors.red)),
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.login_outlined, color: MarginaliaColors.accent),
              title: const Text('Accedi o Registrati'),
              subtitle: const Text('Richiesto per le Jam'),
              onTap: () => context.push('/auth').then((_) => ref.invalidate(currentUserProvider)),
              trailing: const Icon(Icons.chevron_right,
                  color: MarginaliaColors.textMuted, size: 18),
            ),

          const Divider(),

          // ─── Kindle Sync ──────────────────────────────────────────────────
          _SectionHeader('KINDLE'),
          ListTile(
            leading:
                const Icon(Icons.sync_outlined, color: MarginaliaColors.accent),
            title: const Text('Sincronizza con Amazon Kindle'),
            subtitle: const Text('Accedi ad Amazon e importa gli highlight'),
            onTap: () => context.push('/sync/kindle'),
            trailing: const Icon(Icons.chevron_right,
                color: MarginaliaColors.textMuted, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined,
                color: MarginaliaColors.accent),
            title: const Text('Importa My Clippings.txt'),
            subtitle: const Text('Importa manualmente dal file Kindle'),
            onTap: () => context.push('/'),
            trailing: const Icon(Icons.chevron_right,
                color: MarginaliaColors.textMuted, size: 18),
          ),

          const Divider(),

          // ─── Informazioni ─────────────────────────────────────────────────
          _SectionHeader('INFORMAZIONI'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: MarginaliaColors.accent),
            title: const Text('Versione'),
            trailing: const Text('1.0.0',
                style: TextStyle(color: MarginaliaColors.textMuted)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined,
                color: MarginaliaColors.accent),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new,
                size: 16, color: MarginaliaColors.textMuted),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: MarginaliaTextStyles.sectionTitle),
    );
  }
}
