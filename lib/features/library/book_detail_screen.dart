import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import '../../core/utils/share_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/motion/airbnb_motion.dart';
import '../../core/models/book.dart';
import '../../core/models/highlight.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/books_provider.dart';
import '../profile/profile_shared_widgets.dart' show favCoversProvider;
import '../../core/l10n/l10n_extension.dart';
import 'book_cover.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookByIdProvider(bookId));
    final highlightsAsync = ref.watch(highlightsByBookProvider(bookId));

    return bookAsync.when(
      data: (book) {
        if (book == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(context.l10n.bookNotFound,
                  style: const TextStyle(color: ScriptaColors.inkMuted)),
            ),
          );
        }

        final coverColor = ScriptaDecorations.bookCoverColor(book.title);

        final highlightCount = highlightsAsync.maybeWhen(
          data: (h) => h.length,
          orElse: () => 0,
        );

        return Scaffold(
          backgroundColor: ScriptaColors.background,
          body: Stack(
            children: [
              // ── Editorial hero cover ──────────────────────────────────────
              // Hero tag must match the BookGridCard in library_screen.dart
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                // Extend the cover well below the sheet's top so the coloured
                // artwork continues *behind* the white panel — its rounded top
                // then reads as overlapping the colour of the cover.
                height: 440,
                child: Hero(
                  tag: 'book-cover-${book.id}',
                  // Same flight treatment as the recommendation cover: a soft
                  // cross-fade of a rounded cover. Without a destination shuttle
                  // the grid card's plain (square-cornered) shuttle was flown
                  // into this unclipped band, so the morph read harder than the
                  // recommendations' rounded scale. Matching the shuttle here
                  // makes the open/close animation feel identical.
                  flightShuttleBuilder: (_, animation, __, ___, ____) =>
                      FadeTransition(
                    opacity: CurvedAnimation(
                        parent: animation, curve: AirbnbMotion.enter),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15),
                      ),
                      child: BookEditorialCover(
                        title: book.title,
                        author: book.author,
                        coverUrl: book.coverUrl,
                      ),
                    ),
                  ),
                  child: BookEditorialCover(
                    title: book.title,
                    author: book.author,
                    coverUrl: book.coverUrl,
                  ),
                ),
              ),

              // ── Cover edit (matitina) ─────────────────────────────────────
              // A small frosted pencil on the cover: pick a photo, search Google
              // for one, or remove a custom cover. Sits clear of the back button.
              Positioned(
                top: MediaQuery.of(context).padding.top + 6,
                right: 12,
                child: _CoverEditButton(
                  onTap: () => editBookCover(context, ref, book),
                ),
              ),

              // ── Panel sovrapposto (stile CourseInfoScreen) ────────────────
              Positioned.fill(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.62,
                  minChildSize: 0.62,
                  maxChildSize: 1.0,
                  builder: (ctx, scrollCtrl) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: ScriptaColors.background,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x20261E1D),
                            blurRadius: 20,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: CustomScrollView(
                        controller: scrollCtrl,
                        slivers: [
                          // Handle
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: ScriptaColors.rule,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),

                          // ── Stat boxes (stile CourseInfoScreen) ──────────
                          SliverToBoxAdapter(
                            child: _StatRow(
                              highlightCount: highlightCount,
                              author: book.author,
                            ),
                          ),

                          // ── Sezione header ────────────────────────────────
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(22, 28, 22, 12),
                              child: Row(
                                children: [
                                  Text(context.l10n.bookHighlightLabel,
                                      style:
                                          ScriptaTextStyles.sectionTitle),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Divider(
                                        color: ScriptaColors.ruleFaint,
                                        height: 1),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Lista highlights ──────────────────────────────
                          highlightsAsync.when(
                            data: (highlights) => highlights.isEmpty
                                ? SliverFillRemaining(
                                    child: Center(
                                      child: Text(
                                        context.l10n.bookNoHighlights,
                                        style: const TextStyle(
                                            color:
                                                ScriptaColors.inkMuted),
                                      ),
                                    ),
                                  )
                                : SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 60),
                                    sliver: SliverList.builder(
                                      itemCount: highlights.length,
                                      itemBuilder: (c, i) => _HighlightCard(
                                        highlight: highlights[i],
                                        index: i,
                                        coverColor: coverColor,
                                        onTap: () => context.push(
                                            '/highlight/${highlights[i].id}'),
                                      ),
                                    ),
                                  ),
                            loading: () => const SliverFillRemaining(
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: ScriptaColors.primaryDark,
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                            error: (e, _) => SliverFillRemaining(
                              child: Center(child: Text(context.l10n.errorPrefix('$e'))),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Back button (sovrapposto all'hero) ────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),


            ],
          ),
        );
      },
      loading: () => Scaffold(
        backgroundColor: ScriptaColors.background,
        body: const Center(
          child: CircularProgressIndicator(
            color: ScriptaColors.primaryDark,
            strokeWidth: 1.5,
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(context.l10n.errorPrefix('$e'))),
      ),
    );
  }
}

