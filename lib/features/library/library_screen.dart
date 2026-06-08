import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/models/book.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/services/import_service.dart';
import '../../core/providers/isar_provider.dart';
import 'book_cover.dart';
import 'recommendations_section.dart';
import '../review/review_entry_card.dart';
import '../../core/providers/daily_highlight_provider.dart';
import '../../core/providers/daily_subtitle_provider.dart';
import '../stats/stats_screen.dart'
    show readingSessionsProvider, readingGoalProvider;

// ─── Filter state ─────────────────────────────────────────────────────────────

enum _LibraryFilter { all, favorites }

final _libraryFilterProvider =
    StateProvider<_LibraryFilter>((ref) => _LibraryFilter.all);

// ─── Screen ───────────────────────────────────────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isImporting  = false;
  bool _showAllBooks = false; // toggles the "La tua libreria" grid

  @override
  Widget build(BuildContext context) {
    final booksAsync        = ref.watch(booksProvider);
    final allHighlightsAsync = ref.watch(allHighlightsProvider);
    final filter            = ref.watch(_libraryFilterProvider);
    final randomAsync       = ref.watch(dailyHighlightProvider);
    // "Why this phrase is for you" line — null off-iOS or with no context.
    final subtitle          = ref.watch(dailySubtitleProvider);

    // Apply filter
    final filteredBooksAsync = booksAsync.whenData((books) {
      if (filter == _LibraryFilter.favorites) {
        final favBookIds = allHighlightsAsync.maybeWhen(
          data: (hl) =>
              hl.where((h) => h.isFavorite).map((h) => h.bookId).toSet(),
          orElse: () => <int>{},
        );
        return books.where((b) => favBookIds.contains(b.id)).toList();
      }
      return books;
    });

    // Derive display list: max 3 when collapsed, all when expanded
    final allBooks     = filteredBooksAsync.value;
    final hasMoreBooks = (allBooks?.length ?? 0) > 3;
    final displayBooks = allBooks == null
        ? <Book>[]
        : (_showAllBooks ? allBooks : allBooks.take(3).toList());

    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      body: RefreshIndicator(
        onRefresh: () async => _refreshLibrary(),
        color: MarginaliaColors.primaryDark,
        backgroundColor: MarginaliaColors.surfaceElevated,
        displacement: 60,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header editoriale ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: _EditorialHeader(
                isImporting:    _isImporting,
                onImport:       _pickAndImportFile,
                onForceReimport: () => _pickAndImportFile(forceClean: true),
                userName: ref.watch(myDisplayNameProvider).asData?.value,
              ),
            ),

            // ── Ripasso del giorno — daily recall entry point ──────────────
            // The first action of the day: a warm card with the due count +
            // streak flame. Hidden when nothing is due and unreviewed; collapses
            // to a quiet "done" pill once today's session is complete.
            const SliverToBoxAdapter(child: RipassoEntryCard()),

            // ── Hero pull-quote: highlight del giorno ──────────────────────
            randomAsync.when(
              data: (h) => h != null
                  ? SliverToBoxAdapter(
                      child: _DailyCard(
                        content: h.content,
                        subtitle: subtitle,
                        onTap: () => context.push('/highlight/${h.id}'),
                      )
                          .animate()
                          .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                          .slideY(begin: 0.05, end: 0, duration: 500.ms),
                    )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── Strip highlights recenti ───────────────────────────────────
            allHighlightsAsync.when(
              data: (highlights) {
                if (highlights.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: _RecentHighlightsStrip(
                    highlights: highlights.take(8).toList(),
                    onTap: (h) => context.push('/highlight/${h.id}'),
                  ),
                );
              },
              loading: () =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── Filter chips (Airbnb-clean: no section header here, the
            //    screen-level hero title above already announces this) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _FilterChips(
                  selected: filter,
                  onSelect: (f) =>
                      ref.read(_libraryFilterProvider.notifier).state = f,
                ),
              ),
            ),

            // ── Book grid (max 3 when collapsed) ──────────────────────────
            if (allBooks == null)
              // Loading
              const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(
                      color: MarginaliaColors.primaryDark,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
              )
            else if (allBooks.isEmpty)
              SliverFillRemaining(
                child: _EmptyLibrary(
                  onImport: _pickAndImportFile,
                  onDemo:   _loadDemoData,
                  isFiltered: filter != _LibraryFilter.all,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _BookGridCard(
                      book:  displayBooks[i],
                      index: i,
                      onTap: () => context.push('/book/${displayBooks[i].id}'),
                    ),
                    childCount: displayBooks.length,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing:  12,
                    childAspectRatio: 0.72,
                  ),
                ),
              ),

            // ── "Vedi tutti / Nascondi" button ────────────────────────────
            if (allBooks != null && allBooks.isNotEmpty && hasMoreBooks)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showAllBooks = !_showAllBooks),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: MarginaliaColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MarginaliaColors.rule,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showAllBooks
                                ? context.l10n.libraryHide
                                : context.l10n.libraryViewAll(allBooks.length),
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: MarginaliaColors.primaryDark,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _showAllBooks
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: MarginaliaColors.primaryDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Libri consigliati ─────────────────────────────────────────
            const SliverToBoxAdapter(
              child: LibraryRecommendationsSection(),
            ),

            // ── Bottom padding for nav bar ─────────────────────────────────
            // Bottom safety padding (nav bar is now solid, not floating)
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  // ─── Encoding ────────────────────────────────────────────────────────────────

  String _decodeClippings(Uint8List bytes) {
    var data = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      data = bytes.sublist(3);
    }
    try {
      return utf8.decode(data);
    } catch (_) {}
    return latin1.decode(data);
  }

  // ─── Auth guard ─────────────────────────────────────────────────────────────

  bool _requireAuth() {
    final supabase = ref.read(supabaseServiceProvider);
    if (!supabase.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.librarySignInToImport),
          action: SnackBarAction(
            label: context.l10n.librarySignIn,
            textColor: Colors.white,
            onPressed: () => context.push('/auth'),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  // ─── Import da file picker ───────────────────────────────────────────────────

  Future<void> _pickAndImportFile({bool forceClean = false}) async {
    if (!_requireAuth()) return;

    if (forceClean) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MarginaliaColors.surfaceElevated,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text(context.l10n.libraryClearReimportTitle,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          content: Text(
            context.l10n.libraryClearReimportBody,
            style: const TextStyle(
                color: MarginaliaColors.inkMuted,
                fontSize: 14,
                height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB54848)),
              child: Text(context.l10n.libraryClearAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    var rawText = _decodeClippings(file.bytes!);
    setState(() => _isImporting = true);

    if (forceClean) {
      try {
        await ref.read(supabaseServiceProvider).deleteAllUserData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
        }
        setState(() => _isImporting = false);
        return;
      }
    }

    try {
      final userId  = ref.read(currentUserProvider)?.id ?? 'local';
      final isar    = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final importResult = await service.importClippingsText(rawText);
      // After the highlights land, ask the server to re-derive reading
      // sessions from them (one session per book per day, minutes
      // estimated from highlight count). Non-blocking: if it fails,
      // manual sessions still work and we just don't auto-populate the
      // stats this round.
      await supabase.inferReadingSessionsFromHighlights();
      _invalidateAfterImport();

      if (mounted) {
        final msg = importResult.firstError != null
            ? context.l10n.libraryImportPartial(
                importResult.highlightsAdded, importResult.highlightsFailed)
            : importResult.highlightsAdded > 0
                ? context.l10n.libraryImportSuccess(
                    importResult.highlightsAdded, importResult.booksAdded)
                : context.l10n.libraryImportNone(
                    importResult.highlightsDeduplicated);
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: Duration(
                seconds: importResult.firstError != null ? 15 : 4),
          ),
        );
        // If new highlights actually landed, queue a second snackbar telling
        // the user the AI is regenerating their recs. The library
        // recommendations provider was already invalidated above by
        // `_invalidateAfterImport()`, so the next paint shows the
        // "Marginalia is analyzing your highlights…" skeleton automatically.
        if (importResult.highlightsAdded > 0) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text(context.l10n.libraryImportRecsHint),
                duration: const Duration(seconds: 4),
                backgroundColor: MarginaliaColors.primary,
              ),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.libraryImportError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Full refresh after a real My Clippings import — also busts the
  /// recommendations cache so the AI re-analyzes the new highlights,
  /// AND the reading-sessions cache so the stats card refreshes with
  /// the freshly-inferred sessions.
  void _invalidateAfterImport() {
    ref.invalidate(booksProvider);
    ref.invalidate(dailyHighlightProvider);
    ref.invalidate(allHighlightsProvider);
    ref.invalidate(libraryRecommendationsProvider);
    ref.invalidate(readingSessionsProvider);
    ref.invalidate(readingGoalProvider);
  }

  /// Pull-to-refresh: refresh books/highlights data only.
  /// Recommendations are NOT invalidated — they only update after a real import.
  /// The daily phrase is intentionally NOT invalidated: it must stay stable for
  /// its 3-hour window regardless of how often the user swipes to refresh.
  /// (Even if it were re-run, the 3h cache returns the same pick.)
  void _refreshLibrary() {
    ref.invalidate(booksProvider);
    ref.invalidate(allHighlightsProvider);
  }

  // ─── Demo data ───────────────────────────────────────────────────────────────

  Future<void> _loadDemoData() async {
    if (!_requireAuth()) return;
    setState(() => _isImporting = true);
    try {
      var rawText =
          await rootBundle.loadString('assets/demo/My Clippings.txt');
      if (rawText.startsWith('﻿')) rawText = rawText.substring(1);

      final userId  = ref.read(currentUserProvider)?.id ?? 'local';
      final isar    = ref.read(isarProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final service = ImportService(isar, userId, supabaseService: supabase);
      final result  = await service.importClippingsText(rawText);
      await supabase.inferReadingSessionsFromHighlights();
      _invalidateAfterImport();
      if (mounted) {
        final msg = result.firstError != null
            ? context.l10n.libraryImportPartial(
                result.highlightsAdded, result.highlightsFailed)
            : result.highlightsAdded > 0
                ? context.l10n.libraryImportSuccess(
                    result.highlightsAdded, result.booksAdded)
                : context.l10n.libraryImportNone(
                    result.highlightsDeduplicated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration:
                Duration(seconds: result.firstError != null ? 15 : 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix('$e'))));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

// myDisplayNameProvider lives in auth_provider.dart (shared with other screens)

// ─── Greeting phrases ─────────────────────────────────────────────────────────

/// The editorial line at the very top of the Library — a curated, literary
/// greeting that welcomes the reader back to their highlights.
///
/// Each phrase ships in two grammatical forms so the result always reads
/// naturally and is never assembled by gluing fragments together (which is how
/// the old code produced the cacophonous "Così presto!, Vittorio?"):
///   • [_Greeting.plain] — used when we don't know the reader's name.
///   • [_Greeting.named] — used when we do; it contains a single `{name}`
///     slot placed where Italian wants the vocative, with its own punctuation.
///
/// A phrase whose `named` form is empty simply never addresses the reader by
/// name (e.g. "Le tue pagine ti aspettavano."), keeping the mix varied.
class _LibraryGreetings {
  const _LibraryGreetings._();

  /// Returns the greeting for the current day. The pick is stable across
  /// rebuilds (it only changes by calendar day), so the header doesn't flicker
  /// while the reader scrolls — the daily ritual stays put, like the pull-quote.
  static String forToday(String? userName) {
    final name = userName?.trim() ?? '';
    final now = DateTime.now();
    // Day-of-year as a stable rotation index.
    final dayOfYear =
        now.difference(DateTime(now.year)).inDays; // 0-based, stable per day.
    final phrase = _phrases[dayOfYear % _phrases.length];
    if (name.isEmpty || phrase.named.isEmpty) return phrase.plain;
    return phrase.named.replaceAll('{name}', name);
  }

  /// Curated, non-generic set. Warm, a little witty, literary, and contextual
  /// to a reading app — coming back to your books, re-opening your highlights,
  /// the quiet ritual of reading. Deliberately avoids bland filler.
  static const List<_Greeting> _phrases = [
    // ── Reworked from the old time-of-day lines (clean punctuation) ──────────
    _Greeting('Così presto?', 'Così presto, {name}?'),
    _Greeting('Già di ritorno?', 'Già di ritorno, {name}?'),
    _Greeting('Bentornato tra le righe.', 'Bentornato tra le righe, {name}.'),
    // ── New literary greetings ──────────────────────────────────────────────
    _Greeting('Le tue pagine ti aspettavano.', 'Le tue pagine ti aspettavano, {name}.'),
    _Greeting('Di nuovo qui, tra le righe?', 'Di nuovo qui tra le righe, {name}?'),
    _Greeting('Ben tornato dove eri rimasto.', 'Ben tornato dove eri rimasto, {name}.'),
    _Greeting('Qualcosa da rileggere, oggi?', 'Qualcosa da rileggere oggi, {name}?'),
    _Greeting('I tuoi passaggi preferiti, di nuovo.', 'I tuoi passaggi preferiti, {name}.'),
    _Greeting('Riprendiamo da dove eravamo?', 'Riprendiamo da dove eravamo, {name}?'),
    _Greeting('Le parole che hai sottolineato sono ancora qui.', ''),
    _Greeting('Un altro giro fra i tuoi appunti?', 'Un altro giro fra i tuoi appunti, {name}?'),
    _Greeting('Si torna sempre ai buoni libri.', 'Si torna sempre ai buoni libri, vero {name}?'),
    _Greeting('Le righe migliori ti hanno aspettato.', 'Le righe migliori ti hanno aspettato, {name}.'),
    _Greeting('Pronto a rileggere te stesso?', 'Pronto a rileggere te stesso, {name}?'),
    _Greeting('Ogni ritorno è una nuova lettura.', 'Ogni tuo ritorno è una nuova lettura, {name}.'),
    _Greeting('I margini si ricordano di te.', 'I margini si ricordano di te, {name}.'),
    _Greeting('Cosa avevi sottolineato, l’ultima volta?', 'Cosa avevi sottolineato, {name}?'),
    _Greeting('Un pensiero, prima di ripartire?', 'Un pensiero prima di ripartire, {name}?'),
    _Greeting('Le tue letture non vedevano l’ora.', 'Le tue letture non vedevano l’ora, {name}.'),
    _Greeting('Torna a trovare le parole che ami.', 'Le parole che ami sono qui, {name}.'),
    _Greeting('Ben ritrovato fra le tue pagine.', 'Ben ritrovato fra le tue pagine, {name}.'),
    _Greeting('Qualche riga ti stava cercando.', 'Qualche riga ti stava cercando, {name}.'),
    _Greeting('Si ricomincia da un sottolineato?', 'Si ricomincia da un sottolineato, {name}?'),
    _Greeting('La tua biblioteca ti ha tenuto il posto.', 'La tua biblioteca ti ha tenuto il posto, {name}.'),
    _Greeting('Rieccoti dove le storie ti aspettano.', 'Rieccoti, {name}, dove le storie ti aspettano.'),
    _Greeting('Hai lasciato una frase a metà, ieri.', 'Avevi lasciato una frase a metà, {name}.'),
  ];
}

/// A single greeting in two forms. [named] may be empty, meaning the phrase is
/// never personalised with the reader's name.
class _Greeting {
  const _Greeting(this.plain, this.named);

  /// Used when the reader's name is unknown — complete and self-contained.
  final String plain;

  /// Used when the name is known. Contains exactly one `{name}` slot, or is
  /// empty to opt out of personalisation.
  final String named;
}

// ─── Header editoriale ────────────────────────────────────────────────────────

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader({
    required this.isImporting,
    required this.onImport,
    required this.onForceReimport,
    this.userName,
  });

  final bool isImporting;
  final VoidCallback onImport;
  final VoidCallback onForceReimport;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    // Editorial greeting line — a curated, literary phrase that composes
    // cleanly with the reader's name. See [_LibraryGreetings] for the full
    // set and the templating rules (each phrase carries its own punctuation,
    // so we never glue "!," together).
    final greeting = _LibraryGreetings.forToday(userName);

    // Airbnb-clean header: small caption above + huge bold title below.
    // The greeting is the eyebrow ("Buongiorno, Vittorio"), the title is
    // the screen subject ("La tua libreria"). No divider — whitespace
    // does the separating instead.
    return Padding(
      padding: EdgeInsets.fromLTRB(24, top + 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow / greeting
          Row(
            children: [
              Expanded(
                child: Text(
                  greeting,
                  style: MarginaliaTextStyles.subtitle.copyWith(
                    fontSize: 13,
                    color: MarginaliaColors.inkMuted,
                  ),
                ),
              ),
              if (isImporting)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: MarginaliaColors.primaryDark,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onLongPress: onForceReimport,
                  child: IconButton(
                    icon: const Icon(Icons.add_rounded),
                    color: MarginaliaColors.ink,
                    iconSize: 24,
                    splashRadius: 22,
                    tooltip: context.l10n.libraryImportTooltip,
                    onPressed: onImport,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Hero title — Airbnb-spec 28pt bold
          Text(
            context.l10n.libraryTitle,
            style: MarginaliaTextStyles.heroTitle,
          ),
        ],
      ),
    );
  }
}

// ─── Hero pull-quote: highlight del giorno ───────────────────────────────────

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.content,
    required this.onTap,
    this.subtitle,
  });

  final String content;
  final VoidCallback onTap;

  /// Optional "why this phrase is for you" line, woven from on-device context
  /// (steps, today's workout, cycle, calendar). Null off-iOS or when there are
  /// no signals — in which case nothing is rendered.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text =
        content.length > 260 ? '${content.substring(0, 260)}…' : content;

    // Airbnb-clean daily card: section eyebrow over a quiet-card with
    // a generous quote area. No dividers — whitespace and shadow only.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section eyebrow (small caps, light)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              context.l10n.libraryPickedForYou,
              style: MarginaliaTextStyles.sectionTitle,
            ),
          ),
          PressableSpring(
            onPressed: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: MarginaliaDecorations.quietCard(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"',
                    style: MarginaliaTextStyles.quoteDecor.copyWith(
                      fontSize: 56,
                      height: 0.5,
                      color: MarginaliaColors.siennaFaint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text,
                    style: MarginaliaTextStyles.highlightBody.copyWith(
                      fontSize: 18,
                      height: 1.65,
                      color: MarginaliaColors.ink,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      style: MarginaliaTextStyles.subtitle.copyWith(
                        fontSize: 12,
                        height: 1.4,
                        color: MarginaliaColors.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        context.l10n.libraryRead,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MarginaliaColors.primaryDark,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: MarginaliaColors.primaryDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Strip highlights recenti ─────────────────────────────────────────────────

class _RecentHighlightsStrip extends StatelessWidget {
  const _RecentHighlightsStrip({
    required this.highlights,
    required this.onTap,
  });

  final List<Highlight> highlights;
  final ValueChanged<Highlight> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 20, 12),
          child: Text(
            context.l10n.libraryRecent,
            style: MarginaliaTextStyles.sectionTitle,
          ),
        ),
        SizedBox(
          height: 136,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 16),
            itemCount: highlights.length,
            itemBuilder: (ctx, i) {
              final h           = highlights[i];
              final accentColor = _accentFor(h.color);
              return PressableSpring(
                onPressed: () => onTap(h),
                child: Container(
                  width: 240,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: MarginaliaDecorations.quietCard(radius: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((h.bookTitle ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Text(
                                    h.bookTitle!.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MarginaliaTextStyles.bookAuthor
                                        .copyWith(
                                      fontSize: 9,
                                      color: MarginaliaColors.inkFaint,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 7),
                              Expanded(
                                child: Text(
                                  h.content,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: _QuoteStyle.strip,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  .animate(delay: (i * 50).ms)
                  .fadeIn(duration: 300.ms)
                  .slideX(begin: 0.04, end: 0, duration: 300.ms);
            },
          ),
        ),
      ],
    );
  }

  Color _accentFor(String? color) => switch (color) {
        'yellow' => const Color(0xFFD4A017),
        'blue'   => const Color(0xFF4A90BF),
        'pink'   => const Color(0xFFBF4A72),
        'orange' => const Color(0xFFBF7A34),
        _        => MarginaliaColors.siennaLight,
      };
}

class _QuoteStyle {
  static final strip = MarginaliaTextStyles.highlightBodySmall.copyWith(
    fontSize: 13,
    height: 1.6,
  );
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final _LibraryFilter selected;
  final ValueChanged<_LibraryFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label:  context.l10n.libraryFilterAll,
          icon:   Icons.auto_stories_outlined,
          active: selected == _LibraryFilter.all,
          onTap:  () => onSelect(_LibraryFilter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label:  context.l10n.libraryFilterFavorites,
          icon:   Icons.bookmark_outline,
          active: selected == _LibraryFilter.favorites,
          onTap:  () => onSelect(_LibraryFilter.favorites),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String   label;
  final IconData icon;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? MarginaliaColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                active ? MarginaliaColors.primary : MarginaliaColors.rule,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active
                  ? const Color(0xFFF1EEE7)
                  : MarginaliaColors.inkMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: MarginaliaTextStyles.sectionTitle.copyWith(
                color: active
                    ? const Color(0xFFF1EEE7)
                    : MarginaliaColors.inkMuted,
                letterSpacing: 1.5,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Book grid card ───────────────────────────────────────────────────────────

class _BookGridCard extends StatelessWidget {
  const _BookGridCard({
    required this.book,
    required this.index,
    required this.onTap,
  });

  final Book       book;
  final int        index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // PressableSpring → Airbnb-style press feedback (scale + spring restore).
    // Hero → shared-element transition: the cover animates from this grid
    // cell to the same Hero tag in BookDetailScreen.
    // StaggeredListItem → cascade entrance (fade + slight slide-up).
    final card = PressableSpring(
      onPressed: onTap,
      child: Container(
        decoration: MarginaliaDecorations.quietCard(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 63,
              child: Hero(
                tag: 'book-cover-${book.id}',
                flightShuttleBuilder: (_, animation, __, ___, ____) =>
                    FadeTransition(
                  opacity: CurvedAnimation(
                      parent: animation, curve: AirbnbMotion.enter),
                  child: BookEditorialCover(
                    title: book.title,
                    author: book.author,
                  ),
                ),
                child: BookEditorialCover(
                  title: book.title,
                  author: book.author,
                  borderRadius: const BorderRadius.only(
                    topLeft:  Radius.circular(15),
                    topRight: Radius.circular(15),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookTitle.copyWith(
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      book.author.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MarginaliaTextStyles.bookAuthor.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.6,
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
    return StaggeredListItem(index: index, child: card);
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.onImport,
    required this.onDemo,
    this.isFiltered = false,
  });

  final VoidCallback onImport;
  final VoidCallback onDemo;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MarginaliaColors.siennaFaint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                size: 32,
                color: MarginaliaColors.primaryDark,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isFiltered
                  ? context.l10n.libraryNoFavorites
                  : context.l10n.libraryNoBooks,
              style:
                  MarginaliaTextStyles.bookTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              isFiltered
                  ? context.l10n.libraryNoFavoritesBody
                  : context.l10n.libraryNoBooksBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MarginaliaColors.inkMuted,
                height: 1.6,
                fontSize: 14,
              ),
            ),
            if (!isFiltered) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(context.l10n.libraryImportClippings),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onDemo,
                icon: Icon(Icons.auto_awesome_outlined,
                    size: 16,
                    color: MarginaliaColors.primaryDark),
                label: Text(
                  context.l10n.libraryTryDemo,
                  style: const TextStyle(
                      color: MarginaliaColors.primaryDark),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Recommendations section → see recommendations_section.dart ──────────────
