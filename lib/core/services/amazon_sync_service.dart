import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Extracts highlights from read.amazon.com/kp/notebook via DOM injection.
// This is the same approach used by Readwise, Obsidian, and all Kindle
// sync tools — the user logs into their own Amazon page, we never see credentials.
class AmazonSyncService {
  static const String notebookUrl =
      'https://read.amazon.com/kp/notebook';

  // Injected into the page after login to extract all highlights.
  // Returns JSON: List<{bookTitle, bookAuthor, content, location, color}>
  static const String _extractorJs = r"""
(function() {
  const results = [];

  // Each book section in the notebook
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
      const colorAttr = hlBlock.getAttribute('data-highlight-color') || hlBlock.className.match(/kp-notebook-highlight-(\w+)/)?.[1];

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

  return JSON.stringify(results);
})();
""";

  // Checks whether the WebView is currently on the notebook page (post-login)
  static bool isOnNotebookPage(String currentUrl) {
    return currentUrl.contains('read.amazon.com/kp/notebook');
  }

  // Run the extractor on the given WebViewController and return parsed highlights.
  // Throws if the page is not the notebook page or if extraction fails.
  static Future<List<AmazonHighlight>> extractHighlights(
      WebViewController controller) async {
    final rawResult = await controller.runJavaScriptReturningResult(_extractorJs);

    // runJavaScriptReturningResult wraps strings in quotes on some platforms
    String jsonStr = rawResult.toString();
    if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
      jsonStr = jsonDecode(jsonStr) as String;
    }

    final List<dynamic> parsed = jsonDecode(jsonStr) as List<dynamic>;
    return parsed
        .map((item) => AmazonHighlight.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

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

  // Convert to the raw text format that MyClippingsParser can handle,
  // so we can reuse the same import pipeline.
  String toClippingEntry() {
    final dateLine =
        '- Your Highlight on location ${location ?? '0'} | Added on ${DateTime.now()}';
    return '$bookTitle ($bookAuthor)\n$dateLine\n\n$content';
  }
}

// Converts a list of AmazonHighlights into My Clippings.txt format
// so ImportService can process them without duplication of logic.
String amazonHighlightsToClippingsText(List<AmazonHighlight> highlights) {
  return highlights.map((h) => h.toClippingEntry()).join('\n==========\n');
}