// ─── Stat boxes (stile CourseInfoScreen 3-box row) ────────────────────────────

class _StatRow extends StatelessWidget {
  const _StatRow({required this.highlightCount, required this.author});

  final int highlightCount;
  final String author;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StatBox(
            value: '$highlightCount',
            label: context.l10n.bookStatHighlights(highlightCount),
            icon: Icons.format_quote_outlined,
          ),
          // Sottile divisore verticale
          Container(
            width: 0.8, height: 32,
            color: ScriptaColors.ruleFaint,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          _StatBox(
            value: author.split(' ').last,
            label: context.l10n.bookStatAuthor,
            icon: Icons.person_outline,
          ),
          Container(
            width: 0.8, height: 32,
            color: ScriptaColors.ruleFaint,
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          _StatBox(
            value: '',
            label: context.l10n.bookStatReading,
            icon: Icons.menu_book_outlined,
          ),
        ],
      )
          .animate()
          .fadeIn(delay: 100.ms, duration: 350.ms)
          .slideY(begin: 0.04, end: 0, delay: 100.ms, duration: 350.ms),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          // Valore in EB Garamond
          if (value.isNotEmpty)
            Text(
              value,
              style: ScriptaTextStyles.bookTitle.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.ink,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 18, color: ScriptaColors.primaryDark),
          const SizedBox(height: 3),
          // Label in Barlow Condensed uppercase
          Text(
            label.toUpperCase(),
            style: ScriptaTextStyles.sectionTitle.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.5,
              color: ScriptaColors.inkFaint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Highlight card ───────────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.highlight,
    required this.index,
    required this.coverColor,
    required this.onTap,
  });

  final Highlight highlight;
  final int index;
  final Color coverColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: numero + colore dot ──────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${(index + 1).toString().padLeft(2, '0')}',
                        style: ScriptaTextStyles.indexNumber.copyWith(
                          color: ScriptaColors.inkFaint,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      if (highlight.isFavorite)
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 14,
                          color: ScriptaColors.primaryDark,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Testo in EB Garamond italic ────────────────────
                  Text(
                    highlight.content,
                    style: ScriptaTextStyles.highlightBodySmall.copyWith(
                      fontSize: 15.5,
                      height: 1.75,
                    ),
                  ),

                  // ── Nota marginale ─────────────────────────────────
                  if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 11, color: ScriptaColors.inkFaint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            highlight.note!,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: ScriptaColors.inkMuted,
                              fontStyle: FontStyle.italic,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── Footer metadati ────────────────────────────────
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (highlight.location != null)
                        Text(
                          context.l10n.bookLocationPrefix(highlight.location!),
                          style: ScriptaTextStyles.label.copyWith(
                            fontSize: 10,
                            color: ScriptaColors.inkFaint,
                          ),
                        ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Share.share(
                          highlight.content,
                          sharePositionOrigin: shareOrigin(context),
                        ),
                        child: const Icon(Icons.ios_share_rounded,
                            size: 14, color: ScriptaColors.inkFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            // Divider sottile tra highlight
            Container(height: 0.8, color: ScriptaColors.ruleFaint),
          ],
        ),
      ),
    )
        .animate(delay: (index * 35).ms)
        .fadeIn(duration: 300.ms, curve: Curves.easeOut)
        .slideY(
            begin: 0.03, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Color get _accentColor {
    return switch (highlight.color) {
      'yellow' => const Color(0xFFD4A017),
      'blue' => const Color(0xFF4A90BF),
      'pink' => const Color(0xFFBF4A72),
      'orange' => const Color(0xFFBF7A34),
      _ => ScriptaColors.siennaLight,
    };
  }
}

