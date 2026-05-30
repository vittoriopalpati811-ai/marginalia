// ─── HomeTab ──────────────────────────────────────────────────────────────────
//
// First tab — social feed.
// Gradient header with wordmark + "Scrivi" button, then the full FeedTab.

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
      backgroundColor: MarginaliaColors.background,
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
      backgroundColor: Colors.transparent,
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: MarginaliaDecorations.lightStatusBar,
      child: Container(
      decoration: MarginaliaDecorations.gradientHeader,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 16, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Wordmark + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Marginalia', style: MarginaliaTextStyles.wordmarkLight),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.homeFeedSubtitle,
                    style: GoogleFonts.manrope(
                      color: const Color(0xFFF1EEE7).withAlpha(140),
                      fontSize: 12,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),

            // Create-post button
            GestureDetector(
              onTap: onCreatePost,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EEE7).withAlpha(28),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFF1EEE7).withAlpha(50),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_outlined,
                        size: 15, color: Color(0xFFF1EEE7)),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.commonScrivi,
                      style: const TextStyle(
                        color: Color(0xFFF1EEE7),
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
      ),
    );
  }
}
