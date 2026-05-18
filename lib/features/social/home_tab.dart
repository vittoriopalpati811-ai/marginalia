import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import 'feed_tab.dart';

// ─── HomeTab ──────────────────────────────────────────────────────────────────
//
// The first tab in the bottom nav: house icon, no label.
// Renders a gradient header with "Marginalia" logo + create-post button,
// then the full FeedTab content below.

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: Column(
        children: [
          _HomeHeader(
            onCreatePost: () => _openCreatePost(context, ref),
          ),
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
        onCreated: () => ref.invalidate(postsProvider),
      ),
    );
  }
}

// ─── Home header ─────────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onCreatePost});
  final VoidCallback onCreatePost;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Container(
      decoration: MarginaliaDecorations.gradientHeader,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 16, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Logo / title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Marginalia',
                    style: GoogleFonts.lora(
                      color: const Color(0xFFF1EEE7),
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Il tuo feed di lettura',
                    style: TextStyle(
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EEE7).withAlpha(28),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFF1EEE7).withAlpha(50),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 15, color: Color(0xFFF1EEE7)),
                    SizedBox(width: 6),
                    Text(
                      'Scrivi',
                      style: TextStyle(
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
    );
  }
}

// _CreatePostSheet removed — HomeTab now uses the public CreatePostSheet
// from feed_tab.dart (which also supports image attachment).
