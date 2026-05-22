import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';

// ─── Tenor v2 — public demo key, no registration required ─────────────────────
//
// LIVDSRZULELA is Tenor's official public key, documented in their quickstart:
// https://developers.google.com/tenor/guides/quickstart
// "For your first API call, use LIVDSRZULELA as your API key."
// No account needed. Replace with a registered key before shipping at scale.

const _kTenorKey       = 'LIVDSRZULELA';
const _kTenorClientKey = 'marginalia_app';

// ─── Public API ───────────────────────────────────────────────────────────────

/// Shows a bottom sheet for searching and selecting a GIF via Tenor.
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
    _fetchFeatured();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Featured / trending ───────────────────────────────────────────────────

  Future<void> _fetchFeatured() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://tenor.googleapis.com/v2/featured'
        '?key=$_kTenorKey'
        '&client_key=$_kTenorClientKey'
        '&limit=30'
        '&media_filter=tinygif,gif',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _parseAndSet(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _fetchFeatured();
      return;
    }
    setState(() {
      _loading = true;
      _hasSearched = true;
    });
    try {
      final uri = Uri.parse(
        'https://tenor.googleapis.com/v2/search'
        '?key=$_kTenorKey'
        '&client_key=$_kTenorClientKey'
        '&q=${Uri.encodeComponent(query.trim())}'
        '&limit=30'
        '&media_filter=tinygif,gif',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _parseAndSet(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Parser ────────────────────────────────────────────────────────────────
  //
  // Tenor v2 response: results[].media_formats.{tinygif,gif}.url
  // tinygif  ≈ 220 px wide animated GIF  → use as picker thumbnail
  // gif      ≈ full-res animated GIF     → send to chat / comment

  void _parseAndSet(Map<String, dynamic> data) {
    final results = data['results'] as List? ?? [];
    final items = <_GifItem>[];

    for (final r in results) {
      final formats = (r as Map<String, dynamic>)['media_formats']
          as Map<String, dynamic>? ?? {};
      final tiny = (formats['tinygif'] as Map<String, dynamic>?)?['url'] as String?;
      final full = (formats['gif']     as Map<String, dynamic>?)?['url'] as String?
                ?? tiny; // fallback to tinygif if full gif not returned
      if (tiny != null && full != null) {
        items.add(_GifItem(previewUrl: tiny, fullUrl: full));
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
          const SizedBox(height: 4),

          // Tenor attribution (required by Tenor ToS)
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Via Tenor',
                style: GoogleFonts.barlow(
                  fontSize: 10,
                  color: MarginaliaColors.inkFaint,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          // GIF grid
          Expanded(
            child: _gifs.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _hasSearched ? 'Nessun risultato' : 'Caricamento…',
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
                    itemBuilder: (context, i) {
                      final gif = _gifs[i];
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
  final String previewUrl; // tinygif (~220 px) for the picker grid
  final String fullUrl;    // full-res gif to send
}
