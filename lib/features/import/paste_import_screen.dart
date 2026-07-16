// ─── Paste-import screen ─────────────────────────────────────────────────────
//
// Lets the user IMPORT highlights by pasting text, not just by picking a file.
// This is the path for people whose highlights don't come as a tidy file:
//   • Apple Books — select a highlight, Copy, paste here (title/author are read
//     from the "Excerpt From …" attribution automatically);
//   • a notes app, an email-to-self, or any plain list of quotes — filed under
//     the optional book title/author typed above the box.
//
// All the heavy lifting is shared: synthesizeClippingsFromPaste() turns the
// paste into canonical "My Clippings.txt", which flows through the exact same
// ImportService.importClippingsText pipeline the file importer uses (dedup,
// stable ids, Supabase upsert). Reached from Settings → "Paste highlights".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/parser/paste_parser.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/providers/isar_provider.dart';
import '../../core/services/import_service.dart';
import '../../core/theme.dart';

class PasteImportScreen extends ConsumerStatefulWidget {
  const PasteImportScreen({super.key});

  @override
  ConsumerState<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _PasteImportScreenState extends ConsumerState<PasteImportScreen> {
  final _textCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  bool _importing = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return;
    setState(() {
      // Append rather than overwrite so a second paste adds more highlights.
      final existing = _textCtrl.text.trimRight();
      _textCtrl.text = existing.isEmpty ? text : '$existing\n\n$text';
      _textCtrl.selection =
          TextSelection.collapsed(offset: _textCtrl.text.length);
    });
  }

  Future<void> _import() async {
    final raw = _textCtrl.text;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final clippings = synthesizeClippingsFromPaste(
      raw,
      fallbackTitle: _titleCtrl.text,
      fallbackAuthor: _authorCtrl.text,
    );
    if (clippings.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importPasteEmpty)),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final userId = ref.read(currentUserProvider)?.id ?? 'local';
      final isar = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final result = await service.importClippingsText(clippings);

      // Best-effort: re-derive reading sessions so stats reflect the new
      // highlights. Never blocks the import result.
      try {
        await supabase.inferReadingSessionsFromHighlights();
      } catch (_) {}

      ref.invalidate(allHighlightsProvider);
      ref.invalidate(booksProvider);

      if (!mounted) return;
      // gen-l10n orders the generated params ALPHABETICALLY: (books, highlights).
      final msg = result.highlightsAdded > 0
          ? l10n.importSuccess(result.booksAdded, result.highlightsAdded)
          : l10n.libraryImportNone(result.highlightsDeduplicated);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.importErrorGeneric(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: ScriptaColors.background,
      appBar: AppBar(
        backgroundColor: ScriptaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ScriptaColors.ink,
        title: Text(
          l10n.importPasteTitle,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ScriptaColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _ExplainCard(text: l10n.importPasteExplain),
            const SizedBox(height: 20),
            _FieldLabel(l10n.importPasteBookTitleLabel),
            const SizedBox(height: 6),
            _MiniField(
              controller: _titleCtrl,
              hint: l10n.importPasteBookTitleHint,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            _FieldLabel(l10n.importPasteBookAuthorLabel),
            const SizedBox(height: 6),
            _MiniField(
              controller: _authorCtrl,
              hint: l10n.importPasteBookAuthorHint,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _FieldLabel(l10n.importPasteTextLabel),
                const Spacer(),
                TextButton.icon(
                  onPressed: _importing ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: Text(l10n.importPasteFromClipboard),
                  style: TextButton.styleFrom(
                    foregroundColor: ScriptaColors.primaryDark,
                    textStyle: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _textCtrl,
              minLines: 8,
              maxLines: 20,
              enabled: !_importing,
              style: GoogleFonts.manrope(
                  fontSize: 15, color: ScriptaColors.ink, height: 1.5),
              decoration: InputDecoration(
                hintText: l10n.importPasteTextHint,
                hintStyle: GoogleFonts.manrope(
                    fontSize: 15, color: ScriptaColors.inkFaint),
                filled: true,
                fillColor: ScriptaColors.surfaceElevated,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                      color: ScriptaColors.primaryDark, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _importing ? null : _import,
                style: FilledButton.styleFrom(
                  backgroundColor: ScriptaColors.primaryDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _importing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Text(
                        l10n.importPasteAction,
                        style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplainCard extends StatelessWidget {
  const _ExplainCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ScriptaColors.primaryFaint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_stories_outlined,
              color: ScriptaColors.primaryDark, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.5,
                color: ScriptaColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: ScriptaColors.ink,
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({
    required this.controller,
    required this.hint,
    this.textInputAction,
  });
  final TextEditingController controller;
  final String hint;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: textInputAction,
      style: GoogleFonts.manrope(fontSize: 15, color: ScriptaColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.manrope(fontSize: 15, color: ScriptaColors.inkFaint),
        filled: true,
        fillColor: ScriptaColors.surfaceElevated,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: ScriptaColors.primaryDark, width: 1.5),
        ),
      ),
    );
  }
}
