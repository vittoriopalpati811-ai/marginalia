import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/jam_features_provider.dart';
import '../../core/l10n/l10n_extension.dart';
import 'jam_highlight_detail_screen.dart'
    show reactionsProvider, commentsProvider, JamHighlightDetailScreen;
import 'weekly_prompt.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

/// Single jam row — used to get invite_code and metadata.
final jamDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, jamId) => ref.watch(supabaseServiceProvider).fetchJam(jamId),
);

/// Highlights shared in this jam, ordered by most-recent.
final jamHighlightsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) =>
      ref.watch(supabaseServiceProvider).fetchJamHighlights(jamId),
);

/// Members with profile data (display_name, currently_reading_*).
final jamMembersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, jamId) async {
    try {
      return await ref.watch(supabaseServiceProvider).fetchJamMembers(jamId);
    } catch (_) {
      return [];
    }
  },
);

// ─── Screen ───────────────────────────────────────────────────────────────────

class JamDetailScreen extends ConsumerStatefulWidget {
  const JamDetailScreen({
    super.key,
    required this.jamId,
    required this.jamName,
  });

  final String jamId;
  final String jamName;

  @override
  ConsumerState<JamDetailScreen> createState() => _JamDetailScreenState();
}

class _JamDetailScreenState extends ConsumerState<JamDetailScreen> {
  RealtimeChannel? _channel;
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    final service = ref.read(supabaseServiceProvider);
    _channel = service.subscribeToJam(widget.jamId, (_) {
      if (mounted) ref.invalidate(jamHighlightsProvider(widget.jamId));
    });
  }

  // ── Invite sharing ──────────────────────────────────────────────────────────

  Future<void> _shareInviteCode(String? code) async {
    final inviteCode = code ?? widget.jamId.substring(0, 8).toUpperCase();
    await Share.share(
      'Join my Jam on Marginalia! 📚\n\n'
      'Code: $inviteCode\n\n'
      'Download the app: https://marginalia.app',
      subject: 'Join the Jam "${widget.jamName}"',
    );
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.jamCopiedToClipboard)),
    );
  }

  // ── Cover photo ──────────────────────────────────────────────────────────────

  Future<void> _pickJamCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    final file = result.files.first;
    setState(() => _uploadingCover = true);
    try {
      await ref.read(supabaseServiceProvider).uploadJamCover(
            widget.jamId,
            file.bytes!,
            (file.extension ?? 'jpg').toLowerCase(),
          );
      ref.invalidate(jamDetailProvider(widget.jamId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.jamCoverUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload error: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  // ── Share highlight picker ──────────────────────────────────────────────────

  Future<void> _shareHighlight({String? filterByBookTitle}) async {
    final list = await ref.read(allHighlightsProvider.future);

    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.jamNoHighlightsAvailable),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SharePickerSheet(
        highlights: list,
        filterByBookTitle: filterByBookTitle,
        onPick: (highlight) async {
          Navigator.pop(ctx);
          final service = ref.read(supabaseServiceProvider);
          try {
            await service.shareHighlightInJam(
              widget.jamId,
              (highlight.supabaseId != null &&
                      (highlight.supabaseId as String).isNotEmpty)
                  ? highlight.supabaseId as String
                  : '${highlight.id}',
            );
            ref.invalidate(jamHighlightsProvider(widget.jamId));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.jamHighlightShared)),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        },
      ),
    );
  }

  // ── Member profile sheet ────────────────────────────────────────────────────

  void _showMemberProfile(Map<String, dynamic> member) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberProfileSheet(member: member),
    );
  }

  // ── Discussion ──────────────────────────────────────────────────────────────

  void _openDiscussion(Map<String, dynamic> data) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final book = highlight?['books'] as Map<String, dynamic>?;
    final profile = data['profiles'] as Map<String, dynamic>?;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JamHighlightDetailScreen(
        jamHighlightId: data['id'] as String,
        content: highlight?['content'] as String? ?? '',
        bookTitle: book?['title'] as String? ?? '',
        bookAuthor: book?['author'] as String? ?? '',
        sharedBy: profile?['display_name'] as String? ?? 'User',
      ),
    ));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final jamAsync = ref.watch(jamHighlightsProvider(widget.jamId));
    final membersAsync = ref.watch(jamMembersProvider(widget.jamId));
    final jamDetailAsync = ref.watch(jamDetailProvider(widget.jamId));
    final prompt = WeeklyPrompt.current();
    final unreadCount = ref.watch(unreadNotificationCountProvider).maybeWhen(
      data: (n) => n,
      orElse: () => 0,
    );

    final inviteCode = jamDetailAsync.maybeWhen(
      data: (j) => j?['invite_code'] as String?,
      orElse: () => null,
    );
    final jamCoverUrl = jamDetailAsync.maybeWhen(
      data: (j) => j?['cover_url'] as String?,
      orElse: () => null,
    );

    final memberCount = membersAsync.maybeWhen(
      data: (m) => m.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            stretch: true,
            backgroundColor: MarginaliaColors.primary,
            foregroundColor: const Color(0xFFF1EEE7),
            elevation: 0,
            scrolledUnderElevation: 0,
            // Keep status-bar icons white even when the hero image is visible.
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarBrightness: Brightness.dark,        // iOS
              statusBarIconBrightness: Brightness.light,   // Android
              statusBarColor: Colors.transparent,
            ),
            actions: [
              // Notification bell with unread dot
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: context.l10n.notificationsTitle,
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE64A4A),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MarginaliaColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Cover photo upload button
              _uploadingCover
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 1.5),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.image_outlined),
                      tooltip: 'Cambia copertina Jam',
                      onPressed: _pickJamCover,
                    ),
              IconButton(
                icon: const Icon(Icons.ios_share_outlined),
                tooltip: 'Invita amici',
                onPressed: () => _shareInviteCode(inviteCode),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              stretchModes: const [StretchMode.blurBackground],
              // Only use FlexibleSpaceBar.title when a cover photo is shown —
              // the no-cover background already renders the name in large type.
              title: (jamCoverUrl != null && jamCoverUrl.isNotEmpty)
                  ? Text(
                      widget.jamName,
                      style: const TextStyle(
                        color: Color(0xFFF1EEE7),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    )
                  : null,
              titlePadding:
                  const EdgeInsetsDirectional.fromSTEB(56, 0, 56, 16),
              background: jamCoverUrl != null && jamCoverUrl.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(jamCoverUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(decoration: MarginaliaDecorations.gradientHeader)),
                        // Top scrim — keeps status-bar icons visible over photos.
                        // Bottom scrim — ensures title text is readable.
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withAlpha(90),  // top scrim
                                Colors.transparent,
                                Colors.black.withAlpha(130), // bottom scrim
                              ],
                              stops: const [0.0, 0.30, 1.0],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                decoration: MarginaliaDecorations.gradientHeader,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Label chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1EEE7).withAlpha(28),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'JAM',
                            style: TextStyle(
                              color: Color(0xCCF1EEE7),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Jam name
                        Text(
                          widget.jamName,
                          style: const TextStyle(
                            color: Color(0xFFF1EEE7),
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        if (memberCount > 0)
                          Text(
                            '$memberCount ${context.l10n.jamMemberCount(memberCount)}',
                            style: TextStyle(
                              color:
                                  const Color(0xFFF1EEE7).withAlpha(160),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        // Invite code pill — tappable to copy
                        if (inviteCode != null) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _copyInviteCode(inviteCode),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFF1EEE7).withAlpha(20),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFF1EEE7)
                                        .withAlpha(50)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.key_outlined,
                                    size: 12,
                                    color: const Color(0xFFF1EEE7)
                                        .withAlpha(180),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    inviteCode,
                                    style: const TextStyle(
                                      color: Color(0xDDF1EEE7),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.copy_outlined,
                                    size: 12,
                                    color: const Color(0xFFF1EEE7)
                                        .withAlpha(150),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Prompt settimanale ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _WeeklyPromptBanner(prompt: prompt),
          ),

          // ── Feature cards ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _JamFeaturesRow(jamId: widget.jamId),
          ),

          // ── Membri ─────────────────────────────────────────────────────
          membersAsync.when(
            data: (members) => SliverToBoxAdapter(
              child: _MembersStrip(
                members: members,
                onTapMember: _showMemberProfile,
              ),
            ),
            loading: () =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Di tendenza (top 3 most-recent highlights as spotlight) ────
          jamAsync.maybeWhen(
            data: (highlights) => highlights.length >= 2
                ? SliverToBoxAdapter(
                    child: _TrendingSection(
                      highlights: highlights.take(3).toList(),
                      onTap: _openDiscussion,
                    ),
                  )
                : const SliverToBoxAdapter(child: SizedBox.shrink()),
            orElse: () =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ── Section header ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text('TUTTI GLI HIGHLIGHT',
                      style: MarginaliaTextStyles.sectionTitle),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Divider(color: MarginaliaColors.rule)),
                ],
              ),
            ),
          ),

          // ── Highlight list ─────────────────────────────────────────────
          jamAsync.when(
            data: (highlights) => highlights.isEmpty
                ? SliverFillRemaining(
                    child: _EmptyJamHighlights(
                      onShare: _shareHighlight,
                      inviteCode: inviteCode,
                      onInvite: () => _shareInviteCode(inviteCode),
                      onCopy: inviteCode != null
                          ? () => _copyInviteCode(inviteCode)
                          : null,
                    ),
                  )
                : SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    sliver: SliverList.builder(
                      itemCount: highlights.length,
                      itemBuilder: (ctx, i) {
                        final data = highlights[i];
                        return _JamHighlightCard(
                          data: data,
                          index: i,
                          onTap: () => _openDiscussion(data),
                          onMatchTap: (bookTitle) =>
                              _shareHighlight(
                                  filterByBookTitle: bookTitle),
                        );
                      },
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: MarginaliaColors.primary,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _shareHighlight(),
        backgroundColor: MarginaliaColors.primary,
        foregroundColor: const Color(0xFFF1EEE7),
        elevation: 4,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(
          context.l10n.share,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─── Trending section ─────────────────────────────────────────────────────────

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({required this.highlights, required this.onTap});

  final List<Map<String, dynamic>> highlights;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text('DI TENDENZA',
                  style: MarginaliaTextStyles.sectionTitle),
            ],
          ),
        ),
        SizedBox(
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: highlights.length,
            itemBuilder: (_, i) {
              final data = highlights[i];
              final highlight =
                  data['highlights'] as Map<String, dynamic>?;
              final content =
                  highlight?['content'] as String? ?? '';
              final book =
                  highlight?['books'] as Map<String, dynamic>?;
              final bookTitle =
                  book?['title'] as String? ?? '';
              final profile =
                  data['profiles'] as Map<String, dynamic>?;
              final sharedBy =
                  profile?['display_name'] as String? ?? 'User';

              final coverColor =
                  MarginaliaDecorations.bookCoverColor(
                      bookTitle.isNotEmpty ? bookTitle : sharedBy);

              return GestureDetector(
                onTap: () => onTap(data),
                child: Container(
                  width: 216,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        coverColor,
                        Color.fromARGB(
                          255,
                          (coverColor.red * 0.6).round(),
                          (coverColor.green * 0.6).round(),
                          (coverColor.blue * 0.6).round(),
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x28261E1D),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Rank badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(28),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '#${i + 1}',
                            style: const TextStyle(
                              color: Color(0xEEF1EEE7),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Text(
                            content.length > 100
                                ? '${content.substring(0, 100)}…'
                                : content,
                            style: const TextStyle(
                              color: Color(0xEEF1EEE7),
                              fontSize: 12,
                              height: 1.55,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Bottom: book title + shared-by
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                bookTitle.isNotEmpty
                                    ? bookTitle
                                    : sharedBy,
                                style: const TextStyle(
                                  color: Color(0xAAF1EEE7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: Color(0x88F1EEE7),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  .animate(delay: (i * 60).ms)
                  .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                  .slideX(
                      begin: 0.06,
                      end: 0,
                      duration: 280.ms,
                      curve: Curves.easeOut);
            },
          ),
        ),
      ],
    );
  }
}

// ─── Weekly prompt banner ─────────────────────────────────────────────────────

class _WeeklyPromptBanner extends StatelessWidget {
  const _WeeklyPromptBanner({required this.prompt});
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: MarginaliaColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22261E1D),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome,
                color: Color(0xFFF1EEE7), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROMPT DELLA SETTIMANA',
                    style: TextStyle(
                      color: Color(0x99F1EEE7),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prompt,
                    style: const TextStyle(
                      color: Color(0xFFF1EEE7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Members strip ────────────────────────────────────────────────────────────

class _MembersStrip extends StatelessWidget {
  const _MembersStrip({
    required this.members,
    required this.onTapMember,
  });
  final List<Map<String, dynamic>> members;
  final void Function(Map<String, dynamic>) onTapMember;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text('MEMBRI', style: MarginaliaTextStyles.sectionTitle),
        ),
        SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: members.length,
            itemBuilder: (_, i) {
              final m = members[i];
              final profile = m['profile'] as Map<String, dynamic>?;
              final name =
                  profile?['display_name'] as String? ?? 'User';
              final readingTitle =
                  profile?['currently_reading_title'] as String?;
              final initial =
                  name.isNotEmpty ? name[0].toUpperCase() : '?';
              final isOwner = m['role'] == 'owner';
              final isReading =
                  readingTitle != null && readingTitle.isNotEmpty;
              final avatarColor =
                  MarginaliaDecorations.bookCoverColor(name);

              return GestureDetector(
                onTap: () => onTapMember(m),
                child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Tooltip(
                  message: isReading ? 'Sta leggendo: $readingTitle' : name,
                  preferBelow: true,
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  avatarColor,
                                  MarginaliaColors.primaryDark,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(26),
                              border: isOwner
                                  ? Border.all(
                                      color: MarginaliaColors.sienna,
                                      width: 2.5,
                                    )
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFFF1EEE7),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          // Reading indicator dot
                          if (isReading)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: MarginaliaColors.primary,
                                  borderRadius:
                                      BorderRadius.circular(9),
                                  border: Border.all(
                                    color: MarginaliaColors.background,
                                    width: 2,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.auto_stories,
                                      size: 8,
                                      color: MarginaliaColors.primary),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 58,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            color: MarginaliaColors.inkMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyJamHighlights extends StatelessWidget {
  const _EmptyJamHighlights({
    required this.onShare,
    this.inviteCode,
    required this.onInvite,
    this.onCopy,
  });

  final VoidCallback onShare;
  final String? inviteCode;
  final VoidCallback onInvite;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: MarginaliaColors.primaryFaint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_stories_outlined,
              size: 32,
              color: MarginaliaColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'The Jam is quiet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Be the first to share a highlight\nor invite friends to join.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MarginaliaColors.inkMuted,
              fontSize: 14,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            label: Text(context.l10n.jamShareHighlightCta),
          ),
          if (inviteCode != null) ...[
            const SizedBox(height: 20),
            // Invite code card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MarginaliaColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MarginaliaColors.rule),
              ),
              child: Column(
                children: [
                  const Text(
                    'INVITE CODE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: MarginaliaColors.inkMuted,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    inviteCode!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: MarginaliaColors.primary,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.jamShareCode,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MarginaliaColors.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onCopy,
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: Text(context.l10n.copy),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: MarginaliaColors.primary,
                            side: const BorderSide(
                                color: MarginaliaColors.rule),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onInvite,
                          icon: const Icon(Icons.ios_share_outlined,
                              size: 16),
                          label: Text(context.l10n.share),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Share picker bottom sheet ────────────────────────────────────────────────

class _SharePickerSheet extends StatefulWidget {
  const _SharePickerSheet({
    required this.highlights,
    required this.onPick,
    this.filterByBookTitle,
  });

  final List highlights;
  final void Function(dynamic highlight) onPick;
  final String? filterByBookTitle;

  @override
  State<_SharePickerSheet> createState() => _SharePickerSheetState();
}

class _SharePickerSheetState extends State<_SharePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.filterByBookTitle != null) {
      _query = widget.filterByBookTitle!;
      _searchController.text = widget.filterByBookTitle!;
    }
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.highlights
        : widget.highlights.where((h) {
            final q = _query.toLowerCase();
            return (h.content as String).toLowerCase().contains(q) ||
                ((h.bookTitle as String?) ?? '').toLowerCase().contains(q);
          }).toList();

    // Group by book title — alphabetical within each group.
    final grouped = <String, List<dynamic>>{};
    for (final h in filtered) {
      final title = (h.bookTitle as String?) ?? 'Senza titolo';
      grouped.putIfAbsent(title, () => []).add(h);
    }
    final bookTitles = grouped.keys.toList()..sort();

    // Flatten into a single list: [{_header, title, count}, highlight, ...]
    final flatItems = <dynamic>[];
    for (final title in bookTitles) {
      flatItems
          .add({'_header': true, 'title': title, 'count': grouped[title]!.length});
      flatItems.addAll(grouped[title]!);
    }

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // ── Handle ─────────────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MarginaliaColors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.jamPickHighlight,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} '
                          '${filtered.length == 1 ? "risultato" : "risultati"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MarginaliaColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Search bar ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: widget.filterByBookTitle == null,
                decoration: InputDecoration(
                  hintText: context.l10n.jamSearchHint,
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: MarginaliaColors.inkMuted,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            const Divider(height: 1, color: MarginaliaColors.rule),
            // ── List ───────────────────────────────────────────────────
            Expanded(
              child: flatItems.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.jamNoHighlightsFound,
                        style: const TextStyle(color: MarginaliaColors.inkMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: flatItems.length,
                      itemBuilder: (_, idx) {
                        final item = flatItems[idx];
                        // Book group header
                        if (item is Map && item['_header'] == true) {
                          return _BookGroupHeader(
                            title: item['title'] as String,
                            count: item['count'] as int,
                          );
                        }
                        // Highlight item
                        return _SharePickerItem(
                          highlight: item,
                          onTap: () => widget.onPick(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookGroupHeader extends StatelessWidget {
  const _BookGroupHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: MarginaliaColors.sienna,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MarginaliaColors.sienna,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              color: MarginaliaColors.inkFaint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SharePickerItem extends StatelessWidget {
  const _SharePickerItem({required this.highlight, required this.onTap});
  final dynamic highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = highlight.content as String;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: MarginaliaDecorations.card(),
          child: Text(
            content.length > 150
                ? '${content.substring(0, 150)}…'
                : content,
            style: MarginaliaTextStyles.highlightBodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ─── Jam highlight card ────────────────────────────────────────────────────────

class _JamHighlightCard extends ConsumerWidget {
  const _JamHighlightCard({
    required this.data,
    required this.index,
    required this.onTap,
    required this.onMatchTap,
  });

  final Map<String, dynamic> data;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<String> onMatchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlight = data['highlights'] as Map<String, dynamic>?;
    final content = highlight?['content'] as String? ?? '';
    final book = highlight?['books'] as Map<String, dynamic>?;
    final bookTitle = book?['title'] as String? ?? '';
    final bookAuthor = book?['author'] as String? ?? '';
    final color = highlight?['color'] as String?;
    final profile = data['profiles'] as Map<String, dynamic>?;
    final sharedBy = profile?['display_name'] as String? ?? 'User';
    final sharedAt = data['shared_at'] as String?;
    final jhId = data['id'] as String? ?? '';

    final accentColor = _accentFor(color);

    final reactionsAsync = ref.watch(reactionsProvider(jhId));
    final commentsAsync = ref.watch(commentsProvider(jhId));
    final myHighlightsAsync = ref.watch(allHighlightsProvider);

    final myMatchCount = myHighlightsAsync.maybeWhen(
      data: (list) => list
          .where((h) =>
              (h.bookTitle ?? '').toLowerCase() == bookTitle.toLowerCase())
          .length,
      orElse: () => 0,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: MarginaliaDecorations.card(),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Accent strip
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Book info
                      if (bookTitle.isNotEmpty) ...[
                        Text(
                          bookTitle,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MarginaliaColors.sienna,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (bookAuthor.isNotEmpty)
                          Text(
                            bookAuthor.toUpperCase(),
                            style: MarginaliaTextStyles.bookAuthor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                      ],
                      // Content
                      Text(
                        content,
                        style: MarginaliaTextStyles.highlightBodySmall,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Footer row
                      Row(
                        children: [
                          // Shared-by chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.primaryFaint,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              sharedBy,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: MarginaliaColors.primary,
                              ),
                            ),
                          ),
                          if (sharedAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(sharedAt),
                              style: MarginaliaTextStyles.label,
                            ),
                          ],
                          const Spacer(),
                          // Reaction count
                          reactionsAsync.maybeWhen(
                            data: (rxs) => rxs.isEmpty
                                ? const SizedBox.shrink()
                                : _CountChip(
                                    icon: Icons.favorite_outline,
                                    count: rxs.length,
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                          // Comment count
                          commentsAsync.maybeWhen(
                            data: (c) => c.isEmpty
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding:
                                        const EdgeInsets.only(left: 8),
                                    child: _CountChip(
                                      icon: Icons.chat_bubble_outline,
                                      count: c.length,
                                    ),
                                  ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      // Match suggestion
                      if (myMatchCount > 0 && bookTitle.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => onMatchTap(bookTitle),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(
                                10, 8, 12, 8),
                            decoration: BoxDecoration(
                              color: MarginaliaColors.siennaFaint,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: MarginaliaColors.siennaLight
                                    .withAlpha(80),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 14,
                                  color: MarginaliaColors.sienna,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Hai $myMatchCount '
                                    '${myMatchCount == 1 ? "citazione" : "citazioni"}'
                                    ' da questo libro · Rispondi',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: MarginaliaColors.sienna,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 40).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(begin: 0.03, end: 0, duration: 300.ms);
  }

  Color _accentFor(String? color) => switch (color) {
        'yellow' => const Color(0xFFD4A017),
        'blue' => const Color(0xFF4A90BF),
        'pink' => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _ => MarginaliaColors.siennaLight,
      };

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}

// ─── Count chip ───────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.count});
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: MarginaliaColors.inkMuted),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.inkMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Jam features row ─────────────────────────────────────────────────────────

class _JamFeaturesRow extends StatelessWidget {
  const _JamFeaturesRow({required this.jamId});
  final String jamId;

  @override
  Widget build(BuildContext context) {
    final features = [
      (
        icon: Icons.menu_book_rounded,
        label: context.l10n.jamFeatureVoting,
        sub: context.l10n.jamFeatureVotingSubtitle,
        route: '/jam/$jamId/voting',
      ),
      (
        icon: Icons.emoji_events_outlined,
        label: context.l10n.jamFeatureChallenges,
        sub: context.l10n.jamFeatureChallengesSubtitle,
        route: '/jam/$jamId/challenges',
      ),
      (
        icon: Icons.how_to_vote_outlined,
        label: context.l10n.jamFeaturePolls,
        sub: context.l10n.jamFeaturePollsSubtitle,
        route: '/jam/$jamId/polls',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            children: [
              Text('ACTIVITY', style: MarginaliaTextStyles.sectionTitle),
              const SizedBox(width: 12),
              const Expanded(child: Divider(color: MarginaliaColors.rule)),
            ],
          ),
        ),
        SizedBox(
          height: 98,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: features.length,
            itemBuilder: (_, i) {
              final f = features[i];
              return GestureDetector(
                onTap: () => context.push(f.route),
                child: Container(
                  width: 136,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MarginaliaColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: MarginaliaColors.rule, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.icon,
                          size: 20, color: MarginaliaColors.primary),
                      const Spacer(),
                      Text(
                        f.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MarginaliaColors.ink,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.sub,
                        style: const TextStyle(
                          fontSize: 10,
                          color: MarginaliaColors.inkFaint,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              )
                  .animate(delay: (i * 50).ms)
                  .fadeIn(duration: 260.ms)
                  .slideX(begin: 0.05, end: 0, duration: 260.ms);
            },
          ),
        ),
      ],
    );
  }
}

// ─── Member profile sheet ─────────────────────────────────────────────────────

class _MemberProfileSheet extends StatelessWidget {
  const _MemberProfileSheet({required this.member});
  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final profile = member['profile'] as Map<String, dynamic>? ?? {};
    final name = profile['display_name'] as String? ?? 'User';
    final username = profile['username'] as String?;
    final readingTitle = profile['currently_reading_title'] as String?;
    final readingAuthor = profile['currently_reading_author'] as String?;
    final isOwner = member['role'] == 'owner';
    final userId = member['user_id'] as String? ??
        profile['id'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatarColor = MarginaliaDecorations.bookCoverColor(name);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MarginaliaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
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
          const SizedBox(height: 28),

          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [avatarColor, MarginaliaColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
              border: isOwner
                  ? Border.all(
                      color: MarginaliaColors.sienna, width: 3)
                  : null,
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFFF1EEE7),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // Owner badge
          if (isOwner) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'OWNER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: MarginaliaColors.sienna,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Name
          Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MarginaliaColors.ink,
              letterSpacing: -0.4,
            ),
          ),
          if (username != null && username.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$username',
              style: const TextStyle(
                fontSize: 14,
                color: MarginaliaColors.inkMuted,
              ),
            ),
          ],

          // Currently reading card
          if (readingTitle != null && readingTitle.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MarginaliaColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MarginaliaColors.rule),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories,
                      size: 16, color: MarginaliaColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.jamMemberCurrentlyReading
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: MarginaliaColors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          readingTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: MarginaliaColors.ink,
                          ),
                        ),
                        if (readingAuthor != null &&
                            readingAuthor.isNotEmpty)
                          Text(
                            readingAuthor.toUpperCase(),
                            style: MarginaliaTextStyles.bookAuthor,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // View profile button
          if (userId.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/user/$userId');
                },
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('Visualizza profilo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MarginaliaColors.primary,
                  side: const BorderSide(color: MarginaliaColors.rule),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
