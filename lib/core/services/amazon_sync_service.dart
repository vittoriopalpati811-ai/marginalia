import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'import_match.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── AmazonSyncService ────────────────────────────────────────────────────────
//
// Extracts Kindle highlights from the Amazon "Notebook" (Your Notes &
// Highlights) page. Same approach used by Readwise, Obsidian and every other
// Kindle import tool — the user signs into THEIR OWN Amazon account inside the
// WebView; the app never sees the credentials.
//
// How the Notebook page actually works (this is the crux):
// ────────────────────────────────────────────────────────
// `…/notebook` renders a LEFT pane listing every book (`.kp-notebook-library-
// each-book`, whose element id is the ASIN) and a RIGHT pane that shows the
// highlights for the ONE currently-selected book only. The highlights for a
// given book are server-rendered and can be fetched directly at
//   {origin}/notebook?asin={ASIN}&contentLimitState={state}&token={token}
// with the next-page token read from a hidden input — so the robust way to get
// EVERYTHING is: read the book list, then fetch each book's annotations page(s)
// and paginate. (An earlier version naively scraped `.a-section` blocks from the
// landing DOM and silently found nothing — that was the "sync doesn't work" bug.)
//
// Region-safe: the injected script uses `location.origin`, so whichever Amazon
// marketplace the user actually landed on (amazon.com, leggi.amazon.it,
// lesen.amazon.de, …) is used for the fetches automatically — no CORS, cookies
// included, no hard-coded region.
//
// Async delivery: the extraction is asynchronous (many fetches + pagination) and
// WKWebView's `runJavaScriptReturningResult` does NOT await Promises, so the
// script streams progress and the final payload back through a JavaScript
// channel (see [channelName]); the screen awaits that instead of a return value.
//
// HOT-FIX MECHANISM:
// The extractor JS is fetched from Supabase at runtime (table:
// amazon_sync_scripts) and falls back to the compiled-in [_fallbackExtractorJs]
// on any error. To fix a broken Amazon scrape WITHOUT an App Store release:
//   UPDATE amazon_sync_scripts SET script = '<new JS>', version = version + 1,
//   updated_at = now() WHERE is_active = true;
// Any remote replacement MUST also post its result through `window.<channelName>`
// (see the fallback script below for the contract).

class AmazonSyncService {
  /// The Notebook page. NOTE: `/notebook` (not the old `/kp/notebook`, which
  /// 404s for many accounts). Amazon redirects this to the user's regional host
  /// when needed; the extractor then keys off `location.origin`.
  static const String notebookUrl = 'https://read.amazon.com/notebook';

  /// Loaded FIRST so the user signs into Amazon on the Cloud Reader. Navigating
  /// straight to the notebook while unauthenticated shows Amazon's "couldn't
  /// find that page"; starting here lets Amazon handle the sign-in, after which
  /// the user taps the button to open the (now authenticated) notebook.
  static const String entryUrl = 'https://read.amazon.com';

  /// Name of the JavaScript channel the extractor posts results through. The
  /// screen registers a channel with this exact name on its WebViewController.
  static const String channelName = 'ScriptaKindleSync';

  // In-memory cache of the remote script (cleared on app restart / on mismatch).
  static String? _cachedScript;

