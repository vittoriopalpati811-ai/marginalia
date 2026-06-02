import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ─── AmazonSyncService ────────────────────────────────────────────────────────
//
// Extracts highlights from read.amazon.com/kp/notebook via DOM injection.
// Same approach used by Readwise, Obsidian, and all Kindle sync tools —
// the user logs into their own Amazon page; we never see credentials.
//
// HOT-FIX MECHANISM:
// The JS extractor is fetched from Supabase at runtime (table: amazon_sync_scripts).
// If the fetch fails the compiled-in _fallbackExtractorJs is used.
// To fix a broken Amazon sync without an App Store release:
//   UPDATE amazon_sync_scripts SET script = '<new JS>', updated_at = now()
//   WHERE is_active = true;

class AmazonSyncService {
  static const String notebookUrl = 'https://read.amazon.com/kp/notebook';

  // Entry URL loaded FIRST so the user signs into Amazon. Loading the notebook
  // directly shows Amazon's "Sorry, we couldn't find that page" when the WebView
  // isn't authenticated yet; starting at the Cloud Reader lets Amazon handle the
  // sign-in, then the user taps the button to navigate to the (now authenticated)
  // notebook and extract.
  static const String entryUrl = 'https://read.amazon.com';

  // Cache keys stored in a simple in-memory map (cleared on app restart).
  // For persistence across launches use shared_preferences — add the package
  // and replace this map with prefs.getString / prefs.setString calls.
  static String? _cachedScript;
  static int?    _cachedVersion;

  // ── Compiled-in fallback (always works offline) ───────────────────────────

  static const String _fallbackExtractorJs = r"""
(function() {
  const results = [];

  const sections = document.querySelectorAll('#kp-notebook-annotations .a-section');

  sections.forEach(function(section) {
    const titleEl = section.querySelector('h2.kp-notebook-searchable, .kp-notebook-lib-title');
    const authorEl = section.querySelector('.kp-notebook-metadata .a-color-secondary');
    if (!titleEl) return;

    const bookTitle = (titleEl.innerText || '').trim();
    const bookAuthor = authorEl ? (authorEl.innerText || '').replace(/^by\s+/i, '').trim() : '';

    const highlightBlocks = section.querySelectorAll('[id^="highlight-"]');

    highlightBlocks.forEach(function(hlBlock) {
      const contentEl = hlBlock.querySelector('.kp-notebook-highlight');
      const locationEl = hlBlock.querySelector('.kp-notebook-highlight-location, .kp-notebook-metadata');
      const colorMatch = hlBlock.className.match(/kp-notebook-highlight-(\w+)/);
      const colorAttr = hlBlock.getAttribute('data-highlight-color') || (colorMatch ? colorMatch[1] : null);

      if (!contentEl) return;
      const content = (contentEl.innerText || '').trim();
      if (!content) return;

      const locationText = locationEl ? (locationEl.innerText || '') : '';
      const locationMatch = locationText.match(/(?:location|posizione)\s+([\d\-]+)/i);

      results.push({
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        content: content,
        location: locationMatch ? locationMatch[1] : null,
        color: colorAttr || null
      });
    });
  });

  if (results.length === 0 && sections.length > 0) {
    throw new Error('SELECTOR_MISMATCH: ' + sections.length + ' sections, 0 highlights. Amazon DOM may have changed.');
  }

  return JSON.stringify(results);
})();
""";

  // ── Script fetching ───────────────────────────────────────────────────────

  /// Returns the active extractor JS.
  /// Tries Supabase first; falls back to the compiled-in script on any error.
  static Future<String> _fetchScript() async {
    // Return in-memory cache if available.
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
      final script  = row['script']  as String?;

      if (script != null && script.isNotEmpty) {
        _cachedVersion = version;
        _cachedScript  = script;
        if (kDebugMode) {
          debugPrint('[AmazonSync] Using remote JS v$version from Supabase');
        }
        return script;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AmazonSync] Remote JS fetch failed: $e — using fallback');
      }
    }

    return _fallbackExtractorJs;
  }

  /// Clears the in-memory cache so the next sync re-fetches from Supabase.
  /// Call this if you want to force a script refresh.
  static void invalidateScriptCache() {
    _cachedScript  = null;
    _cachedVersion = null;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Checks whether the WebView is currently on the notebook page (post-login).
  static bool isOnNotebookPage(String currentUrl) {
    return currentUrl.contains('read.amazon.com/kp/notebook');
  }

  /// Runs the extractor on the given WebViewController and returns parsed highlights.
  /// Throws a descriptive error if extraction fails (SELECTOR_MISMATCH, JSON parse error, etc.).
  static Future<List<AmazonHighlight>> extractHighlights(
      WebViewController controller) async {
    final script = await _fetchScript();

    final rawResult = await controller.runJavaScriptReturningResult(script);

    // runJavaScriptReturningResult wraps strings in double quotes on some platforms.
    String jsonStr = rawResult.toString();
    if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
      jsonStr = jsonDecode(jsonStr) as String;
    }

    if (jsonStr.contains('SELECTOR_MISMATCH')) {
      // Amazon changed their DOM — invalidate cache so next attempt re-fetches
      // the latest script from Supabase.
      invalidateScriptCache();
      throw Exception('Amazon has updated their site. Please try again in a few minutes — '
          'we are already working on a fix.');
    }

    final List<dynamic> parsed = jsonDecode(jsonStr) as List<dynamic>;
    return parsed
        .map((item) => AmazonHighlight.fromJson(item as Map<String, dynamic>))
        .toList();
  }
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
      bookTitle:  json['bookTitle']  as String? ?? '',
      bookAuthor: json['bookAuthor'] as String? ?? '',
      content:    json['content']    as String? ?? '',
      location:   json['location']   as String?,
      color:      json['color']      as String?,
    );
  }

  /// Converts to My Clippings.txt format so ImportService can process it
  /// without duplicating parsing logic.
  String toClippingEntry() {
    final dateLine =
        '- Your Highlight on location ${location ?? '0'} | Added on ${DateTime.now()}';
    return '$bookTitle ($bookAuthor)\n$dateLine\n\n$content';
  }
}

/// Converts a list of AmazonHighlights into My Clippings.txt text
/// so ImportService can process them without duplication of logic.
String amazonHighlightsToClippingsText(List<AmazonHighlight> highlights) {
  return highlights.map((h) => h.toClippingEntry()).join('\n==========\n');
}
