import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/supabase_service.dart';

// Provider for user's jams (from Supabase)
final jamsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) {
    final service = ref.watch(supabaseServiceProvider);
    if (!service.isAuthenticated) return Future.value([]);
    return service.fetchMyJams();
  },
);

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  @override
  Widget build(BuildContext context) {
    final isAuth = ref.watch(isAuthenticatedProvider);

    if (!isAuth) return _UnauthenticatedState();

    final jamsAsync = ref.watch(jamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jam'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Crea Jam',
            onPressed: _showCreateJamSheet,
          ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Unisciti con codice',
            onPressed: _showJoinJamSheet,
          ),
        ],
      ),
      body: jamsAsync.when(
        data: (jams) => jams.isEmpty
            ? _EmptyJams(
                onCreateJam: _showCreateJamSheet,
                onJoinJam: _showJoinJamSheet,
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: jams.length,
                itemBuilder: (ctx, i) => _JamCard(
                  jam: jams[i],
                  index: i,
                ),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: MarginaliaColors.accent),
        ),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
    );
  }

  Future<void> _showCreateJamSheet() async {
    final nameController = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nuova Jam',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'es. "Il Nome della Rosa"',
                labelText: 'Nome della Jam',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;
                  final service = ref.read(supabaseServiceProvider);
                  await service.createJam(nameController.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Crea Jam'),
              ),
            ),
          ],
        ),
      ),
    );
    if (created == true) {
      ref.invalidate(jamsProvider);
    }
  }

  Future<void> _showJoinJamSheet() async {
    final codeController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MarginaliaColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Unisciti a una Jam',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Incolla il codice invito',
                labelText: 'Codice invito',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final code = codeController.text.trim();
                  if (code.isEmpty) return;
                  final service = ref.read(supabaseServiceProvider);
                  final jam = await service.fetchJamByInviteCode(code);
                  if (jam == null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Codice non valido.')),
                      );
                    }
                    return;
                  }
                  await service.joinJam(jam['id'] as String);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(jamsProvider);
                },
                child: const Text('Unisciti'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JamCard extends StatelessWidget {
  const _JamCard({required this.jam, required this.index});

  final Map<String, dynamic> jam;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = jam['name'] as String? ?? '';
    final code = jam['invite_code'] as String? ?? '';
    final memberCount = (jam['jam_members'] as List?)?.length ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(name, style: MarginaliaTextStyles.bookTitle),
        subtitle: Text(
          '$memberCount ${memberCount == 1 ? "membro" : "membri"}',
          style: MarginaliaTextStyles.bookAuthor,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy_outlined,
              size: 18, color: MarginaliaColors.textMuted),
          tooltip: 'Copia codice invito',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Codice invito copiato!')),
            );
          },
        ),
        onTap: () {/* TODO: push jam detail screen */},
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }
}

class _EmptyJams extends StatelessWidget {
  const _EmptyJams({required this.onCreateJam, required this.onJoinJam});

  final VoidCallback onCreateJam;
  final VoidCallback onJoinJam;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_outlined,
                size: 56, color: MarginaliaColors.accentLight),
            const SizedBox(height: 20),
            const Text(
              'Nessuna Jam ancora',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea una cerchia di lettura\no unisciti a quella di un amico.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MarginaliaColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onCreateJam,
              icon: const Icon(Icons.add),
              label: const Text('Crea Jam'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onJoinJam,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Unisciti con codice'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnauthenticatedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 56, color: MarginaliaColors.accentLight),
            const SizedBox(height: 20),
            const Text(
              'Accedi per usare le Jam',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.text),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le cerchie di lettura richiedono un account Marginalia.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MarginaliaColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () {/* go to auth screen */},
              child: const Text('Accedi o Registrati'),
            ),
          ],
        ),
      ),
    );
  }
}