  // ── Compiled-in fallback extractor (authoritative; always available) ───────
  //
  // Contract: posts JSON messages to window.<channelName>:
  //   {"type":"progress","book":"<title>","total":<int>}   — per book, optional
  //   {"type":"done","highlights":[{bookTitle,bookAuthor,content,location,color}]}
  //   {"type":"error","error":"<message>"}                  — fatal
  //   {"type":"error","error":"NO_BOOKS"}                   — logged-in but empty
  static const String _fallbackExtractorJs = r"""
(function () {
  var CHANNEL = "ScriptaKindleSync";
  function post(obj) {
    try { window[CHANNEL].postMessage(JSON.stringify(obj)); } catch (e) {}
  }

  var origin = location.origin;
  var notebook = origin + "/notebook";

  function parseBooks(doc) {
    var els = doc.querySelectorAll(".kp-notebook-library-each-book");
    var books = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var titleEl = el.querySelector("h2.kp-notebook-searchable") ||
                    el.querySelector("h2");
      var authorEl = el.querySelector("p.kp-notebook-searchable") ||
                     el.querySelector("p");
      var title = titleEl ? (titleEl.innerText || titleEl.textContent || "").trim() : "";
      var author = authorEl ? (authorEl.innerText || authorEl.textContent || "") : "";
      // Author is rendered like "By: Jane Doe" / "Di: …" / "De : …" — drop prefix.
      author = author.replace(/.*:\s*/, "").trim();
      var asin = el.id || el.getAttribute("id") || "";
      if (asin) books.push({ asin: asin, title: title, author: author });
    }
    return books;
  }

  function parseHighlights(doc, book) {
    var out = [];
    var rows = doc.querySelectorAll(".a-row.a-spacing-base");
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      // Scoped #id lookups still work within a subtree even though Amazon
      // (invalidly) reuses these ids on every row.
      var span = row.querySelector("#highlight") ||
                 row.querySelector(".kp-notebook-highlight");
      var text = span ? (span.innerText || span.textContent || "").trim() : "";
      if (!text) continue;

      var locEl = row.querySelector("#kp-annotation-location");
      var location = locEl ? (locEl.value || locEl.getAttribute("value") || null) : null;

      var hlEl = row.querySelector(".kp-notebook-highlight");
      var cls = hlEl ? (hlEl.className || "") : "";
      var cm = /kp-notebook-highlight-(\w+)/.exec(cls);

      out.push({
        bookTitle: book.title,
        bookAuthor: book.author,
        content: text,
        location: location,
        color: cm ? cm[1] : null
      });
    }
    return out;
  }

  function nextState(doc) {
    var t = doc.querySelector(".kp-notebook-annotations-next-page-start");
    var c = doc.querySelector(".kp-notebook-content-limit-state");
    if (!t) return null;
    var token = t.value || t.getAttribute("value") || "";
    if (!token) return null;
    return { token: token, limit: c ? (c.value || c.getAttribute("value") || "") : "" };
  }

  function fetchDoc(url) {
    return fetch(url, { credentials: "include" })
      .then(function (r) { return r.text(); })
      .then(function (html) {
        return new DOMParser().parseFromString(html, "text/html");
      });
  }

  function highlightsUrl(asin, state) {
    return notebook + "?asin=" + encodeURIComponent(asin) +
      "&contentLimitState=" + (state ? encodeURIComponent(state.limit) : "") +
      "&token=" + (state ? encodeURIComponent(state.token) : "");
  }

  // Sequentially page through one book's annotations.
  function scrapeBook(book, all) {
    function loop(state, guard) {
      if (guard > 60) return Promise.resolve();
      return fetchDoc(highlightsUrl(book.asin, state)).then(function (doc) {
        var hs = parseHighlights(doc, book);
        for (var i = 0; i < hs.length; i++) all.push(hs[i]);
        var ns = nextState(doc);
        if (ns) return loop(ns, guard + 1);
        return Promise.resolve();
      });
    }
    return loop(null, 0);
  }

  function run() {
    var booksReady;
    if (document.querySelector(".kp-notebook-library-each-book")) {
      booksReady = Promise.resolve(parseBooks(document));
    } else {
      // Page may still be hydrating, or we were invoked off-notebook: fetch the
      // server-rendered notebook HTML (cookies included) and read books there.
      booksReady = fetchDoc(notebook).then(function (doc) { return parseBooks(doc); });
    }

    booksReady.then(function (books) {
      if (!books || books.length === 0) {
        post({ type: "error", error: "NO_BOOKS" });
        return;
      }
      var all = [];
      var chain = Promise.resolve();
      books.forEach(function (book) {
        chain = chain.then(function () {
          return scrapeBook(book, all).then(function () {
            post({ type: "progress", book: book.title, total: all.length });
          });
        });
      });
      chain.then(function () {
        post({ type: "done", highlights: all });
      }).catch(function (e) {
        post({ type: "error", error: String((e && e.message) || e) });
      });
    }).catch(function (e) {
      post({ type: "error", error: String((e && e.message) || e) });
    });
  }

  try { run(); } catch (e) { post({ type: "error", error: String((e && e.message) || e) }); }
})();
""";

  // ── Script fetching ───────────────────────────────────────────────────────

  /// Returns the active extractor JS — remote (hot-fixable) if available, else
  /// the compiled-in fallback. Never throws.
  static Future<String> extractorScript() async {
    if (_cachedScript != null) return _cachedScript!;

    try {
      final row = await Supabase.instance.client
          .from('amazon_sync_scripts')
          .select('version, script')
          .eq('is_active', true)
          .order('version', ascending: false)
          .limit(1)
          .single();

      final version = row['version'] as int?;
      final script = row['script'] as String?;
      if (script != null && script.isNotEmpty) {
        _cachedScript = script;
        if (kDebugMode) debugPrint('[AmazonSync] Using remote JS v$version');
        return script;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AmazonSync] Remote JS unavailable ($e) — using fallback');
      }
    }
    return _fallbackExtractorJs;
  }

  /// Clears the in-memory script cache so the next sync re-fetches from Supabase.
  static void invalidateScriptCache() {
    _cachedScript = null;
  }

  // ── Page detection ────────────────────────────────────────────────────────

  /// Whether the WebView is on a Notebook page (post-login). Matches any Amazon
  /// marketplace host (read.amazon.com, leggi.amazon.it, lesen.amazon.de, …).
  static bool isOnNotebookPage(String currentUrl) {
    final u = currentUrl.toLowerCase();
    return u.contains('amazon.') && u.contains('/notebook');
  }

  /// Given the URL the WebView is currently on (after login + any Amazon
  /// redirects), returns the notebook URL on the SAME host — so a regional
  /// account (leggi.amazon.it, lesen.amazon.de, leer.amazon.es, lire.amazon.fr,
  /// read.amazon.co.uk, …) opens ITS OWN notebook and the cookies/CORS line up.
  /// Falls back to [notebookUrl] when the host can't be determined.
  static String notebookUrlForHost(String? currentUrl) {
    final uri = currentUrl == null ? null : Uri.tryParse(currentUrl);
    if (uri == null || !uri.hasAuthority) return notebookUrl;
    final host = uri.host.toLowerCase();
    if (!host.contains('amazon.')) return notebookUrl;
    return '${uri.scheme}://$host/notebook';
  }

  // ── Channel message parsing ───────────────────────────────────────────────

  /// Parses one JSON message posted by the extractor through the channel.
  /// Returns a [SyncMessage]; throws nothing (malformed messages become a
  /// `SyncMessage.error`).
  static SyncMessage parseChannelMessage(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      switch (map['type']) {
        case 'progress':
          return SyncMessage.progress(
            book: map['book'] as String? ?? '',
            total: (map['total'] as num?)?.toInt() ?? 0,
          );
        case 'done':
          final list = (map['highlights'] as List<dynamic>? ?? const [])
              .map((e) => AmazonHighlight.fromJson(e as Map<String, dynamic>))
              .where((h) => h.content.trim().isNotEmpty)
              .toList();
          return SyncMessage.done(list);
        case 'error':
        default:
          return SyncMessage.error(map['error'] as String? ?? 'Unknown error');
      }
    } catch (e) {
      return SyncMessage.error('Malformed sync message: $e');
    }
  }
}

