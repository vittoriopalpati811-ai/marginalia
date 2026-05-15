import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// Profile of the current user — currently_reading + display_name
final myProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return null;
  try {
    return await svc.fetchProfile();
  } catch (_) {
    return null;
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // ─── Account ─────────────────────────────────────────────────────
          _SectionHeader('ACCOUNT'),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.person_outline,
                  color: MarginaliaColors.primary),
              title: Text(user.email ?? 'Utente'),
              subtitle: const Text('Connesso'),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(supabaseServiceProvider).signOut();
                },
                child: const Text('Esci',
                    style: TextStyle(color: Color(0xFFB54848))),
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.login_outlined,
                  color: MarginaliaColors.primary),
              title: const Text('Accedi o Registrati'),
              subtitle: const Text('Richiesto per le Jam'),
              onTap: () => context.push('/auth'),
              trailing: const Icon(Icons.chevron_right,
                  color: MarginaliaColors.inkMuted, size: 18),
            ),

          const Divider(),

          // ─── Sto leggendo ────────────────────────────────────────────────
          if (user != null) ...[
            _SectionHeader('STO LEGGENDO'),
            profileAsync.when(
              data: (profile) => _CurrentlyReadingTile(
                title: profile?['currently_reading_title'] as String?,
                author: profile?['currently_reading_author'] as String?,
                onTap: () => _editCurrentlyReading(context, ref, profile),
              ),
              loading: () => const ListTile(
                leading: Icon(Icons.menu_book_outlined,
                    color: MarginaliaColors.primary),
                title: Text('Caricamento…'),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Divider(),
          ],

          // ─── Kindle Sync ──────────────────────────────────────────────────
          _SectionHeader('KINDLE'),
          ListTile(
            leading: const Icon(Icons.sync_outlined,
                color: MarginaliaColors.primary),
            title: const Text('Sincronizza con Amazon Kindle'),
            subtitle: const Text('Accedi ad Amazon e importa gli highlight'),
            onTap: () => context.push('/sync/kindle'),
            trailing: const Icon(Icons.chevron_right,
                color: MarginaliaColors.inkMuted, size: 18),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined,
                color: MarginaliaColors.primary),
            title: const Text('Importa My Clippings.txt'),
            subtitle: const Text('Importa manualmente dal file Kindle'),
            onTap: () => context.push('/'),
            trailing: const Icon(Icons.chevron_right,
                color: MarginaliaColors.inkMuted, size: 18),
          ),

          const Divider(),

          // ─── Informazioni ─────────────────────────────────────────────────
          _SectionHeader('INFORMAZIONI'),
          const ListTile(
            leading:
                Icon(Icons.info_outline, color: MarginaliaColors.primary),
            title: Text('Versione'),
            trailing:
                Text('1.0.0', style: TextStyle(color: MarginaliaColors.inkMuted)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined,
                color: MarginaliaColors.primary),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new,
                size: 16, color: MarginaliaColors.inkMuted),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Future<void> _editCurrentlyReading(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? profile,
  ) async {
    final titleController = TextEditingController(
        text: profile?['currently_reading_title'] as String? ?? '');
    final authorController = TextEditingController(
        text: profile?['currently_reading_author'] as String? ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cosa stai leggendo?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'I membri delle tue Jam lo vedranno nella cerchia.',
              style:
                  TextStyle(color: MarginaliaColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Titolo del libro',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: authorController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Autore (opzionale)',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(supabaseServiceProvider)
                            .updateCurrentlyReading(title: null, author: null);
                        ref.invalidate(myProfileProvider);
                      } catch (_) {}
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Rimuovi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () async {
                      final t = titleController.text.trim();
                      final a = authorController.text.trim();
                      try {
                        await ref
                            .read(supabaseServiceProvider)
                            .updateCurrentlyReading(
                              title: t.isEmpty ? null : t,
                              author: a.isEmpty ? null : a,
                            );
                        ref.invalidate(myProfileProvider);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Errore: $e')),
                          );
                        }
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Salva'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentlyReadingTile extends StatelessWidget {
  const _CurrentlyReadingTile({
    required this.title,
    required this.author,
    required this.onTap,
  });

  final String? title;
  final String? author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasBook = title != null && title!.isNotEmpty;
    return ListTile(
      leading: const Icon(Icons.menu_book_outlined,
          color: MarginaliaColors.primary),
      title: Text(
        hasBook ? title! : 'Aggiungi un libro in corso',
        style: TextStyle(
          fontWeight: hasBook ? FontWeight.w600 : FontWeight.w400,
          color: hasBook ? MarginaliaColors.ink : MarginaliaColors.inkMuted,
        ),
      ),
      subtitle: hasBook
          ? Text((author ?? '').toUpperCase(),
              style: MarginaliaTextStyles.bookAuthor)
          : const Text(
              'Visibile ai membri delle tue Jam',
              style: TextStyle(fontSize: 12),
            ),
      trailing: const Icon(Icons.chevron_right,
          color: MarginaliaColors.inkMuted, size: 18),
      onTap: onTap,
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
