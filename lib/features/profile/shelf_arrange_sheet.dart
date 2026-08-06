// ─── Arranging the shelf ─────────────────────────────────────────────────────
//
// Founder: "nella libreria sul profilo ci vuole un tastino che dia la
// possibilità di modificare l'ordine dei libri o manualmente o secondo filtri
// … la disposizione scelta deve essere poi visibile anche agli altri."
//
// So this sheet does two things that look like one: it picks an ORDER, and it
// publishes it. The choice lives in `user_shelf_layout`, which every signed-in
// reader can read, and both the owner's shelf and a visitor's view of it run the
// same `applyShelfOrder` — a shelf someone arranged is a small act of curation,
// and it would be a strange one if only they could see the result.
//
// Manual arranging is a drag-to-reorder LIST rather than dragging spines around
// the cabinet: a spine is 30 points wide and its neighbours re-flow between rows
// as it moves, which makes dropping one precisely a game rather than a tool.
// The list is unambiguous, and the shelf redraws underneath it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme.dart';
import '../library/book_cover.dart';
import '../library/bookshelf_view.dart';
import 'profile_shared_widgets.dart';

/// The arrangement a profile is currently showing, for [ownerUserId] (null =
/// the signed-in reader). Read by BOTH profiles.
final shelfLayoutProvider = FutureProvider.family
    .autoDispose<ShelfLayout, String?>((ref, ownerUserId) async {
  final svc = ref.watch(supabaseServiceProvider);
  final uid =
      (ownerUserId == null || ownerUserId.isEmpty) ? svc.userId : ownerUserId;
  if (uid == null || uid.isEmpty) return const ShelfLayout.fallback();
  final row = await svc.fetchShelfLayout(uid);
  return ShelfLayout(
    sort: shelfSortFromName(row['sort_mode'] as String?),
    manualOrder: [
      for (final k in (row['manual_order'] as List? ?? const []))
        k.toString(),
    ],
  );
});

class ShelfLayout {
  const ShelfLayout({required this.sort, required this.manualOrder});

  /// What an unarranged shelf shows: alphabetical, the order the server already
  /// sends. Chosen over "recent" so a shelf nobody touched still reads as tidy.
  const ShelfLayout.fallback()
      : sort = ShelfSort.title,
        manualOrder = const [];

  final ShelfSort sort;
  final List<String> manualOrder;
}

Future<void> showShelfArrangeSheet(
  BuildContext context, {
  required List<ShelfEntry> entries,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShelfArrangeSheet(entries: entries),
  );
}

class _ShelfArrangeSheet extends ConsumerStatefulWidget {
  const _ShelfArrangeSheet({required this.entries});

  final List<ShelfEntry> entries;

  @override
  ConsumerState<_ShelfArrangeSheet> createState() => _ShelfArrangeSheetState();
}

class _ShelfArrangeSheetState extends ConsumerState<_ShelfArrangeSheet> {
  ShelfSort _sort = ShelfSort.title;
  List<ShelfEntry> _manual = const [];
  bool _saving = false;
  bool _loaded = false;

  /// The list as it currently reads, so the preview and the drag list always
  /// agree with each other.
  List<ShelfEntry> get _arranged => _sort == ShelfSort.manual
      ? _manual
      : applyShelfOrder(widget.entries, _sort, const []);

  void _adopt(ShelfLayout layout) {
    if (_loaded) return;
    _loaded = true;
    _sort = layout.sort;
    // Only seed the hand-arranged list from a SAVED hand arrangement. Seeding it
    // eagerly would mean that picking "by colour" and then "by hand" throws the
    // colour order away and starts from alphabetical — the reader would be
    // hand-arranging a shelf they were not looking at.
    if (layout.sort == ShelfSort.manual) {
      _manual =
          applyShelfOrder(widget.entries, ShelfSort.manual, layout.manualOrder);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(supabaseServiceProvider).saveShelfLayout(
            sortMode: shelfSortName(_sort),
            // The manual order is written whatever the mode, so switching to a
            // filter and back does not throw away an arrangement someone spent
            // real time on.
            manualOrder: [
              for (final e in _manual.isEmpty ? _arranged : _manual)
                favCoverKey(e.title, e.author),
            ],
          );
      ref.invalidate(shelfLayoutProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.shelfArrangeError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(shelfLayoutProvider(null)).whenData(_adopt);

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: ScriptaColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ScriptaColors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.shelfArrangeTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ScriptaColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l10n.shelfArrangeSubtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.4,
                  color: ScriptaColors.inkMuted,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── The filters ──────────────────────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final s in ShelfSort.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SortChip(
                        label: _sortLabel(l10n, s),
                        selected: _sort == s,
                        onTap: () => setState(() {
                          if (s == ShelfSort.manual && _manual.isEmpty) {
                            // Start hand-arranging from what is on screen, so
                            // the first drag moves a book the reader can see.
                            _manual = [..._arranged];
                          }
                          _sort = s;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: _sort == ShelfSort.manual
                  ? _ManualList(
                      entries: _manual,
                      controller: controller,
                      onReorder: (from, to) => setState(() {
                        if (to > from) to -= 1;
                        _manual = [..._manual]..insert(to, _manual[from]);
                        _manual.removeAt(from > to ? from + 1 : from);
                      }),
                    )
                  : SingleChildScrollView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: BookshelfView(
                        entries: _arranged,
                        onTap: (_, __) {},
                      ),
                    ),
            ),

            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: ScriptaColors.primary,
                      foregroundColor: ScriptaColors.ink,
                      disabledBackgroundColor: ScriptaColors.primaryFaint,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _saving ? l10n.shelfArrangeSaving : l10n.shelfArrangeSave,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(dynamic l10n, ShelfSort s) => switch (s) {
        ShelfSort.title => l10n.shelfSortTitle as String,
        ShelfSort.author => l10n.shelfSortAuthor as String,
        ShelfSort.color => l10n.shelfSortColor as String,
        ShelfSort.mostHighlighted => l10n.shelfSortMarked as String,
        ShelfSort.recent => l10n.shelfSortRecent as String,
        ShelfSort.manual => l10n.shelfSortManual as String,
      };
}

class _SortChip extends StatelessWidget {
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? ScriptaColors.primary : ScriptaColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? ScriptaColors.primary : ScriptaColors.rule,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? ScriptaColors.ink : ScriptaColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Drag to arrange. Each row wears its own spine colour, so the list and the
/// cabinet are recognisably the same books.
class _ManualList extends StatelessWidget {
  const _ManualList({
    required this.entries,
    required this.controller,
    required this.onReorder,
  });

  final List<ShelfEntry> entries;
  final ScrollController controller;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      scrollController: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: entries.length,
      onReorder: onReorder,
      itemBuilder: (context, i) {
        final e = entries[i];
        final colors = bookColorsFor(e.title, e.author);
        return Padding(
          key: ValueKey('${e.title}|${e.author}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ScriptaColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ScriptaColors.ruleFaint),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.base,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ScriptaColors.ink,
                        ),
                      ),
                      Text(
                        e.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: ScriptaColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                // A real handle, not a picture of one: dragging it starts the
                // reorder immediately. Long-press still works on the rest of
                // the row, but an icon that looks grabbable has to BE grabbable
                // — otherwise the first drag just scrolls the list and the
                // feature reads as broken.
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Icon(Icons.drag_handle,
                        color: ScriptaColors.inkFaint, size: 20),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
