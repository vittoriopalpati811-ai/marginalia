import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/l10n/l10n_extension.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _userSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final _userSearchResultsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated) return [];
  return svc.searchUsers(query);
});

// ─── SearchScreen ─────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query      = ref.watch(_userSearchQueryProvider);
    final resultsAsync = ref.watch(_userSearchResultsProvider(query));

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Column(
        children: [
          // ── Gradient header ─────────────────────────────────────────────────
          Container(
            decoration: MarginaliaDecorations.gradientHeader,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // ── Back button ──────────────────────────────────
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(22),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withAlpha(35),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 15,
                              color: Color(0xFFF2F5EA),
                            ),
                          ),
                        ),
                        Text(
                          context.l10n.searchTitle,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF2F5EA),
                            letterSpacing: -0.8,
                            height: 1,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            context.l10n.searchSubtitle,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withAlpha(100),
                              letterSpacing: 0.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Search bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withAlpha(30), width: 0.5),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: false,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFFF2F5EA),
                          height: 1.4,
                        ),
                        cursorColor: const Color(0xFFF2F5EA),
                        decoration: InputDecoration(
                          hintText: context.l10n.searchHint,
                          hintStyle: TextStyle(
                            color: Colors.white.withAlpha(70),
                            fontSize: 15,
                          ),
                          prefixIcon: Icon(Icons.person_search_outlined,
                              color: Colors.white.withAlpha(80), size: 20),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear,
                                      color: Colors.white.withAlpha(80),
                                      size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    ref
                                        .read(_userSearchQueryProvider.notifier)
                                        .state = '';
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 14),
                        ),
                        onChanged: (v) =>
                            ref.read(_userSearchQueryProvider.notifier).state =
                                v,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Results ─────────────────────────────────────────────────────────
          Expanded(
            child: query.isEmpty
                ? const _EmptySearch()
                : resultsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: MarginaliaColors.sienna, strokeWidth: 1.5),
                    ),
                    error: (e, _) => Center(
                        child: Text('$e',
                            style: const TextStyle(
                                color: MarginaliaColors.inkMuted))),
                    data: (users) => users.isEmpty
                        ? _NoResults(query: query)
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 16, 16, 120),
                            itemCount: users.length,
                            itemBuilder: (ctx, i) => _UserCard(
                              user: users[i],
                              index: i,
                              onTap: () {
                                final id = users[i]['id'] as String? ?? '';
                                if (id.isNotEmpty) context.push('/user/$id');
                              },
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── User card ────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.index,
    required this.onTap,
  });
  final Map<String, dynamic> user;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name      = user['display_name'] as String? ?? 'Reader';
    final username  = user['username']     as String?;
    final avatarUrl = user['avatar_url']   as String?;
    final bio       = user['bio']          as String?;
    final initial   = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final tint      = MarginaliaDecorations.bookCoverColor(name);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: MarginaliaDecorations.card(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tint,
                shape: BoxShape.circle,
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(avatarUrl,
                          fit: BoxFit.cover,
                          width: 48,
                          height: 48,
                          errorBuilder: (_, __, ___) => _Initial(initial)),
                    )
                  : _Initial(initial),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MarginaliaColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (username != null && username.isNotEmpty)
                    Text(
                      '@$username',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: MarginaliaColors.sienna,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (bio != null && bio.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: MarginaliaColors.inkMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Arrow
            const Icon(Icons.chevron_right,
                size: 18, color: MarginaliaColors.inkFaint),
          ],
        ),
      ),
    )
        .animate(delay: (index * 30).ms)
        .fadeIn(duration: 220.ms, curve: Curves.easeOut)
        .slideY(begin: 0.02, end: 0, duration: 220.ms);
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.letter);
  final String letter;
  @override
  Widget build(BuildContext context) => Center(
        child: Text(letter,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      );
}

// ─── Empty / no-results ───────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: MarginaliaColors.siennaFaint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_search_outlined,
                size: 28, color: MarginaliaColors.siennaLight),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.searchEmpty,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MarginaliaColors.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.searchEmptyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MarginaliaColors.inkMuted,
              height: 1.65,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_outlined,
              size: 40, color: MarginaliaColors.inkFaint),
          const SizedBox(height: 12),
          Text(
            context.l10n.searchNoResults(query),
            style: const TextStyle(
                color: MarginaliaColors.inkMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