// ─── Cover editing (matitina) ────────────────────────────────────────────────

/// Opens the cover-edit sheet for [book]: pick a photo from the gallery, search
/// Google for one, or remove a custom cover.
void editBookCover(BuildContext context, WidgetRef ref, Book book) {
  final it = Localizations.localeOf(context).languageCode == 'it';
  final hasCustom = (book.coverUrl ?? '').isNotEmpty;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ScriptaColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: ScriptaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                it ? 'Copertina del libro' : 'Book cover',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ScriptaColors.ink,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: ScriptaColors.primaryDark),
            title: Text(it ? 'Scegli dalla galleria' : 'Choose from gallery'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickAndUploadCover(context, ref, book);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined,
                color: ScriptaColors.primaryDark),
            title: Text(it ? 'Scatta una foto' : 'Take a photo'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickFromCameraAndUpload(context, ref, book);
            },
          ),
          ListTile(
            leading: const Icon(Icons.search_rounded,
                color: ScriptaColors.primaryDark),
            title: Text(it ? 'Cerca su Google' : 'Search on Google'),
            subtitle: Text(
              it
                  ? 'Trova e scarica, poi scegline dalla galleria'
                  : 'Find one, save it, then pick from gallery',
              style: const TextStyle(
                  fontSize: 12, color: ScriptaColors.inkFaint),
            ),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _searchCoverOnGoogle(book);
            },
          ),
          if (hasCustom)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: ScriptaColors.highlightRose),
              title: Text(it ? 'Rimuovi copertina' : 'Remove cover'),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await ref
                    .read(bookCoverControllerProvider)
                    .setCover(book.id, null);
                ref.invalidate(favCoversProvider);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _pickAndUploadCover(
    BuildContext context, WidgetRef ref, Book book) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    var ext = (file.extension ?? 'jpg').toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Carico la copertina…' : 'Uploading cover…')));
    final url = await ref
        .read(supabaseServiceProvider)
        .uploadBookCover(bytes, ext, book.supabaseId);
    await ref.read(bookCoverControllerProvider).setCover(book.id, url);
    ref.invalidate(favCoversProvider); // refresh profile favourite covers
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina aggiornata' : 'Cover updated')));
  } catch (_) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it
            ? 'Impossibile aggiornare la copertina'
            : "Couldn't update the cover")));
  }
}

/// Take a NEW photo with the camera and use it as the book cover.
Future<void> _pickFromCameraAndUpload(
    BuildContext context, WidgetRef ref, Book book) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1400,
      imageQuality: 88,
    );
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    var ext = shot.name.contains('.')
        ? shot.name.split('.').last.toLowerCase()
        : 'jpg';
    if (ext == 'jpeg') ext = 'jpg';
    if (ext.isEmpty || ext.length > 4) ext = 'jpg';
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Carico la copertina…' : 'Uploading cover…')));
    final url = await ref
        .read(supabaseServiceProvider)
        .uploadBookCover(bytes, ext, book.supabaseId);
    await ref.read(bookCoverControllerProvider).setCover(book.id, url);
    ref.invalidate(favCoversProvider); // refresh profile favourite covers
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina aggiornata' : 'Cover updated')));
  } catch (_) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it
            ? 'Impossibile aggiornare la copertina'
            : "Couldn't update the cover")));
  }
}

Future<void> _searchCoverOnGoogle(Book book) async {
  final q = Uri.encodeComponent('${book.title} ${book.author} book cover');
  final uri = Uri.parse('https://www.google.com/search?tbm=isch&q=$q');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // ignore — nothing to open
  }
}

/// Small frosted pencil overlaid on the cover.
class _CoverEditButton extends StatelessWidget {
  const _CoverEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        ),
        child: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
      ),
    );
  }
}

