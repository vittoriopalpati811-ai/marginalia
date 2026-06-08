import 'package:flutter_test/flutter_test.dart';
import 'package:scripta/core/services/amazon_sync_service.dart';
import 'package:scripta/core/parser/my_clippings_parser.dart';

// Pure-logic tests for the Kindle sync. The WebView/DOM extraction itself can't
// run off-device, but the URL/region handling, the channel-message protocol and
// the My Clippings serialisation are plain Dart — and these are exactly the
// pieces that are easy to break silently, so they're worth pinning down.

void main() {
  group('isOnNotebookPage', () {
    test('matches the notebook on any Amazon reader host', () {
      expect(AmazonSyncService.isOnNotebookPage(
          'https://read.amazon.com/notebook'), isTrue);
      expect(AmazonSyncService.isOnNotebookPage(
          'https://read.amazon.com/notebook?asin=B01'), isTrue);
      expect(AmazonSyncService.isOnNotebookPage(
          'https://leggi.amazon.it/notebook'), isTrue);
      expect(AmazonSyncService.isOnNotebookPage(
          'https://lesen.amazon.de/notebook'), isTrue);
    });

    test('does not match login / landing / store pages', () {
      expect(AmazonSyncService.isOnNotebookPage(
          'https://read.amazon.com/landing'), isFalse);
      expect(AmazonSyncService.isOnNotebookPage(
          'https://www.amazon.com/ap/signin'), isFalse);
      expect(AmazonSyncService.isOnNotebookPage(
          'https://read.amazon.com/kindle-library'), isFalse);
      expect(AmazonSyncService.isOnNotebookPage('https://example.com/notebook'),
          isFalse);
    });
  });

  group('notebookUrlForHost', () {
    test('keeps the user on the host they logged in on (region-safe)', () {
      expect(
        AmazonSyncService.notebookUrlForHost('https://leggi.amazon.it/kindle-library'),
        'https://leggi.amazon.it/notebook',
      );
      expect(
        AmazonSyncService.notebookUrlForHost('https://read.amazon.com/landing?foo=bar'),
        'https://read.amazon.com/notebook',
      );
    });

    test('falls back to the global notebook URL on null/garbage/non-Amazon', () {
      expect(AmazonSyncService.notebookUrlForHost(null),
          AmazonSyncService.notebookUrl);
      expect(AmazonSyncService.notebookUrlForHost('not a url'),
          AmazonSyncService.notebookUrl);
      expect(AmazonSyncService.notebookUrlForHost('https://example.com/x'),
          AmazonSyncService.notebookUrl);
    });

    test('global notebook URL is /notebook, not the dead /kp/notebook', () {
      expect(AmazonSyncService.notebookUrl, contains('/notebook'));
      expect(AmazonSyncService.notebookUrl, isNot(contains('/kp/notebook')));
    });
  });

  group('parseChannelMessage', () {
    test('parses a progress message', () {
      final m = AmazonSyncService.parseChannelMessage(
          '{"type":"progress","book":"Dune","total":12}');
      expect(m.type, SyncMessageType.progress);
      expect(m.book, 'Dune');
      expect(m.total, 12);
    });

    test('parses a done message into highlights, dropping empties', () {
      final m = AmazonSyncService.parseChannelMessage(
          '{"type":"done","highlights":['
          '{"bookTitle":"Dune","bookAuthor":"Herbert","content":"Fear is the mind-killer","location":"42","color":"yellow"},'
          '{"bookTitle":"Dune","bookAuthor":"Herbert","content":"   ","location":"43"}'
          ']}');
      expect(m.type, SyncMessageType.done);
      expect(m.highlights, isNotNull);
      expect(m.highlights!.length, 1); // blank-content one dropped
      expect(m.highlights!.first.content, 'Fear is the mind-killer');
      expect(m.highlights!.first.location, '42');
      expect(m.highlights!.first.color, 'yellow');
    });

    test('parses an error message', () {
      final m = AmazonSyncService.parseChannelMessage(
          '{"type":"error","error":"NO_BOOKS"}');
      expect(m.type, SyncMessageType.error);
      expect(m.error, 'NO_BOOKS');
    });

    test('malformed JSON degrades to an error message, never throws', () {
      final m = AmazonSyncService.parseChannelMessage('not json at all');
      expect(m.type, SyncMessageType.error);
      expect(m.error, isNotNull);
    });
  });

  group('clippings serialisation round-trips through the real parser', () {
    test('extracted highlights parse back into the import pipeline', () {
      final highlights = [
        const AmazonHighlight(
          bookTitle: 'The Great Gatsby',
          bookAuthor: 'F. Scott Fitzgerald',
          content: 'So we beat on, boats against the current.',
          location: '342',
          color: 'yellow',
        ),
        const AmazonHighlight(
          bookTitle: 'Sapiens',
          bookAuthor: 'Yuval Noah Harari',
          content: 'Money is the most universal system of mutual trust.',
          location: '1200',
        ),
      ];

      final text = amazonHighlightsToClippingsText(highlights);
      final parsed = MyClippingsParser().parse(text);

      expect(parsed.length, 2);
      expect(parsed.map((c) => c.content),
          containsAll(highlights.map((h) => h.content)));
      // Title/author survive the My Clippings "Title (Author)" round-trip.
      expect(parsed.any((c) => c.bookTitle == 'The Great Gatsby'), isTrue);
      expect(parsed.any((c) => c.bookTitle == 'Sapiens'), isTrue);
    });

    test('a missing author still produces a parseable entry', () {
      final text = amazonHighlightsToClippingsText([
        const AmazonHighlight(
          bookTitle: 'Untitled Notebook',
          bookAuthor: '',
          content: 'A lonely thought.',
          location: '1',
        ),
      ]);
      final parsed = MyClippingsParser().parse(text);
      expect(parsed.length, 1);
      expect(parsed.first.content, 'A lonely thought.');
    });
  });
}
