// ─── Highlight semantic search ───────────────────────────────────────────────
//
// "Smart" search over the user's highlights by MEANING, not just keywords:
// type a feeling/idea ("letting go", "il coraggio di iniziare") and get the
// passages that are semantically closest — even when they share no words.
//
// Powered by the `semantic-search` edge function (Supabase's built-in gte-small
// embeddings + pgvector). Degrades gracefully: if the corpus isn't embedded yet,
// is empty, or the network is down, it falls back to local keyword matching.
// A first-use background pass embeds the library in batches.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/highlights_provider.dart';
import '../../core/theme.dart';

class _Result {
  const _Result(this.content, this.bookTitle, this.bookAuthor, this.semantic);
  final String content;
  final String? bookTitle;
  final String? bookAuthor;
  final bool semantic;
}

class HighlightSearchScreen extends ConsumerStatefulWidget {
  const HighlightSearchScreen({super.key});

  @override
  ConsumerState<HighlightSearchScreen> createState() =>
      _HighlightSearchScreenState();
}

class _HighlightSearchScreenState extends ConsumerState<HighlightSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<_Result> _results = const [];
  bool _searched = false;

  // first-use embedding backfill
  bool _indexing = false;
  int _remaining = -1;

  bool get _it =>
      Localizations.localeOf(context).languageCode == 'it';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _backfill());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // Embed the library in batches so semantic search has a corpus. Best-effort,
  // bounded, never throws into the UI.
  Future<void> _backfill() async {
    final svc = ref.read(supabaseServiceProvider);
    if (!svc.isAuthenticated) return;
    if (mounted) setState(() => _indexing = true);
    try {
      for (var i = 0; i < 8; i++) {
        final res = await svc.indexHighlightsForSearch(limit: 200);
        final remaining = (res['remaining'] as num?)?.toInt() ?? 0;
        if (mounted) setState(() => _remaining = remaining);
        // if we have a live query and just embedded new rows, refresh results
        if (_query.trim().isNotEmpty) _runSearch(_query);
        if (remaining <= 0) break;
      }
    } catch (_) {
      // ignore — search still works on whatever is embedded + keyword fallback
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);

    List<_Result> out = const [];
    // 1) semantic
    try {
      final svc = ref.read(supabaseServiceProvider);
      if (svc.isAuthenticated) {
        final rows = await svc.semanticSearchHighlights(q);
        out = rows
            .map((r) => _Result(
                  (r['content'] as String?)?.trim() ?? '',
                  r['book_title'] as String?,
                  r['book_author'] as String?,
                  true,
                ))
            .where((r) => r.content.isNotEmpty)
            .toList();
      }
    } catch (_) {/* fall through to keyword */}

    // 2) keyword fallback (local) when semantic gave nothing
    if (out.isEmpty) {
      try {
        final all = await ref.read(allHighlightsProvider.future);
        final lower = q.toLowerCase();
        out = all
            .where((h) =>
                h.content.toLowerCase().contains(lower) ||
                (h.note?.toLowerCase().contains(lower) ?? false))
            .take(40)
            .map((h) => _Result(h.content, h.bookTitle, h.bookAuthor, false))
            .toList();
      } catch (_) {}
    }

    if (!mounted) return;
    // ignore a stale response if the query moved on
    if (_ctrl.text.trim() != q) return;
    setState(() {
      _results = out;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final it = _it;
    return Scaffold(
      backgroundColor: MarginaliaColors.background,
      appBar: AppBar(
        backgroundColor: MarginaliaColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: MarginaliaColors.ink,
        title: Text(
          it ? 'Cerca per significato' : 'Search by meaning',
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700, fontSize: 18, color: MarginaliaColors.ink),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── search field ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
                style: GoogleFonts.manrope(fontSize: 16, color: MarginaliaColors.ink),
                decoration: InputDecoration(
                  hintText: it
                      ? 'Es. "lasciar andare", "il coraggio di iniziare"…'
                      : 'e.g. "letting go", "the courage to begin"…',
                  hintStyle: GoogleFonts.manrope(
                      fontSize: 15, color: MarginaliaColors.inkFaint),
                  prefixIcon: const Icon(Icons.auto_awesome_outlined,
                      color: MarginaliaColors.primaryDark, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: MarginaliaColors.inkMuted,
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: MarginaliaColors.surfaceElevated,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: MarginaliaColors.primaryDark, width: 1.5),
                  ),
                ),
              ),
            ),

            // ── indexing banner ───────────────────────────────────────────
            if (_indexing && _remaining > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: MarginaliaColors.primaryDark),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        it
                            ? 'Preparazione ricerca intelligente… ($_remaining rimanenti)'
                            : 'Preparing smart search… ($_remaining left)',
                        style: GoogleFonts.manrope(
                            fontSize: 12.5, color: MarginaliaColors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),

            // ── results ───────────────────────────────────────────────────
            Expanded(child: _body(it)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool it) {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
            color: MarginaliaColors.primaryDark, strokeWidth: 1.6),
      );
    }
    if (!_searched) {
      return _Hint(
        icon: Icons.auto_awesome_outlined,
        title: it ? 'Cerca per idea, non per parola' : 'Search by idea, not keyword',
        body: it
            ? 'Scrivi un concetto o un’emozione: trovo i passaggi più vicini per significato, anche se usano parole diverse.'
            : 'Type a concept or feeling — I surface the passages closest in meaning, even when they share no words.',
      );
    }
    if (_results.isEmpty) {
      return _Hint(
        icon: Icons.search_off_rounded,
        title: it ? 'Nessun risultato' : 'No results',
        body: it
            ? 'Prova con parole diverse o un concetto più ampio.'
            : 'Try different words or a broader concept.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ResultCard(_results[i]),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.r);
  final _Result r;

  @override
  Widget build(BuildContext context) {
    final attribution = [r.bookTitle, r.bookAuthor]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MarginaliaColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.content,
            style: GoogleFonts.ebGaramond(
              fontSize: 17,
              height: 1.45,
              color: MarginaliaColors.ink,
            ),
          ),
          if (attribution.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              attribution,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.primaryDark,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: MarginaliaColors.primaryDark),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.ebGaramond(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: MarginaliaColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.5,
                color: MarginaliaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
