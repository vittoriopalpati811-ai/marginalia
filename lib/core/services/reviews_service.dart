// ─── Reviews service ──────────────────────────────────────────────────────────
//
// Social book reviews: a 1–5 star rating + a free-text "perché" for a book the
// reader has highlights of, with an optional attached highlight. Backed by the
// `reviews` table (see supabase/migrations/035_reviews.sql).
//
// This service is intentionally separate from SupabaseService so the reviews
// feature owns its own Supabase access. It mirrors how SupabaseService obtains
// the client and the current user id: the Supabase client is injected via the
// `supabaseClientProvider` (the same provider SupabaseService is built from in
// auth_provider.dart), and the current user id is read from
// `client.auth.currentUser?.id`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

/// A single social book review.
class Review {
  const Review({
    required this.id,
    required this.userId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.rating,
    required this.body,
    this.highlightText,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String bookTitle;
  final String bookAuthor;
  final int rating; // 1–5
  final String body; // the "perché"
  final String? highlightText; // optional attached highlight (denormalised)
  final DateTime? createdAt;

  factory Review.fromMap(Map<String, dynamic> m) {
    final createdRaw = m['created_at'] as String?;
    return Review(
      id: m['id'] as String? ?? '',
      userId: m['user_id'] as String? ?? '',
      bookTitle: m['book_title'] as String? ?? '',
      bookAuthor: m['book_author'] as String? ?? '',
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      body: m['body'] as String? ?? '',
      highlightText: (m['highlight_text'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['highlight_text'] as String?),
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ReviewsService {
  ReviewsService(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;
  bool get _isAuthenticated => _client.auth.currentUser != null;

  /// Lists the reviews written by [targetUserId] (defaults to the current
  /// user), newest first.
  Future<List<Review>> fetchReviews([String? targetUserId]) async {
    final uid = targetUserId ?? _userId;
    if (uid == null) return [];
    final rows = await _client
        .from('reviews')
        .select('id, user_id, book_title, book_author, rating, body, '
            'highlight_text, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) => Review.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Inserts a new review for the current user. Returns the created row.
  Future<Review> addReview({
    required String bookTitle,
    required String bookAuthor,
    required int rating,
    required String body,
    String? highlightText,
  }) async {
    if (!_isAuthenticated || _userId == null) {
      throw StateError('Not authenticated');
    }
    final clamped = rating.clamp(1, 5);
    final trimmedHighlight = highlightText?.trim();
    final row = await _client
        .from('reviews')
        .insert({
          'user_id': _userId,
          'book_title': bookTitle.trim(),
          'book_author': bookAuthor.trim(),
          'rating': clamped,
          'body': body.trim(),
          if (trimmedHighlight != null && trimmedHighlight.isNotEmpty)
            'highlight_text': trimmedHighlight,
        })
        .select()
        .single();
    return Review.fromMap(Map<String, dynamic>.from(row));
  }

  /// Deletes one of the current user's reviews. RLS + the explicit user_id
  /// filter ensure only the author can delete.
  Future<void> deleteReview(String reviewId) async {
    if (!_isAuthenticated || _userId == null) return;
    await _client
        .from('reviews')
        .delete()
        .eq('id', reviewId)
        .eq('user_id', _userId!);
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// Singleton service, built from the shared Supabase client provider (same
/// client SupabaseService uses — see auth_provider.dart).
final reviewsServiceProvider = Provider<ReviewsService>(
  (ref) => ReviewsService(ref.watch(supabaseClientProvider)),
);

/// The current user's reviews, newest first. autoDispose so it refreshes when
/// the profile is reopened; invalidate it after writing a review.
final myReviewsProvider = FutureProvider.autoDispose<List<Review>>((ref) async {
  final svc = ref.watch(reviewsServiceProvider);
  try {
    return await svc.fetchReviews();
  } catch (_) {
    return [];
  }
});

/// Reviews written by a specific user (for public profile views).
final userReviewsProvider =
    FutureProvider.autoDispose.family<List<Review>, String>((ref, userId) async {
  final svc = ref.watch(reviewsServiceProvider);
  try {
    return await svc.fetchReviews(userId);
  } catch (_) {
    return [];
  }
});
