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
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../core/providers/books_provider.dart';
import '../profile/profile_shared_widgets.dart' show favCoversProvider;
import '../profile/fav_books_actions.dart';
import '../../core/services/supabase_service.dart'
    show ImageModerationException;
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

              // ── Cover actions (cuore + matitina) ──────────────────────────
              // A heart to add/remove the book from the profile's "libri del
              // cuore", plus a frosted pencil to edit the cover. Both sit clear
              // of the back button on the cover's top-right.
              Positioned(
                top: MediaQuery.of(context).padding.top + 6,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CoverFavButton(book: book),
                    const SizedBox(width: 10),
                    _CoverEditButton(
                      onTap: () => editBookCover(context, ref, book),
                    ),
                  ],
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
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _removeCover(context, ref, book);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Human-readable cover-update failure. The generic "impossibile aggiornare la
/// copertina" hid the real cause (moderation rejection vs storage/RLS vs
/// network), making the bug undiagnosable from the device — now the snackbar
/// names the step that failed and the log carries the full error.
String _coverErrorText(Object error, bool it) {
  debugPrint('[Cover] update failed: $error');
  if (error is ImageModerationException) {
    return it
        ? 'Immagine non consentita: la moderazione l’ha rifiutata'
        : 'Image not allowed: rejected by moderation';
  }
  final raw = error.toString().replaceAll('\n', ' ').trim();
  final detail = raw.length > 110 ? '${raw.substring(0, 110)}…' : raw;
  if (detail.isEmpty) {
    return it
        ? 'Impossibile aggiornare la copertina'
        : "Couldn't update the cover";
  }
  return it
      ? 'Impossibile aggiornare la copertina — $detail'
      : "Couldn't update the cover — $detail";
}

/// Centred modal loading overlay shown while a cover uploads. A rounded white
/// card with a sage spinner that stays up (barrier-locked) until the upload AND
/// both DB writes AND provider invalidation finish, so the founder gets clear
/// "working…" feedback instead of a transient snackbar. Always pair with a
/// try/finally that closes it via the captured root navigator.
void _showCoverUploadingOverlay(BuildContext context, bool it) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      // Material ancestor: without it the Text below renders with the yellow
      // "missing Material" debug underline (this dialog returns a raw Container,
      // not an AlertDialog/Dialog which would supply Material themselves).
      child: Material(
        type: MaterialType.transparency,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: ScriptaColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33261E1D),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: ScriptaColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              it ? 'Carico la copertina…' : 'Uploading cover…',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ScriptaColors.ink,
              ),
            ),
          ],
        ),
      ),
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
    if (!context.mounted) return;
    // Capture the root navigator BEFORE awaiting so we can always dismiss the
    // overlay even if the original context unmounts during the upload.
    final rootNav = Navigator.of(context, rootNavigator: true);
    _showCoverUploadingOverlay(context, it);
    try {
      final url = await ref
          .read(supabaseServiceProvider)
          .uploadBookCover(bytes, ext, book.supabaseId);
      await ref.read(bookCoverControllerProvider).setCover(book.id, url);
      // Single source of truth: mirror to the per-user cover store so the cover
      // shows on favourites, reviews and to anyone visiting the profile.
      await ref
          .read(supabaseServiceProvider)
          .setUserBookCover(book.title, book.author, url);
      ref.invalidate(favCoversProvider); // refresh profile favourite covers
    } finally {
      // ALWAYS close the overlay, on success or error, before the snackbar.
      if (rootNav.canPop()) rootNav.pop();
    }
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina aggiornata' : 'Cover updated')));
  } catch (error) {
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
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
    if (!context.mounted) return;
    // Capture the root navigator BEFORE awaiting so we can always dismiss the
    // overlay even if the original context unmounts during the upload.
    final rootNav = Navigator.of(context, rootNavigator: true);
    _showCoverUploadingOverlay(context, it);
    try {
      final url = await ref
          .read(supabaseServiceProvider)
          .uploadBookCover(bytes, ext, book.supabaseId);
      await ref.read(bookCoverControllerProvider).setCover(book.id, url);
      // Single source of truth: mirror to the per-user cover store so the cover
      // shows on favourites, reviews and to anyone visiting the profile.
      await ref
          .read(supabaseServiceProvider)
          .setUserBookCover(book.title, book.author, url);
      ref.invalidate(favCoversProvider); // refresh profile favourite covers
    } finally {
      // ALWAYS close the overlay, on success or error, before the snackbar.
      if (rootNav.canPop()) rootNav.pop();
    }
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina aggiornata' : 'Cover updated')));
  } catch (error) {
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
  }
}