// ─── Channel message model ────────────────────────────────────────────────────

enum SyncMessageType { progress, done, error }

class SyncMessage {
  const SyncMessage._(this.type, {this.book, this.total, this.highlights, this.error});

  factory SyncMessage.progress({required String book, required int total}) =>
      SyncMessage._(SyncMessageType.progress, book: book, total: total);
  factory SyncMessage.done(List<AmazonHighlight> highlights) =>
      SyncMessage._(SyncMessageType.done, highlights: highlights);
  factory SyncMessage.error(String error) =>
      SyncMessage._(SyncMessageType.error, error: error);

  final SyncMessageType type;
  final String? book;
  final int? total;
  final List<AmazonHighlight>? highlights;
  final String? error;
}

// ─── AmazonHighlight model ────────────────────────────────────────────────────

class AmazonHighlight {
  const AmazonHighlight({
    required this.bookTitle,
    required this.bookAuthor,
    required this.content,
    this.location,
    this.color,
  });

  final String bookTitle;
  final String bookAuthor;
  final String content;
  final String? location;
  final String? color;

  factory AmazonHighlight.fromJson(Map<String, dynamic> json) {
    return AmazonHighlight(
      bookTitle: json['bookTitle'] as String? ?? '',
      bookAuthor: json['bookAuthor'] as String? ?? '',
      content: json['content'] as String? ?? '',
      location: json['location'] as String?,
      color: json['color'] as String?,
    );
  }

  /// Converts to a My Clippings.txt entry so ImportService can process it
  /// without duplicating parsing logic.
  ///
  /// The "Title (Author)" line MUST keep the parentheses: MyClippingsParser
  /// requires them and silently drops any entry without them, so a book with no
  /// detected author falls back to a placeholder rather than losing its
  /// highlights.
  String toClippingEntry() {
    final author = bookAuthor.trim().isEmpty ? 'Sconosciuto' : bookAuthor.trim();

    // Location: NEVER a constant fallback. The importer dedups on
    // (book, location), so writing '0' for every highlight Amazon gives no
    // location for meant a whole book collapsed to its single longest
    // highlight and the rest vanished without a word. A stable content hash
    // keeps distinct highlights distinct AND keeps a re-sync idempotent — the
    // same fix the paste and Kobo importers already use.
    // A stable digest, NOT String.hashCode: this value is persisted and
    // compared on every later sync, and Dart makes no promise that hashCode
    // survives an SDK upgrade. If it shifted, every locationless highlight
    // would come back as new exactly once — silently, and for good.
    final loc = location ?? contentFingerprint(content);

    // Date: must be in a shape MyClippingsParser can actually read. Writing a
    // raw `DateTime.now()` ("2026-08-05 12:34:56.789012") matched none of the
    // parser's formats, so every Kindle-synced highlight landed with a null
    // date — which is what the reading-session stats are derived from.
    //
    // In UTC, because the parser calls `DateFormat.parse(str, true)`, i.e. it
    // reads whatever it is given AS UTC. Handing it local time would file every
    // highlight off by the timezone offset.
    final added = DateFormat('EEEE, MMMM d, yyyy h:mm:ss a', 'en_US')
        .format(DateTime.now().toUtc());

    return '$bookTitle ($author)\n'
        '- Your Highlight on location $loc | Added on $added\n\n$content';
  }
}

/// Converts a list of AmazonHighlights into My Clippings.txt text so
/// ImportService can process them without duplicating logic.
String amazonHighlightsToClippingsText(List<AmazonHighlight> highlights) {
  return highlights.map((h) => h.toClippingEntry()).join('\n==========\n');
}
