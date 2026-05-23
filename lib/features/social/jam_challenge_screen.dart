import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Jam Challenge Screen ─────────────────────────────────────────────────────

class JamChallengeScreen extends ConsumerStatefulWidget {
  const JamChallengeScreen({super.key, required this.jamId});
  final String jamId;

  @override
  ConsumerState<JamChallengeScreen> createState() => _JamChallengeScreenState();
}

class _JamChallengeScreenState extends ConsumerState<JamChallengeScreen> {
  @override
  Widget build(BuildContext context) {
    final challengesAsync = ref.watch(jamChallengesProvider(widget.jamId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Sfide di lettura',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: MarginaliaColors.ink,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: MarginaliaColors.primary),
            onPressed: _showCreateSheet,
            tooltip: 'Crea sfida',
          ),
        ],
      ),
      body: challengesAsync.when(
        data: (challenges) => challenges.isEmpty
            ? _EmptyState(onCreate: _showCreateSheet)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: challenges.length,
                itemBuilder: (_, i) => _ChallengeCard(
                  data: challenges[i],
                  currentUserId: currentUser?.id ?? '',
                  onProgressUpdate: (count) => _updateProgress(
                    challenges[i]['id'] as String,
                    count,
                  ),
                ).animate(delay: (i * 40).ms).fadeIn(duration: 280.ms).slideY(begin: 0.04, end: 0),
              ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: MarginaliaColors.primary, strokeWidth: 1.5),
        ),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Future<void> _updateProgress(String challengeId, int count) async {
    try {
      await ref.read(supabaseServiceProvider).updateChallengeProgress(
            challengeId: challengeId,
            count: count,
          );
      ref.invalidate(jamChallengesProvider(widget.jamId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    }
  }

  void _showCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateChallengeSheet(
        jamId: widget.jamId,
        onCreated: () => ref.invalidate(jamChallengesProvider(widget.jamId)),
      ),
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _ChallengeCard extends StatefulWidget {
  const _ChallengeCard({
    required this.data,
    required this.currentUserId,
    required this.onProgressUpdate,
  });

  final Map<String, dynamic> data;
  final String currentUserId;
  final void Function(int) onProgressUpdate;

  @override
  State<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<_ChallengeCard> {
  int get _myProgress {
    final progList = widget.data['jam_challenge_progress'] as List? ?? [];
    final myEntry = progList.firstWhere(
      (p) => p['user_id'] == widget.currentUserId,
      orElse: () => <String, dynamic>{},
    );
    return (myEntry['current_count'] as int?) ?? 0;
  }

  int get _targetCount => (widget.data['target_count'] as int?) ?? 1;
  String get _unit => widget.data['unit'] as String? ?? 'books';
  DateTime? get _deadline {
    final s = widget.data['deadline'] as String?;
    return s != null ? DateTime.tryParse(s) : null;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _myProgress;
    final target = _targetCount;
    final fraction = (progress / target).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarginaliaColors.rule, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: MarginaliaColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.data['title'] as String? ?? '',
                  style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
              ),
            ],
          ),
          if ((widget.data['description'] as String?) != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.data['description'] as String,
              style: GoogleFonts.manrope(fontSize: 13, color: MarginaliaColors.inkMuted),
            ),
          ],
          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: MarginaliaColors.primaryFaint,
              color: MarginaliaColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$progress / $target $_unit',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: MarginaliaColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_deadline != null)
                Text(
                  'Scadenza: ${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                  style: GoogleFonts.manrope(fontSize: 11, color: MarginaliaColors.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // +/- controls for personal progress
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ProgressButton(
                icon: Icons.remove,
                onTap: progress > 0
                    ? () => widget.onProgressUpdate(progress - 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$progress',
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
              ),
              _ProgressButton(
                icon: Icons.add,
                onTap: progress < target
                    ? () => widget.onProgressUpdate(progress + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressButton extends StatelessWidget {
  const _ProgressButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 150.ms,
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null ? MarginaliaColors.primaryFaint : const Color(0x0F000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? MarginaliaColors.primary : MarginaliaColors.inkFaint,
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 56, color: MarginaliaColors.inkFaint),
            const SizedBox(height: 16),
            Text(
              'Nessuna sfida attiva',
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: MarginaliaColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'Crea una sfida condivisa e motiva i tuoi compagni di lettura.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: MarginaliaColors.inkMuted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crea sfida'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create challenge sheet ───────────────────────────────────────────────────

class _CreateChallengeSheet extends ConsumerStatefulWidget {
  const _CreateChallengeSheet({required this.jamId, required this.onCreated});
  final String jamId;
  final VoidCallback onCreated;

  @override
  ConsumerState<_CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends ConsumerState<_CreateChallengeSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _target = 1;
  String _unit = 'books';
  DateTime? _deadline;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(supabaseServiceProvider).createChallenge(
            jamId: widget.jamId,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            targetCount: _target,
            unit: _unit,
            deadline: _deadline,
          );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.errorPrefix(e.toString())}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: MarginaliaColors.rule, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Crea sfida',
              style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: MarginaliaColors.ink),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(hintText: 'Nome sfida *', prefixIcon: Icon(Icons.emoji_events_outlined)),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(hintText: 'Descrizione (opzionale)'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Target + unit
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Obiettivo', style: GoogleFonts.manrope(fontSize: 12, color: MarginaliaColors.inkMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _ProgressButton(
                            icon: Icons.remove,
                            onTap: _target > 1 ? () => setState(() => _target--) : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('$_target', style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w600)),
                          ),
                          _ProgressButton(
                            icon: Icons.add,
                            onTap: () => setState(() => _target++),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unità', style: GoogleFonts.manrope(fontSize: 12, color: MarginaliaColors.inkMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _unit,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        items: const [
                          DropdownMenuItem(value: 'books', child: Text('Libri')),
                          DropdownMenuItem(value: 'highlights', child: Text('Highlight')),
                          DropdownMenuItem(value: 'chapters', child: Text('Capitoli')),
                        ],
                        onChanged: (v) => setState(() => _unit = v ?? 'books'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Deadline picker
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _deadline = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                _deadline != null
                    ? 'Scadenza: ${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'
                    : 'Imposta scadenza (opzionale)',
                style: GoogleFonts.manrope(fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Crea'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


