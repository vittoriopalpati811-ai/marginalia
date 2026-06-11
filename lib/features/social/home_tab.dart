// ─── HomeTab ──────────────────────────────────────────────────────────────────
//
// First tab — social feed.
// Plain header with wordmark + "Scrivi" button floating over the paper
// background (no colored bar), then the full FeedTab.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import 'feed_tab.dart'; // FeedTab, CreatePostSheet, postsProvider, feedProvider

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      body: Column(
        children: [
          _HomeHeader(onCreatePost: () => _openCreatePost(context, ref)),
          const Expanded(child: FeedTab()),
        ],
      ),
    );
  }

  Future<void> _openCreatePost(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Host ABOVE the shell bottom-nav (root navigator) — otherwise the sheet
      // is placed under the shell and its TextField can't hold focus on iOS
      // (the "can't type in the new-post box" bug). Mirrors the profile call site.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      // Light scrim so the feed (founder photo) stays visible behind the
      // composer; the default black54 dim hid it almost entirely.
      barrierColor: Colors.black.withOpacity(0.12),
      builder: (_) => CreatePostSheet(
        onCreated: () async {
          // Small delay so Postgres commits before we re-fetch
          await Future.delayed(const Duration(milliseconds: 400));
          ref.invalidate(postsProvider);
          ref.invalidate(feedProvider);
        },
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onCreatePost});
  final VoidCallback onCreatePost;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    // No colored bar: the wordmark + "Scrivi" button float over the normal
    // paper background, so the status-bar icons must be DARK (matching the
    // global default set in main.dart) to stay visible.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light, // iOS: light bg → dark icons
        statusBarIconBrightness: Brightness.dark, // Android
      ),
      child: Padding(
        // Keep the top SafeArea inset so the title never overlaps the notch.
        padding: EdgeInsets.fromLTRB(20, top + 16, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Wordmark + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scripta',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: ScriptaColors.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.homeFeedSubtitle,
                    style: GoogleFonts.manrope(
                      color: ScriptaColors.inkMuted,
                      fontSize: 12,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),

            // Create-post button
            GestureDetector(
              // Without this the GestureDetector only hit-tests the painted
              // icon/text glyphs (a DecoratedBox doesn't absorb hits on its
              // padding), so taps on the button's padding did nothing — this is
              // why "non si riesce a cliccare per scrivere un post". Opaque makes
              // the whole pill tappable.
              behavior: HitTestBehavior.opaque,
              onTap: onCreatePost,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: ScriptaColors.siennaFaint,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: ScriptaColors.sienna.withAlpha(60),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_outlined,
                        size: 15, color: ScriptaColors.primaryDark),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.commonScrivi,
                      style: const TextStyle(
                        color: ScriptaColors.primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
