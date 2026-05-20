import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final conversationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  return svc.fetchConversations();
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: FloatingActionButton(
          onPressed: _showNewConversationSheet,
          backgroundColor: MarginaliaColors.primary,
          foregroundColor: Colors.white,
          elevation: 6,
          child: const Icon(Icons.edit_outlined, size: 22),
        ),
      ),
      body: Column(
        children: [
          // ── Gradient header ──────────────────────────────────────────────
          _MessagesHeader(),

          // ── Conversation list ────────────────────────────────────────────
          Expanded(
            child: conversationsAsync.when(
              data: (conversations) {
                if (conversations.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  color: MarginaliaColors.primary,
                  backgroundColor: MarginaliaColors.surface,
                  onRefresh: () async {
                    ref.invalidate(conversationsProvider);
                    await ref.read(conversationsProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      return _ConversationCard(
                        conversation: conv,
                        index: index,
                        onTap: () => context.push('/chat/${conv['id']}'),
                      ).animate(delay: (index * 40).ms)
                          .fadeIn(duration: 300.ms, curve: Curves.easeOut)
                          .slideY(begin: 0.04, end: 0, duration: 300.ms);
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.sienna,
                  strokeWidth: 1.5,
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: MarginaliaColors.inkFaint, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        'Errore nel caricamento',
                        style: GoogleFonts.barlow(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MarginaliaColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(conversationsProvider),
                        child: Text(
                          'Riprova',
                          style: GoogleFonts.barlow(
                            color: MarginaliaColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sheets ──────────────────────────────────────────────────────────────────

  void _showNewConversationSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NewConversationSheet(
        onConversationCreated: (id) {
          if (ctx.mounted) Navigator.pop(ctx);
          context.push('/chat/$id');
          ref.invalidate(conversationsProvider);
        },
      ),
    );
  }
}

// ─── Gradient Header ─────────────────────────────────────────────────────────

class _MessagesHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: MarginaliaDecorations.gradientHeader,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, topPadding > 0 ? 4 : 16, 20, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messaggi',
                      style: MarginaliaTextStyles.wordmarkLight,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Conversazioni e gruppi',
                      style: GoogleFonts.barlow(
                        color: const Color(0xFFF1EEE7).withAlpha(140),
                        fontSize: 12,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EEE7).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.send_outlined,
                  color: Color(0xFFF1EEE7),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conversation Card ───────────────────────────────────────────────────────

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.index,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation['is_group'] == true;
    final members =
        (conversation['members'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final lastMessage = conversation['last_message'] as Map<String, dynamic>?;

    // Derive display name and avatar
    String displayName;
    String? avatarUrl;

    if (isGroup) {
      displayName = conversation['group_name'] as String? ?? 'Gruppo';
      avatarUrl = conversation['group_avatar_url'] as String?;
    } else {
      // Find the other person (not current user)
      final otherMember = members.isNotEmpty ? members.first : null;
      displayName = otherMember?['display_name'] as String? ?? 'Utente';
      avatarUrl = otherMember?['avatar_url'] as String?;
    }

    // Last message preview
    String lastPreview = 'Nessun messaggio';
    String timeLabel = '';

    if (lastMessage != null) {
      final content = lastMessage['content'] as String?;
      final imageUrl = lastMessage['image_url'] as String?;
      if (content != null && content.isNotEmpty) {
        lastPreview = content;
      } else if (imageUrl != null) {
        lastPreview = '📷 Immagine';
      }

      final createdAt = lastMessage['created_at'] as String?;
      if (createdAt != null) {
        timeLabel = _formatTime(DateTime.tryParse(createdAt));
      }
    }

    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    final avatarBg = MarginaliaDecorations.bookCoverColor(displayName);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: MarginaliaColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.rule, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              _Avatar(
                avatarUrl: avatarUrl,
                initial: initial,
                color: avatarBg,
                size: 48,
                isGroup: isGroup,
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.barlow(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.ink,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: GoogleFonts.barlow(
                              fontSize: 11,
                              color: MarginaliaColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              color: MarginaliaColors.inkMuted,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (lastMessage != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: MarginaliaColors.sienna,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isGroup && members.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${members.length} partecipanti',
                        style: GoogleFonts.barlow(
                          fontSize: 11,
                          color: MarginaliaColors.inkFaint,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: MarginaliaColors.inkFaint,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'ora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${dt.day}/${dt.month}';
  }
}

// ─── Avatar widget ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.initial,
    required this.color,
    required this.size,
    this.isGroup = false,
  });

  final String? avatarUrl;
  final String initial;
  final Color color;
  final double size;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: ClipOval(
        child: avatarUrl != null && avatarUrl!.isNotEmpty
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialFallback(
                  initial: initial,
                  isGroup: isGroup,
                  size: size,
                ),
              )
            : _InitialFallback(
                initial: initial,
                isGroup: isGroup,
                size: size,
              ),
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  const _InitialFallback({
    required this.initial,
    required this.isGroup,
    required this.size,
  });

  final String initial;
  final bool isGroup;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return Center(
        child: Icon(Icons.group_outlined,
            color: Colors.white.withAlpha(220), size: size * 0.45),
      );
    }
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.ebGaramond(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.send_outlined,
                size: 36,
                color: MarginaliaColors.sienna,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Nessuna conversazione',
              style: GoogleFonts.ebGaramond(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Inizia a scrivere a un lettore\no crea un gruppo di lettura.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
  }
}

// ─── New Conversation Sheet ───────────────────────────────────────────────────

class _NewConversationSheet extends StatelessWidget {
  const _NewConversationSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Nuova conversazione',
                style: GoogleFonts.ebGaramond(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: MarginaliaColors.ink,
                ),
              ),
              const SizedBox(height: 24),

              // Direct message option
              _SheetOption(
                icon: Icons.person_outline,
                title: 'Messaggio diretto',
                subtitle: 'Scrivi a un lettore',
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => _UserSearchSheet(
                      onConversationCreated: onConversationCreated,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // Group option
              _SheetOption(
                icon: Icons.group_outlined,
                title: 'Crea gruppo',
                subtitle: 'Crea una chat di gruppo',
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => _CreateGroupSheet(
                      onConversationCreated: onConversationCreated,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: MarginaliaColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MarginaliaColors.rule, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MarginaliaColors.primaryFaint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: MarginaliaColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.barlow(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: MarginaliaColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 12,
                      color: MarginaliaColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: MarginaliaColors.inkFaint, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── User Search Sheet (direct message) ──────────────────────────────────────

class _UserSearchSheet extends ConsumerStatefulWidget {
  const _UserSearchSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  ConsumerState<_UserSearchSheet> createState() => _UserSearchSheetState();
}

class _UserSearchSheetState extends ConsumerState<_UserSearchSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(supabaseServiceProvider);
      final results = await svc.searchUsers(query.trim());
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore nella ricerca';
        _loading = false;
      });
    }
  }

  Future<void> _startConversation(String userId) async {
    try {
      final svc = ref.read(supabaseServiceProvider);
      final id = await svc.createOrFetchDirectConversation(userId);
      widget.onConversationCreated(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MarginaliaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Messaggio diretto',
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _search,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cerca utenti…',
                    prefixIcon: const Icon(Icons.search_outlined, size: 20),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: MarginaliaColors.sienna,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // Results
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: GoogleFonts.barlow(color: MarginaliaColors.inkMuted),
                    ),
                  )
                : _results.isEmpty && _searchController.text.isNotEmpty && !_loading
                    ? Center(
                        child: Text(
                          'Nessun utente trovato',
                          style: GoogleFonts.barlow(
                            color: MarginaliaColors.inkFaint,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          final name =
                              user['display_name'] as String? ?? 'Utente';
                          final username = user['username'] as String? ?? '';
                          final avatarUrl = user['avatar_url'] as String?;
                          final userId = user['id'] as String? ?? '';
                          final initial =
                              name.isNotEmpty ? name[0].toUpperCase() : '?';
                          final avatarBg =
                              MarginaliaDecorations.bookCoverColor(name);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: _Avatar(
                              avatarUrl: avatarUrl,
                              initial: initial,
                              color: avatarBg,
                              size: 42,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.barlow(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.ink,
                              ),
                            ),
                            subtitle: username.isNotEmpty
                                ? Text(
                                    '@$username',
                                    style: GoogleFonts.barlow(
                                      fontSize: 12,
                                      color: MarginaliaColors.inkFaint,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right,
                                color: MarginaliaColors.inkFaint, size: 18),
                            onTap: () => _startConversation(userId),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Create Group Sheet ───────────────────────────────────────────────────────

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet({required this.onConversationCreated});

  final void Function(String conversationId) onConversationCreated;

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _selectedUsers = [];
  bool _searchLoading = false;
  bool _creating = false;

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searchLoading = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      final results = await svc.searchUsers(query.trim());
      setState(() {
        _searchResults = results
            .where((u) => !_selectedUsers.any((s) => s['id'] == u['id']))
            .toList();
        _searchLoading = false;
      });
    } catch (_) {
      setState(() => _searchLoading = false);
    }
  }

  void _toggleUser(Map<String, dynamic> user) {
    setState(() {
      final exists = _selectedUsers.any((u) => u['id'] == user['id']);
      if (exists) {
        _selectedUsers.removeWhere((u) => u['id'] == user['id']);
      } else {
        _selectedUsers.add(user);
      }
      _searchResults = _searchResults
          .where((u) => !_selectedUsers.any((s) => s['id'] == u['id']))
          .toList();
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un nome per il gruppo.')),
      );
      return;
    }
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aggiungi almeno un partecipante.')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final svc = ref.read(supabaseServiceProvider);
      final memberIds =
          _selectedUsers.map((u) => u['id'] as String).toList();
      final id = await svc.createGroupConversation(
        memberIds,
        groupName: name,
      );
      widget.onConversationCreated(id);
    } catch (e) {
      setState(() => _creating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle + title
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 16, 24, MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MarginaliaColors.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nuovo gruppo',
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: MarginaliaColors.ink,
                  ),
                ),
                const SizedBox(height: 16),

                // Group name
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Nome del gruppo…',
                    prefixIcon: Icon(Icons.group_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // User search
                TextField(
                  controller: _searchController,
                  onChanged: _search,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    color: MarginaliaColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cerca utenti da aggiungere…',
                    prefixIcon: const Icon(Icons.person_add_outlined, size: 20),
                    suffixIcon: _searchLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: MarginaliaColors.sienna,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),

                // Selected chips
                if (_selectedUsers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selectedUsers.map((user) {
                      final name = user['display_name'] as String? ?? 'Utente';
                      return Chip(
                        label: Text(name),
                        onDeleted: () => _toggleUser(user),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        backgroundColor: MarginaliaColors.primaryFaint,
                        labelStyle: GoogleFonts.barlow(
                          fontSize: 12,
                          color: MarginaliaColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Search results
          Expanded(
            child: _searchResults.isEmpty && _searchController.text.isEmpty
                ? Center(
                    child: Text(
                      'Cerca un utente per aggiungerlo',
                      style: GoogleFonts.barlow(
                        color: MarginaliaColors.inkFaint,
                        fontSize: 13,
                      ),
                    ),
                  )
                : _searchResults.isEmpty && _searchController.text.isNotEmpty && !_searchLoading
                    ? Center(
                        child: Text(
                          'Nessun utente trovato',
                          style: GoogleFonts.barlow(
                            color: MarginaliaColors.inkFaint,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final name =
                              user['display_name'] as String? ?? 'Utente';
                          final username = user['username'] as String? ?? '';
                          final avatarUrl = user['avatar_url'] as String?;
                          final initial =
                              name.isNotEmpty ? name[0].toUpperCase() : '?';
                          final avatarBg =
                              MarginaliaDecorations.bookCoverColor(name);
                          final isSelected = _selectedUsers
                              .any((u) => u['id'] == user['id']);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: _Avatar(
                              avatarUrl: avatarUrl,
                              initial: initial,
                              color: avatarBg,
                              size: 40,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.barlow(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.ink,
                              ),
                            ),
                            subtitle: username.isNotEmpty
                                ? Text(
                                    '@$username',
                                    style: GoogleFonts.barlow(
                                      fontSize: 12,
                                      color: MarginaliaColors.inkFaint,
                                    ),
                                  )
                                : null,
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: MarginaliaColors.primary, size: 20)
                                : const Icon(Icons.add_circle_outline,
                                    color: MarginaliaColors.inkFaint, size: 20),
                            onTap: () => _toggleUser(user),
                          );
                        },
                      ),
          ),

          // Create button
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _creating ? null : _createGroup,
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Crea gruppo'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