/// Remove a custom cover for a library [book]. DB-first: if the network remove
/// fails we surface the error BEFORE dropping the local cover, so the on-screen
/// state stays consistent — and confirm success, like the upload paths do.
Future<void> _removeCover(BuildContext context, WidgetRef ref, Book book) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    await ref
        .read(supabaseServiceProvider)
        .removeUserBookCover(book.title, book.author);
    await ref.read(bookCoverControllerProvider).setCover(book.id, null);
    ref.invalidate(favCoversProvider);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina rimossa' : 'Cover removed')));
  } catch (error) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
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

// ─── Cover editing BY TITLE/AUTHOR (profile favourites) ──────────────────────
//
// The profile favourites store only {title, author} (no book id). This variant
// lets the pencil there edit a cover for ANY favourite — it writes the per-user
// cover store (the single source of truth shown everywhere + to visitors) and
// also mirrors to the local Isar book when one matches (so the library updates
// offline too). The storage filename is a stable hash of title|author.

String _coverStorageKey(String title, String author) {
  final k = '${title.toLowerCase().trim()}|${author.toLowerCase().trim()}';
  return sha1.convert(utf8.encode(k)).toString();
}

Book? _findLibraryBook(WidgetRef ref, String title, String author) {
  final list = ref.read(booksProvider).asData?.value;
  if (list == null) return null;
  final t = title.toLowerCase().trim();
  final a = author.toLowerCase().trim();
  for (final b in list) {
    if (b.title.toLowerCase().trim() == t &&
        b.author.toLowerCase().trim() == a) {
      return b;
    }
  }
  // No title-only fallback: the per-user cover store is keyed by title|author,
  // so mirroring onto a same-title-different-author library book would flip the
  // cover of an unrelated book. Require an exact title+author match.
  return null;
}

void editBookCoverByKey(
    BuildContext context, WidgetRef ref, String title, String author) {
  final it = Localizations.localeOf(context).languageCode == 'it';
  final key = '${title.toLowerCase().trim()}|${author.toLowerCase().trim()}';
  final hasCustom =
      ((ref.read(favCoversProvider(null)).asData?.value ?? const {})[key] ?? '')
          .isNotEmpty;
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
                    color: ScriptaColors.ink),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: ScriptaColors.primaryDark),
            title: Text(it ? 'Scegli dalla galleria' : 'Choose from gallery'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickAndUploadCoverByKey(context, ref, title, author);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined,
                color: ScriptaColors.primaryDark),
            title: Text(it ? 'Scatta una foto' : 'Take a photo'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _pickFromCameraByKey(context, ref, title, author);
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
              style:
                  const TextStyle(fontSize: 12, color: ScriptaColors.inkFaint),
            ),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _searchCoverOnGoogleQuery(title, author);
            },
          ),
          if (hasCustom)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: ScriptaColors.highlightRose),
              title: Text(it ? 'Rimuovi copertina' : 'Remove cover'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _removeCoverByKey(context, ref, title, author);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _applyCoverByKey(BuildContext context, WidgetRef ref, String title,
    String author, Uint8List bytes, String ext) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  // Capture the root navigator BEFORE awaiting so we can always dismiss the
  // overlay even if the original context unmounts during the upload.
  final rootNav = Navigator.of(context, rootNavigator: true);
  _showCoverUploadingOverlay(context, it);
  try {
    final url = await ref
        .read(supabaseServiceProvider)
        .uploadBookCover(bytes, ext, _coverStorageKey(title, author));
    await ref
        .read(supabaseServiceProvider)
        .setUserBookCover(title, author, url);
    final b = _findLibraryBook(ref, title, author);
    if (b != null) {
      await ref.read(bookCoverControllerProvider).setCover(b.id, url);
    }
    ref.invalidate(favCoversProvider);
    // Close the overlay BEFORE the success snackbar.
    if (rootNav.canPop()) rootNav.pop();
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina aggiornata' : 'Cover updated')));
  } catch (error) {
    // ALWAYS close the overlay on error before surfacing the failure.
    if (rootNav.canPop()) rootNav.pop();
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
  }
}

