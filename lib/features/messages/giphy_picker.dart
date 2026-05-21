import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';

// ─── GIF Picker (Reddit JSON API — no key required) ───────────────────────────
//
// Uses Reddit's public JSON endpoints on r/gifs and r/reactiongifs.
// No API key, no registration. Rate limit: ~60 req/min per IP (plenty for a
// native app). Requires User-Agent header so Reddit doesn't treat us as a bot.

const _kUserAgent = 'Marginalia-App/1.0 (native; contact: app@marginalia.app)';

// ─── Public API ───────────────────────────────────────────────────────────────

/// Shows a bottom sheet for searching and selecting a GIF via Reddit.
/// Returns the selected GIF URL or null if dismissed.
Future<String?> showGifPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GifPickerSheet(),
  );
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

class _GifPickerSheet extends StatefulWidget {
  const _GifPickerSheet();

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final _searchController = TextEditingController();
  List<_GifItem> _gifs = [];
  bool _loading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _fetchTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Trending (hot posts from r/gifs) ──────────────────────────────────────

  Future<void> _fetchTrending() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://www.reddit.com/r/gifs/hot.json?limit=50&raw_json=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _kUserAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _parseAndSetGifs(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Search across r/gifs + r/reactiongifs ─────────────────────────────────

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _fetchTrending();
      return;
    }
    setState(() {
      _loading = true;
      _hasSearched = true;
    });
    try {
      final uri = Uri.parse(
        'https://www.reddit.com/r/gifs+reactiongifs/search.json'
        '?q=${Uri.encodeComponent(query.trim())}'
        '&limit=50&sort=top&t=all&raw_json=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _kUserAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _parseAndSetGifs(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Parser ────────────────────────────────────────────────────────────────
  //
  // Reddit posts in r/gifs include a `preview` block with an animated GIF
  // variant at preview.images[0].variants.gif. We use that URL as both
  // the thumbnail (smaller) and the full GIF to send.

  void _parseAndSetGifs(Map<String, dynamic> data) {
    final children = (data['data']?['children'] as List? ?? []);
    final items = <_GifItem>[];

    for (final child in children) {
      final post = child['data'] as Map<String, dynamic>? ?? {};

      // Skip removed / deleted posts
      if (post['removed_by_category'] != null) continue;
      if (post['selftext'] == '[removed]') continue;

      final preview = post['preview'] as Map<String, dynamic>?;
      if (preview == null) continue;

      final images = preview['images'] as List?;
      if (images == null || images.isEmpty) continue;

      final firstImage = images.first as Map<String, dynamic>? ?? {};
      final variants = firstImage['variants'] as Map<String, dynamic>? ?? {};
      final gifVariant = variants['gif'] as Map<String, dynamic>?;
      final gifSource = gifVariant?['source'] as Map<String, dynamic>?;
      final fullGifUrl = gifSource?['url'] as String?;

      // Static JPEG preview for the grid thumbnail (faster to load)
      final sourceMap = firstImage['source'] as Map<String, dynamic>? ?? {};
      final previewUrl = sourceMap['url'] as String? ?? '';

      // Fallback: if Reddit didn't generate a gif variant but the post URL
      // itself is a direct .gif (e.g. i.redd.it/*.gif), use that.
      final postUrl = post['url'] as String? ?? '';
      final resolvedFull =
          fullGifUrl ?? (postUrl.toLowerCase().endsWith('.gif') ? postUrl : null);

      if (previewUrl.isNotEmpty && resolvedFull != null) {
        items.add(_GifItem(previewUrl: previewUrl, fullUrl: resolvedFull));
      }
    }

    if (mounted) setState(() => _gifs = items);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.72;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MarginaliaColors.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onSubmitted: _search,
              style: GoogleFonts.barlow(
                fontSize: 15,
                color: MarginaliaColors.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Cerca GIF…',
                hintStyle: GoogleFonts.barlow(
                  color: MarginaliaColors.inkFaint,
                  fontSize: 15,
                ),
                prefixIcon: const Icon(Icons.gif_box_outlined,
                    color: MarginaliaColors.inkFaint, size: 22),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: MarginaliaColors.sienna,
                          ),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search_rounded,
                            color: MarginaliaColors.inkFaint, size: 20),
                        onPressed: () => _search(_searchController.text),
                      ),
                filled: true,
                fillColor: MarginaliaColors.surfaceElevated,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: MarginaliaColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // GIF grid
          Expanded(
            child: _gifs.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _hasSearched
                          ? 'Nessun risultato'
                          : 'In caricamento…',
                      style: GoogleFonts.barlow(
                        color: MarginaliaColors.inkFaint,
                        fontSize: 14,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: _gifs.length,
                    itemBuilder: (context, index) {
                      final gif = _gifs[index];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pop(gif.fullUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            gif.previewUrl,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => Container(
                              color: MarginaliaColors.surfaceElevated,
                              child: const Icon(Icons.gif,
                                  color: MarginaliaColors.inkFaint, size: 32),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Model ────────────────────────────────────────────────────────────────────

class _GifItem {
  const _GifItem({required this.previewUrl, required this.fullUrl});
  final String previewUrl; // static JPEG thumbnail for the picker grid
  final String fullUrl;    // animated GIF to send
}
