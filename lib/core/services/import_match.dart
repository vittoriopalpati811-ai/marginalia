// ─── What counts as "the same book" and "the same highlight" ─────────────────
//
// The importer used to answer both questions with exact string equality, and
// that was quietly wrong in production: one real account holds "Il nome della
// rosa" with 5 highlights AND "Il Nome della Rosa" with 21 — the same book,
// twice on the shelf, because a capital letter differed between two imports.
//
// The two doors into the library disagree by construction:
//
//   My Clippings.txt   →  "Il nome della rosa (Eco, Umberto)"   loc "1234-1236"
//   Kindle web sync    →  "Il nome della rosa" / "Umberto Eco"  loc "1234"
//
// Author order, capitalisation and location shape all differ, so the same
// highlight arrived as a different book AND a different highlight. That was
// survivable while syncing was something you chose to do; it stopped being
// survivable when the sync started running by itself every six hours.
//
// Everything here is a pure function of its inputs, so the phone, the cloud
// backup and the tests can never disagree about what is a duplicate.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Collapses runs of whitespace and trims. Kindle pads titles inconsistently
/// between the notebook page and the clippings file.
String _tidy(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// A title reduced to what identifies it. Case and spacing only — the stored
/// title keeps whatever the reader first saw, because rewriting someone's
/// library to lowercase to make a lookup easier would be a poor trade.
String normalizedTitle(String title) => _tidy(title).toLowerCase();

/// An author reduced to a set of words, ORDER REMOVED.
///
/// This is what makes "Eco, Umberto" and "Umberto Eco" the same person, which
/// is the single biggest source of duplicate books: the clippings file writes
/// surname-first and the web notebook writes it the natural way round.
/// Sorting the words also absorbs "de Saint-Exupéry, Antoine" vs "Antoine de
/// Saint-Exupéry". Two different people cannot collide here without being
/// anagram-level identical, which in practice means they are the same person.
String normalizedAuthor(String author) {
  final cleaned = _tidy(author)
      .toLowerCase()
      .replaceAll(RegExp(r'[.,;]'), ' ');
  final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList()..sort();
  return words.join(' ');
}

/// The identity of a book for matching purposes. Never displayed.
String bookMatchKey(String title, String author) =>
    '${normalizedTitle(title)}|${normalizedAuthor(author)}';

/// A quote reduced to its words. Kindle re-flows punctuation and whitespace
/// between the two export paths; the words are what the reader recognises.
String normalizedContent(String content) => _tidy(content)
    .toLowerCase()
    // Curly quotes and straight quotes are the same punctuation; Kindle uses
    // one in the clippings file and the other on the notebook page, and no
    // reader would call those two different sentences.
    .replaceAll(RegExp(r'[‘’]'), "'")
    .replaceAll(RegExp(r'[“”]'), '"');

/// Where a highlight starts, as a bare number.
///
/// "1234-1236" and "1234" are the same starting point written by two different
/// exporters. Only ever used TOGETHER with a content check — a location alone
/// is not enough to call two quotes the same, because two genuinely different
/// highlights can begin at the same place.
String? locationStart(String? location) {
  if (location == null) return null;
  final m = RegExp(r'\d+').firstMatch(location);
  return m?.group(0);
}

/// A stable fallback identity for a highlight Amazon reports with no location.
///
/// Deliberately NOT `String.hashCode`: Dart does not promise that value is
/// stable across SDK releases, and this one is PERSISTED and compared on every
/// later sync. A hash that shifted under a Flutter upgrade would re-import a
/// reader's whole locationless library exactly once — silently, and for good.
String contentFingerprint(String content) =>
    sha1.convert(utf8.encode(normalizedContent(content))).toString().substring(0, 16);

/// Are these two highlights of the same book the same highlight?
///
/// Two rules, and the order matters:
///
///   1. Identical text is the same highlight, whatever the locations say. This
///      is what catches the clippings-vs-sync case, where the quote is
///      character-for-character equal but the location is "1234-1236" in one
///      and "1234" in the other.
///   2. Same starting location AND one text contains the other is the same
///      highlight, extended. Kindle really does re-issue a highlight with more
///      text around it, and that is the case the "keep the longer one" rule
///      exists for.
///
/// Anything else is treated as two different highlights. That asymmetry is
/// deliberate: a duplicate is an annoyance a reader can see and complain about,
/// while a wrongly merged highlight is a sentence of theirs that quietly
/// disappears — so this errs towards keeping both.
bool isSameHighlight({
  required String? locationA,
  required String contentA,
  required String? locationB,
  required String contentB,
}) {
  final a = normalizedContent(contentA);
  final b = normalizedContent(contentB);
  if (a == b) return true;

  final la = locationStart(locationA);
  final lb = locationStart(locationB);
  if (la != null && la == lb && (a.contains(b) || b.contains(a))) return true;

  return false;
}