Future<void> _pickAndUploadCoverByKey(
    BuildContext context, WidgetRef ref, String title, String author) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.first.bytes;
    if (bytes == null) return;
    var ext = (res.files.first.extension ?? 'jpg').toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    if (context.mounted) {
      await _applyCoverByKey(context, ref, title, author, bytes, ext);
    }
  } catch (error) {
    // Picker failure (e.g. permission denied) — surface like any cover error.
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
  }
}

Future<void> _pickFromCameraByKey(
    BuildContext context, WidgetRef ref, String title, String author) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    final shot = await ImagePicker().pickImage(
        source: ImageSource.camera, maxWidth: 1400, imageQuality: 88);
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    var ext = shot.name.contains('.')
        ? shot.name.split('.').last.toLowerCase()
        : 'jpg';
    if (ext == 'jpeg') ext = 'jpg';
    if (ext.isEmpty || ext.length > 4) ext = 'jpg';
    if (context.mounted) {
      await _applyCoverByKey(context, ref, title, author, bytes, ext);
    }
  } catch (error) {
    // Camera failure (e.g. permission denied) — surface like any cover error.
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
  }
}

/// Remove a custom cover keyed by title|author (profile favourites). DB-first,
/// then mirror to the local Isar book if one matches — with confirm/error toast.
Future<void> _removeCoverByKey(
    BuildContext context, WidgetRef ref, String title, String author) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final it = Localizations.localeOf(context).languageCode == 'it';
  try {
    await ref.read(supabaseServiceProvider).removeUserBookCover(title, author);
    final b = _findLibraryBook(ref, title, author);
    if (b != null) {
      await ref.read(bookCoverControllerProvider).setCover(b.id, null);
    }
    ref.invalidate(favCoversProvider);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(it ? 'Copertina rimossa' : 'Cover removed')));
  } catch (error) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
        content: Text(_coverErrorText(error, it)),
        duration: const Duration(seconds: 6)));
  }
}

Future<void> _searchCoverOnGoogleQuery(String title, String author) async {
  final q = Uri.encodeComponent('$title $author book cover');
  final uri = Uri.parse('https://www.google.com/search?tbm=isch&q=$q');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // ignore — nothing to open
  }
}

/// Frosted heart overlaid on the cover — toggles the book in the profile's
/// "libri del cuore" (max 6). Filled when the book is already a favourite,
/// outline otherwise; both states give snackbar feedback via [toggleFavoriteBook].
class _CoverFavButton extends ConsumerWidget {
  const _CoverFavButton({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref
            .watch(isFavoriteBookProvider(
                (title: book.title, author: book.author)))
            .asData
            ?.value ??
        false;
    return GestureDetector(
      onTap: () => toggleFavoriteBook(
        context,
        ref,
        title: book.title,
        author: book.author,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.28),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
        ),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          // Brand red (0xFFB94A41) when favourited, white outline otherwise.
          color: isFav ? const Color(0xFFB94A41) : Colors.white,
        ),
      ),
    );
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

