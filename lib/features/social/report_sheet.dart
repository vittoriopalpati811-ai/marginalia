// ─── Report reason-picker sheet (App Store Guideline 1.2) ────────────────────
//
// A shared, liquid-glass bottom sheet for reporting objectionable user content
// (posts, comments, messages, profiles, reviews, jams). Mirrors the
// `_PostMenuSheet` style in feed_tab.dart (ClipRRect r28, BackdropFilter blur
// 18, translucent surface, white hairline border, 36×4 handle).
//
// Usage:
//   final ok = await showReportSheet(
//     context, ref,
//     contentType: 'post',
//     contentId: post['id'] as String,
//     reportedUserId: post['user_id'] as String?,
//   );
//
// The user picks one predefined reason; on tap we immediately call
// `SupabaseService.reportContent` (rate-limited 20/day server-side), pop the
// sheet, and surface a localized confirmation / error SnackBar. Returns true
// only when the report was accepted by the backend.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';

/// A single predefined report reason: a stable, language-independent [slug]
/// stored server-side, plus a localized display [label].
class _ReportReason {
  const _ReportReason({required this.slug, required this.label, required this.icon});
  final String slug;
  final String label;
  final IconData icon;
}

/// Presents the reason-picker sheet for [contentType] / [contentId].
///
/// Returns `true` if a report was successfully submitted, `false` if the user
/// dismissed the sheet or the submission failed. Safe to call with a missing
/// [contentId] — it simply does nothing and returns false.
Future<bool> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String contentType,
  required String contentId,
  String? reportedUserId,
}) async {
  if (contentId.isEmpty) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(
      contentType: contentType,
      contentId: contentId,
      reportedUserId: reportedUserId,
    ),
  );
  return result ?? false;
}

/// Shows the localized "block this user?" confirmation dialog used across the
/// feed, chat and profile surfaces. Returns `true` only if the user confirms.
/// Kept here so every block entry point asks the same question the same way.
Future<bool> confirmBlockUser(BuildContext context) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(l10n.blockUserConfirmTitle,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(l10n.blockUserConfirmBody,
          style: const TextStyle(height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text(l10n.blockUserConfirmCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB54848)),
          onPressed: () => Navigator.pop(dialogCtx, true),
          child: Text(l10n.blockUserConfirmConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.contentType,
    required this.contentId,
    this.reportedUserId,
  });

  final String contentType;
  final String contentId;
  final String? reportedUserId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  bool _submitting = false;

  List<_ReportReason> _reasons(BuildContext context) {
    final l10n = context.l10n;
    // Slugs are intentionally English and stable so the moderation queue is
    // language-independent; only the labels are localized.
    return [
      _ReportReason(
          slug: 'spam', label: l10n.reportReasonSpam, icon: Icons.block_flipped),
      _ReportReason(
          slug: 'harassment',
          label: l10n.reportReasonHarassment,
          icon: Icons.sentiment_very_dissatisfied_outlined),
      _ReportReason(
          slug: 'hate', label: l10n.reportReasonHate, icon: Icons.report_gmailerrorred_outlined),
      _ReportReason(
          slug: 'sexual', label: l10n.reportReasonSexual, icon: Icons.no_adult_content),
      _ReportReason(
          slug: 'violence',
          label: l10n.reportReasonViolence,
          icon: Icons.warning_amber_outlined),
      _ReportReason(
          slug: 'misinformation',
          label: l10n.reportReasonMisinformation,
          icon: Icons.fact_check_outlined),
      _ReportReason(
          slug: 'other', label: l10n.reportReasonOther, icon: Icons.more_horiz),
    ];
  }

  Future<void> _submit(String slug) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    // Capture before any await — popping the sheet deactivates this context.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final svc = ref.read(supabaseServiceProvider);

    try {
      await svc.reportContent(
        contentType: widget.contentType,
        contentId: widget.contentId,
        reportedUserId: widget.reportedUserId,
        reason: slug,
      );
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.reportSuccess)),
      );
    } catch (e) {
      navigator.pop(false);
      final isRateLimit = _looksLikeRateLimit(e);
      messenger.showSnackBar(
        SnackBar(
          content: Text(isRateLimit ? l10n.reportRateLimited : l10n.reportError),
        ),
      );
    }
  }

  // The report_content RPC raises when the caller exceeds 20 reports/day. We
  // can't rely on a typed error, so sniff the message for the usual markers.
  bool _looksLikeRateLimit(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('rate') ||
        msg.contains('limit') ||
        msg.contains('too many') ||
        msg.contains('429');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final reasons = _reasons(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: ScriptaColors.surface.withAlpha(225),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withAlpha(46), width: 0.6),
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ScriptaColors.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined,
                          size: 18, color: ScriptaColors.inkMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.l10n.reportSheetTitle,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ScriptaColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (_submitting)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: ScriptaColors.sienna,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(
                    color: ScriptaColors.ruleFaint, height: 1, thickness: 1),
                ...reasons.map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _submitting ? null : () => _submit(r.slug),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          child: Row(
                            children: [
                              Icon(r.icon,
                                  size: 19, color: ScriptaColors.inkMuted),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  r.label,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color: ScriptaColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
