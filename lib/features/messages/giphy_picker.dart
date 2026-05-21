import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme.dart';

// ─── GIPHY API Key ────────────────────────────────────────────────────────────
// Get your free key at https://developers.giphy.com/
// Replace this with your own key before shipping to production.
const _kGiphyApiKey = 'dc6zaTOxFJmzC'; // public beta key

// ─── GiphyPicker ─────────────────────────────────────────────────────────────

/// Shows a bottom sheet for searching and selecting a GIF from GIPHY.
/// Returns the selected GIF URL (original mp4 or gif url), or null if dismissed.
Future<String?> showGiphyPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GiphyPickerSheet(),
  );
}

class _GiphyPickerSheet extends StatefulWidget {
  const _GiphyPickerSheet();

  @override
  State<_GiphyPickerSheet> createState() => _GiphyPickerSheetState();
}

class _GiphyPickerSheetState extends State<_GiphyPickerSheet> {
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

  Future<void> _fetchTrending() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://api.giphy.com/v1/gifs/trending'
        '?api_key=$_kGiphyApiKey&limit=24&rating=g',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        _setGifs(data);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

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
        'https://api.giphy.com/v1/gifs/search'
        '?api_key=$_kGiphyApiKey'
        '&q=${Uri.encodeComponent(query.trim())}'
        '&limit=24&rating=g',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        _setGifs(data);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _setGifs(Map<String, dynamic> data) {
    final items = (data['data'] as List? ?? []).map((g) {
      final images = g['images'] as Map<String, dynamic>? ?? {};
      final fixed = images['fixed_height'] as Map<String, dynamic>? ?? {};
      final orig = images['original'] as Map<String, dynamic>? ?? {};
      return _GifItem(
        previewUrl: fixed['url'] as String? ?? '',
        fullUrl: orig['url'] as String? ?? fixed['url'] as String? ?? '',
      );
    }).where((g) => g.previewUrl.isNotEmpty).toList();

    if (mounted) setState(() => _gifs = items);
  }

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

          // GIPHY branding (required by their ToS)
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Powered by GIPHY',
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
                      _hasSearched ? 'Nessun risultato' : 'In caricamento…',
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

class _GifItem {
  const _GifItem({required this.previewUrl, required this.fullUrl});
  final String previewUrl;
  final String fullUrl;
}
