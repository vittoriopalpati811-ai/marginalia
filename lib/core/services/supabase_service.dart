import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book.dart';
import '../models/highlight.dart';

/// Thrown when an image upload is rejected by server-side content moderation
/// (the moderate-image edge function flagged it as NSFW / gore / violent).
class ImageModerationException implements Exception {
  const ImageModerationException();
}

// Thin wrapper around Supabase client. Encapsulates table names and RLS
// assumptions so screens don't need to know the schema.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  // Short-lived cache of the current user's blocked-user IDs. Feed/conversation
  // fetches call [fetchBlockedUserIds] which hits this cache to avoid querying
  // blocked_users on every list load. Invalidated on block/unblock and after a
  // brief TTL so a block elsewhere (other device) is picked up within seconds.
  Set<String>? _blockedIdsCache;
  DateTime? _blockedIdsFetchedAt;
  static const _blockedIdsTtl = Duration(seconds: 30);

  User? get currentUser => _client.auth.currentUser;
  String? get userId => _client.auth.currentUser?.id;
  bool get isAuthenticated => _client.auth.currentUser != null;

  /// Exposed for Realtime channel subscriptions.
  SupabaseClient get client => _client;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<AuthResponse> signInWithEmail(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUpWithEmail(String email, String password) =>
      _client.auth.signUp(email: email, password: password);

  /// The APNs token most recently registered for THIS device, cached so it can
  /// be removed from `device_tokens` on sign-out — closing the cross-account
  /// push leak when two accounts are used on the same device.
  String? _currentDeviceToken;

  Future<void> signOut() async {
    // Remove THIS device's push token for the current account BEFORE the session
    // is torn down — RLS authorizes the delete only while still signed in. This
    // stops a different account that signs in next on the SAME device from
    // receiving the previous user's pushes. Best-effort; never blocks sign-out.
    final token = _currentDeviceToken;
    final uid = _client.auth.currentUser?.id;
    if (token != null && uid != null) {
      try {
        await _client
            .from('device_tokens')
            .delete()
            .eq('user_id', uid)
            .eq('token', token);
      } catch (_) {
        // best-effort
      }
    }
    _currentDeviceToken = null;
    await _client.auth.signOut();
  }

  // ─── OAuth providers ──────────────────────────────────────────────────────
  //
  // Apple & Google are configured in the Supabase dashboard
  // (Authentication → Providers). signInWithOAuth opens the provider's
  // consent page; on web it redirects, on iOS it uses the in-app browser.
  // The session is restored automatically via the deep-link / redirect URL.
  //
  // For native iOS, also set the URL scheme `io.supabase.flutter` in
  // ios/Runner/Info.plist (CFBundleURLSchemes). The web build uses the
  // current origin as the redirect.

  /// Initiates Sign in with Apple. Returns true if the redirect started.
  Future<bool> signInWithApple() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      // On web, return to the same page (Supabase parses the hash).
      // On native, the SDK handles deep-link redirect automatically.
      redirectTo: null,
    );
  }

  /// Initiates Sign in with Google.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: null,
    );
  }

  /// Pre-flight check: is the given OAuth provider actually configured in
  /// the Supabase dashboard?
  ///
  /// Without this, calling `signInWithOAuth` for a provider whose credentials
  /// haven't been entered yet redirects the browser to a Supabase JSON error
  /// page ("Unsupported provider: provider is not enabled") — exposing the
  /// raw JSON to the user. By hitting `/auth/v1/settings` first we can show
  /// a friendly inline message and never navigate away.
  ///
  /// Returns `true` only if Supabase reports the provider as enabled.
  /// On network failures we return `true` to fall back to the existing
  /// behaviour (so a transient settings-endpoint hiccup doesn't block real
  /// users who *do* have a configured provider).
  Future<bool> isOAuthProviderEnabled(String provider) async {
    try {
      // _client.rest.url is the PostgREST endpoint, e.g.
      //   https://<project>.supabase.co/rest/v1
      // Strip the suffix to get the project root and append the auth path.
      final restUrl = _client.rest.url.toString();
      final base    = restUrl.replaceAll(RegExp(r'/rest/v1/?$'), '');
      final url     = Uri.parse('$base/auth/v1/settings');
      final apikey  = _client.rest.headers['apikey'] ?? '';
      final resp    = await http
          .get(url, headers: {'apikey': apikey})
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return true; // fall back — don't block
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final ext  = data['external'] as Map<String, dynamic>?;
      final flag = ext?[provider];
      // Supabase returns false when the provider has no credentials yet.
      return flag is bool ? flag : true;
    } catch (_) {
      return true; // network error → assume enabled and let upstream surface
    }
  }

  // ─── Phone OTP ────────────────────────────────────────────────────────────
  //
  // Two-step: send the OTP, then verify it. Requires an SMS provider
  // (Twilio / MessageBird / etc.) configured in Supabase
  // Authentication → Phone Auth.

  /// Sends a one-time code via SMS to the given E.164 phone number
  /// (e.g. "+391234567890").
  Future<void> sendPhoneOtp(String phoneE164) {
    return _client.auth.signInWithOtp(phone: phoneE164);
  }

  /// Verifies the SMS code and signs the user in.
  Future<AuthResponse> verifyPhoneOtp({
    required String phoneE164,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phoneE164,
      token: token,
    );
  }

  /// Confirms a freshly-signed-up email by verifying the 6-digit code Supabase
  /// emailed the user. Requires the "Confirm signup" email template to include
  /// `{{ .Token }}`. On success the returned [AuthResponse] carries an
  /// authenticated session, flipping the user into the signed-in state.
  ///
  /// Typing the code is deliberately preferred over the magic link: a link must
  /// round-trip through Safari + a deep link / web redirect (fragile on a fresh
  /// install), whereas the OTP is verified directly against Supabase — no
  /// redirect, no allow-list, nothing to misconfigure.
  Future<AuthResponse> verifyEmailSignupOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email,
      token: token,
    );
  }

  /// Re-sends the signup confirmation email (fresh 6-digit code + link). Rate
  /// limited server-side by Supabase; the UI also enforces a local cooldown.
  Future<void> resendSignupOtp(String email) {
    return _client.auth.resend(type: OtpType.signup, email: email);
  }

  /// Permanently deletes the current user's account and all their data.
  /// Calls the delete_my_account() RPC (migration 025) which cascades
  /// deletes through FK relationships in auth.users, then signs out.
  Future<void> deleteAccount() async {
    await _client.rpc('delete_my_account');
    await _client.auth.signOut();
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ─── Books ────────────────────────────────────────────────────────────────

  Future<void> upsertBook(Book book) async {
    await _client.from('books').upsert({
      'id': book.supabaseId,
      'user_id': userId,
      'title': book.title,
      'author': book.author,
      'cover_url': book.coverUrl,
      'last_synced_at': book.lastSyncedAt?.toIso8601String(),
    });
  }

  /// Lightweight remote sync of just a book's cover URL (by Supabase id), used
  /// by the cover editor so it doesn't depend on the platform-specific Book
  /// type. Best-effort: the local Isar cover is authoritative.
  Future<void> setBookCoverUrl(String supabaseId, String? coverUrl) async {
    if (!isAuthenticated || supabaseId.isEmpty || userId == null) return;
    await _client
        .from('books')
        .update({'cover_url': coverUrl})
        .eq('id', supabaseId)
        .eq('user_id', userId!);
  }

  Future<void> upsertRawBook({
    required String id,
    required String userId,
    required String title,
    required String author,
  }) async {
    await _client.from('books').upsert({
      'id': id,
      'user_id': userId,
      'title': title,
      'author': author,
    });
  }

  Future<void> upsertRawHighlight({
    required String id,
    required String userId,
    required String bookId,
    required String content,
    String? location,
    DateTime? addedAt,
    String? color,
  }) async {
    // Hash MUST include bookId — the unique constraint on
    // (user_id, content_hash) treats the highlight as a duplicate
    // otherwise, so the same memorable quote (e.g. "Tutto cambia
    // perché nulla cambi") appearing in two different books would
    // collide and the second import would fail. The original schema
    // comment in migration 001 explicitly says "sha256(book_id || content)";
    // the previous code shipped sha256(content) by mistake. The
    // user's 1000-highlight test surfaced this: 170 ok, 830 errors.
    final hash = sha256
        .convert(utf8.encode('$bookId $content'))
        .toString();
    await _client.from('highlights').upsert({
      'id': id,
      'user_id': userId,
      'book_id': bookId,
      'content': content,
      'content_hash': hash,
      'location': location,
      'added_at': addedAt?.toIso8601String(),
      'color': color,
      'is_favorite': false,
    });
  }

  Future<List<Map<String, dynamic>>> fetchBooks() async {
    final response = await _client
        .from('books')
        .select()
        .eq('user_id', userId!)
        .order('title');
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── Highlights ───────────────────────────────────────────────────────────

  Future<void> upsertHighlight(Highlight highlight, String bookSupabaseId) async {
    await _client.from('highlights').upsert({
      'id': highlight.supabaseId,
      'user_id': userId,
      'book_id': bookSupabaseId,
      'content': highlight.content,
      'note': highlight.note,
      'location': highlight.location,
      'added_at': highlight.addedAt?.toIso8601String(),
      'color': highlight.color,
      'is_favorite': highlight.isFavorite,
    });
  }

  Future<void> updateHighlightFavorite(String highlightId, bool isFavorite) async {
    await _client
        .from('highlights')
        .update({'is_favorite': isFavorite})
        .eq('id', highlightId)
        .eq('user_id', userId!);
  }

  Future<List<Map<String, dynamic>>> fetchHighlights({String? bookId}) async {
    var query = _client
        .from('highlights')
        .select('*, books(title, author)')
        .eq('user_id', userId!);
    if (bookId != null) {
      query = query.eq('book_id', bookId);
    }
    final response = await query.order('added_at', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── Jams ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createJam(String title) async {
    final response = await _client.from('jams').insert({
      'title': title,
      'owner_id': userId,
    }).select().single();
    return response;
  }

  Future<List<Map<String, dynamic>>> fetchMyJams() async {
    // Fetch jams owned by user
    final owned = List<Map<String, dynamic>>.from(
      await _client
          .from('jams')
          .select()
          .eq('owner_id', userId!)
          .order('created_at', ascending: false) as List,
    );

    // Fetch jam IDs where user is a member (but not owner)
    final memberRows = List<Map<String, dynamic>>.from(
      await _client
          .from('jam_members')
          .select('jam_id')
          .eq('user_id', userId!) as List,
    );

    final ownedIds = owned.map((r) => r['id'] as String).toSet();
    final memberOnlyIds = memberRows
        .map((r) => r['jam_id'] as String)
        .where((id) => !ownedIds.contains(id))
        .toList();

    if (memberOnlyIds.isEmpty) return owned;

    final memberJams = List<Map<String, dynamic>>.from(
      await _client
          .from('jams')
          .select()
          .inFilter('id', memberOnlyIds)
          .order('created_at', ascending: false) as List,
    );

    return [...owned, ...memberJams];
  }

  Future<Map<String, dynamic>?> fetchJam(String jamId) async {
    return await _client.from('jams').select().eq('id', jamId).maybeSingle();
  }

  Future<Map<String, dynamic>?> fetchJamByInviteCode(String code) async {
    final response = await _client
        .from('jams')
        .select()
        .eq('invite_code', code)
        .maybeSingle();
    return response;
  }

  Future<void> joinJam(String jamId) async {
    await _client.from('jam_members').upsert({
      'jam_id': jamId,
      'user_id': userId,
      'role': 'member',
    });
  }

  Future<void> leaveJam(String jamId) async {
    await _client
        .from('jam_members')
        .delete()
        .eq('jam_id', jamId)
        .eq('user_id', userId!);
  }

  Future<void> shareHighlightInJam(String jamId, String highlightId) async {
    await _client.from('jam_highlights').upsert({
      'jam_id': jamId,
      'highlight_id': highlightId,
      'shared_by': userId,
    });
  }

  Future<List<Map<String, dynamic>>> fetchJamHighlights(String jamId) async {
    final response = await _client
        .from('jam_highlights')
        .select('''
          *,
          highlights(content, color, books(title, author)),
          profiles(display_name)
        ''')
        .eq('jam_id', jamId)
        .order('shared_at', ascending: false)
        .limit(200); // cap the jam feed (newest 200) — avoid loading everything
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── Reactions & Comments (Jam interaction) ───────────────────────────────

  Future<List<Map<String, dynamic>>> fetchReactions(String jamHighlightId) async {
    final response = await _client
        .from('jam_highlight_reactions')
        .select('emoji, user_id, created_at')
        .eq('jam_highlight_id', jamHighlightId);
    return List<Map<String, dynamic>>.from(response as List);
  }

  // Toggles reaction: if user has this emoji on this highlight, remove it; else add it.
  Future<void> toggleReaction(String jamHighlightId, String emoji) async {
    final existing = await _client
        .from('jam_highlight_reactions')
        .select('id')
        .eq('jam_highlight_id', jamHighlightId)
        .eq('user_id', userId!)
        .eq('emoji', emoji)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from('jam_highlight_reactions')
          .delete()
          .eq('id', existing['id'] as String);
    } else {
      await _client.from('jam_highlight_reactions').insert({
        'jam_highlight_id': jamHighlightId,
        'user_id': userId,
        'emoji': emoji,
      });
    }
  }

  Future<List<Map<String, dynamic>>> fetchComments(String jamHighlightId) async {
    final response = await _client
        .from('jam_highlight_comments')
        .select('*, profiles(display_name)')
        .eq('jam_highlight_id', jamHighlightId)
        .order('created_at', ascending: true);
    final rows = List<Map<String, dynamic>>.from(response as List);

    // Hide comments authored by users I've blocked.
    final blockedIds = await fetchBlockedUserIds();
    if (blockedIds.isNotEmpty) {
      rows.removeWhere(
          (r) => blockedIds.contains(r['user_id'] as String? ?? ''));
    }
    return rows;
  }

  Future<void> addComment(String jamHighlightId, String content,
      {String? imageUrl}) async {
    await _client.from('jam_highlight_comments').insert({
      'jam_highlight_id': jamHighlightId,
      'user_id': userId,
      'content': content,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  /// Uploads an image for a comment and returns the public URL.
  Future<String> uploadCommentImage(Uint8List bytes, String ext) async {
    await _ensureBucket('comment-images');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${userId!}/$ts.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('comment-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    return _client.storage.from('comment-images').getPublicUrl(path);
  }

  Future<void> deleteComment(String commentId) async {
    await _client
        .from('jam_highlight_comments')
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId!);
  }

  // ─── Profile ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> fetchProfile([String? id]) async {
    final target = id ?? userId;
    if (target == null) return null;
    return await _client
        .from('profiles')
        .select()
        .eq('id', target)
        .maybeSingle();
  }

  // ─── Book notes ───────────────────────────────────────────────────────────

  /// Fetches the personal note for a recommended book, or null if none.
  Future<String?> fetchBookNote({
    required String title,
    required String author,
  }) async {
    final uid = userId;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('book_notes')
          .select('notes')
          .eq('user_id', uid)
          .eq('book_title', title)
          .eq('book_author', author)
          .maybeSingle();
      return res?['notes'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Saves (upserts) a personal note for a recommended book.
  Future<void> saveBookNote({
    required String title,
    required String author,
    required String notes,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await _client.from('book_notes').upsert(
      {
        'user_id':     uid,
        'book_title':  title,
        'book_author': author,
        'notes':       notes,
        'updated_at':  DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,book_title,book_author',
    );
  }

  // ─── Reading goals ────────────────────────────────────────────────────────

  /// Returns the user's reading goal for the given year, or null.
  Future<int?> fetchReadingGoal({required int year}) async {
    final uid = userId;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('reading_goals')
          .select('target_books')
          .eq('user_id', uid)
          .eq('year', year)
          .maybeSingle();
      return res?['target_books'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Upserts the user's reading goal for the given year.
  Future<void> saveReadingGoal({
    required int year,
    required int targetBooks,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await _client.from('reading_goals').upsert(
      {
        'user_id':      uid,
        'year':         year,
        'target_books': targetBooks,
        'updated_at':   DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,year',
    );
  }

  // ─── Reading sessions ─────────────────────────────────────────────────────

  /// Inserts a reading session.
  /// Either pass a `bookId` (preferred) or denormalized `title`/`author`.
  Future<void> addReadingSession({
    String? bookId,
    String? title,
    String? author,
    required int minutes,
    int? pages,
    DateTime? sessionDate,
    DateTime? startedAt,
    DateTime? endedAt,
    String source = 'manual',
    String? note,
  }) async {
    final uid = userId;
    if (uid == null) return;
    await _client.from('reading_sessions').insert({
      'user_id':      uid,
      'book_id':      bookId,
      'book_title':   title,
      'book_author':  author,
      'session_date': (sessionDate ?? DateTime.now()).toIso8601String().split('T').first,
      'started_at':   startedAt?.toIso8601String(),
      'ended_at':     endedAt?.toIso8601String(),
      'minutes_read': minutes,
      'pages_read':   pages,
      'source':       source,
      'note':         note,
    });
  }

  /// Re-derives reading sessions from the user's highlights:
  ///   • One session per (book, day-of-highlight)
  ///   • Estimated minutes = clamp(highlight_count × 8, 10, 240)
  ///   • Marked `source = 'inferred'` so the UI can label it "stimato"
  ///   • Manual sessions for the same (book, date) are preserved
  ///
  /// Called automatically after every My Clippings import. Returns the
  /// number of inferred sessions created (0 on error).
  Future<int> inferReadingSessionsFromHighlights() async {
    try {
      final res = await _client.rpc('infer_reading_sessions_from_highlights');
      if (res is int) return res;
      if (res is num) return res.toInt();
      return 0;
    } catch (e) {
      // Non-fatal: stats just won't be auto-populated this round.
      // ignore: avoid_print
      print('[inferReadingSessions] $e');
      return 0;
    }
  }

  /// Lists the user's reading sessions, newest first.
  Future<List<Map<String, dynamic>>> fetchReadingSessions({int limit = 200}) async {
    final uid = userId;
    if (uid == null) return [];
    try {
      final res = await _client
          .from('reading_sessions')
          .select('id, book_id, book_title, book_author, session_date, '
              'started_at, ended_at, minutes_read, pages_read, source, note')
          .eq('user_id', uid)
          .order('session_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (_) {
      return [];
    }
  }

  /// Delete all highlights and books for the current user.
  /// Used by "force reimport" to clear corrupted data before re-upload.
  Future<void> deleteAllUserData() async {
    final uid = userId!;
    await _client.from('highlights').delete().eq('user_id', uid);
    await _client.from('books').delete().eq('user_id', uid);
  }

  Future<void> updateCurrentlyReading({String? title, String? author}) async {
    await _client.from('profiles').update({
      'currently_reading_title': title,
      'currently_reading_author': author,
    }).eq('id', userId!);
  }

  Future<List<Map<String, dynamic>>> fetchJamMembers(String jamId) async {
    final memberRows = List<Map<String, dynamic>>.from(
      await _client
          .from('jam_members')
          .select('user_id, role, joined_at')
          .eq('jam_id', jamId) as List,
    );
    if (memberRows.isEmpty) return [];
    final ids = memberRows.map((r) => r['user_id'] as String).toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
          .from('profiles')
          .select('id, display_name, currently_reading_title, currently_reading_author')
          .inFilter('id', ids) as List,
    );
    final profileById = {for (var p in profiles) p['id'] as String: p};
    return [
      for (var m in memberRows)
        {
          ...m,
          'profile': profileById[m['user_id']],
        }
    ];
  }

  // ─── Jam review competition (Ripasso leaderboard) ─────────────────────────

  /// The Ripasso leaderboard for [jamId]: one row per jam member with their
  /// streak snapshot, ordered by current streak desc. Backed by the
  /// `jam_review_leaderboard` SECURITY DEFINER RPC (migration 051), which is
  /// self-guarded so only a member of that jam gets rows.
  ///
  /// Each row carries: `id`, `display_name`, `avatar_url`, `review_streak`,
  /// `review_best_streak`, `last_reviewed_on`, `reviewed_today` (bool, computed
  /// server-side against current_date).
  Future<List<Map<String, dynamic>>> fetchJamReviewLeaderboard(
    String jamId,
  ) async {
    final res = await _client.rpc(
      'jam_review_leaderboard',
      params: {'p_jam_id': jamId},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Best-effort APNs push to the caller's jam-mates when they finish today's
  /// review. Reads the recipient ids from the `jam_mates_for_review` RPC (the
  /// DISTINCT other members across every jam the caller belongs to), then fans
  /// out one `send-push-notification` invocation per recipient — mirroring the
  /// [_notifyConversationMembers] pattern. Fire-and-forget: never throws, so it
  /// can never affect the offline review loop.
  Future<void> notifyJamMatesReviewDone() async {
    try {
      if (!isAuthenticated || userId == null) return;

      final mates = await _client.rpc('jam_mates_for_review') as List;
      if (mates.isEmpty) return;

      // Resolve the caller's display name for the push body.
      final me = await fetchProfile();
      final name =
          (me?['display_name'] as String?)?.trim().isNotEmpty == true
              ? (me!['display_name'] as String).trim()
              : 'A jam-mate';

      for (final row in mates) {
        final uid = (row as Map)['user_id'] as String?;
        if (uid == null || uid == userId) continue;
        await _client.functions.invoke(
          'send-push-notification',
          body: {
            'user_id': uid,
            'title': 'Ripasso completato',
            'body': "$name finished today's review",
            'data': {'type': 'jam_review'},
          },
        );
      }
    } catch (_) {
      // Push is best-effort; a failure must never affect the review loop.
    }
  }

  // ─── Follows ──────────────────────────────────────────────────────────────

  /// Follow another user (idempotent upsert).
  Future<void> followUser(String targetId) async {
    await _client.from('follows').upsert({
      'follower_id': userId,
      'following_id': targetId,
    });
    // Best-effort in-app notification for the user who just got followed. The
    // notify_new_follow RPC (migration 054) is SECURITY DEFINER: it derives the
    // recipient + actor server-side and verifies the follow really exists, so a
    // failure here must never block the follow itself.
    if (targetId != userId) {
      unawaited(_notifyNewFollow(targetId));
    }
  }

  /// Fire-and-forget call to the notify_new_follow RPC + APNs push. Swallows
  /// every error — a missing notification is cosmetic; the follow succeeded.
  Future<void> _notifyNewFollow(String targetId) async {
    try {
      await _client.rpc('notify_new_follow', params: {
        'p_following_id': targetId,
      });
    } catch (_) {
      // Ignore — never surface to the user.
    }
    try {
      await _client.functions.invoke('send-push-notification', body: {
        'mode': 'follow',
        'following_id': targetId,
      });
    } catch (_) {
      // Push is best-effort; the in-app notification already landed.
    }
  }

  /// Stop following a user.
  Future<void> unfollowUser(String targetId) async {
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', userId!)
        .eq('following_id', targetId);
  }

  /// Profiles of users I follow, with their reading status.
  Future<List<Map<String, dynamic>>> fetchFollowing() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('follows')
              .select('following_id')
              .eq('follower_id', userId!) as List,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['following_id'] as String).toList();
    return List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              // avatar_url added so stories row can show profile photos.
              .select(
                  'id, display_name, avatar_url, currently_reading_title, currently_reading_author')
              .inFilter('id', ids)
              .filter('deleted_at', 'is', null) as List,
    );
  }

  /// Set of user IDs I currently follow — used for follow-button toggle state.
  Future<Set<String>> fetchFollowingIds() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('follows')
              .select('following_id')
              .eq('follower_id', userId!) as List,
    );
    return rows.map((r) => r['following_id'] as String).toSet();
  }

  /// Profiles of users who follow me.
  Future<List<Map<String, dynamic>>> fetchFollowers() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('follows')
              .select('follower_id')
              .eq('following_id', userId!) as List,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['follower_id'] as String).toList();
    return List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select(
                  'id, display_name, avatar_url, currently_reading_title, currently_reading_author')
              .inFilter('id', ids)
              .filter('deleted_at', 'is', null) as List,
    );
  }

  /// Jam members I haven't followed yet — used as "Suggeriti".
  Future<List<Map<String, dynamic>>> fetchFollowingSuggestions() async {
    final uid = userId!;
    final myJams = await fetchMyJams();
    if (myJams.isEmpty) return [];

    final jamIds = myJams.map((j) => j['id'] as String).toList();
    final memberRows = List<Map<String, dynamic>>.from(
      await _client
              .from('jam_members')
              .select('user_id')
              .inFilter('jam_id', jamIds)
              .neq('user_id', uid) as List,
    );
    if (memberRows.isEmpty) return [];

    final memberIds =
        memberRows.map((r) => r['user_id'] as String).toSet().toList();
    final followingIds = await fetchFollowingIds();
    final suggestionIds = memberIds
        .where((id) => !followingIds.contains(id))
        .take(10)
        .toList();
    if (suggestionIds.isEmpty) return [];

    return List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select(
                  'id, display_name, avatar_url, currently_reading_title, currently_reading_author')
              .inFilter('id', suggestionIds) as List,
    );
  }

  // ─── Moderation: blocking & reporting (App Store Guideline 1.2) ───────────

  /// Block another user. Routes through the `block_user` RPC (migration 041),
  /// which upserts the block row idempotently AND severs any follow edge in
  /// both directions server-side. Invalidates the blocked-ids cache so feeds
  /// reflect the block immediately.
  Future<void> blockUser(String userId) async {
    await _client.rpc('block_user', params: {'p_blocked_id': userId});
    _invalidateBlockedIdsCache();
  }

  /// Remove a block. Routes through the `unblock_user` RPC (migration 041).
  /// Does not restore prior follows. Invalidates the blocked-ids cache.
  Future<void> unblockUser(String userId) async {
    await _client.rpc('unblock_user', params: {'p_blocked_id': userId});
    _invalidateBlockedIdsCache();
  }

  /// IDs of users the current user has blocked. Used to filter posts, feed,
  /// comments and conversations client-side.
  ///
  /// Cached for [_blockedIdsTtl] to keep list loads cheap (one query, reused
  /// across the several fetches that need it). Pass [forceRefresh] to bypass
  /// the cache. Returns an empty set when signed out or on error (fail-open:
  /// a transient failure must not blank the feed).
  Future<Set<String>> fetchBlockedUserIds({bool forceRefresh = false}) async {
    if (!isAuthenticated || userId == null) return <String>{};

    final cached = _blockedIdsCache;
    final fetchedAt = _blockedIdsFetchedAt;
    if (!forceRefresh &&
        cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _blockedIdsTtl) {
      return cached;
    }

    try {
      final rows = List<Map<String, dynamic>>.from(
        await _client
            .from('blocked_users')
            .select('blocked_id')
            .eq('blocker_id', userId!) as List,
      );
      final ids = rows.map((r) => r['blocked_id'] as String).toSet();
      _blockedIdsCache = ids;
      _blockedIdsFetchedAt = DateTime.now();
      return ids;
    } catch (_) {
      // Fail-open: return the last known set (or empty) rather than erroring
      // the caller's list load.
      return cached ?? <String>{};
    }
  }

  void _invalidateBlockedIdsCache() {
    _blockedIdsCache = null;
    _blockedIdsFetchedAt = null;
  }

  /// Report objectionable content. Routes through the `report_content` RPC
  /// (migration 041), which records the report with the caller as reporter and
  /// is rate-limited server-side (20/day). [contentType] must be one of
  /// 'post','comment','message','profile','review','jam'.
  Future<void> reportContent({
    required String contentType,
    required String contentId,
    String? reportedUserId,
    required String reason,
    String? details,
  }) async {
    await _client.rpc('report_content', params: {
      'p_content_type': contentType,
      'p_content_id': contentId,
      'p_reported_user_id': reportedUserId,
      'p_reason': reason,
      'p_details': details,
    });
  }

  // ─── Profile stats ─────────────────────────────────────────────────────────

  Future<void> updateDisplayName(String displayName) async {
    await _client
        .from('profiles')
        .update({'display_name': displayName}).eq('id', userId!);
  }

  /// Update multiple profile fields at once. [username] is stored lowercase.
  Future<void> updateProfileInfo({
    String? displayName,
    String? bio,
    String? currentlyReadingTitle,
    String? currentlyReadingAuthor,
    String? username,
  }) async {
    if (!isAuthenticated || userId == null) return;
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (bio != null) data['bio'] = bio;
    if (currentlyReadingTitle != null) data['currently_reading_title'] = currentlyReadingTitle;
    if (currentlyReadingAuthor != null) data['currently_reading_author'] = currentlyReadingAuthor;
    if (username != null && username.trim().isNotEmpty) {
      data['username'] = username.trim().toLowerCase();
    }
    if (data.isEmpty) return;
    await _client.from('profiles').update(data).eq('id', userId!);
  }

  /// Aggregate counts for the current user's profile stats row.
  Future<Map<String, int>> fetchMyStats() async {
    final uid = userId!;
    final results = await Future.wait([
      _client.from('books').select('id').eq('user_id', uid),
      _client.from('highlights').select('id').eq('user_id', uid),
      _client.from('follows').select('following_id').eq('follower_id', uid),
      _client.from('follows').select('follower_id').eq('following_id', uid),
    ]);
    return {
      'books': (results[0] as List).length,
      'highlights': (results[1] as List).length,
      'following': (results[2] as List).length,
      'followers': (results[3] as List).length,
    };
  }

  /// Highlights shared by the current user in any Jam — for the profile grid.
  Future<List<Map<String, dynamic>>> fetchMySharedHighlights() async {
    final response = await _client
        .from('jam_highlights')
        .select('*, highlights(content, color, books(title, author)), jams(title, id)')
        .eq('shared_by', userId!)
        .order('shared_at', ascending: false)
        .limit(120); // profile grid — newest 120 is plenty
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── Feed (highlights shared by people I follow) ──────────────────────────

  /// Recent highlights shared by followed users across all Jams, newest first.
  Future<List<Map<String, dynamic>>> fetchFeed() async {
    if (!isAuthenticated) return [];
    final blockedIds = await fetchBlockedUserIds();
    final followingIds = (await fetchFollowingIds())
        .where((id) => !blockedIds.contains(id))
        .toList();
    if (followingIds.isEmpty) return [];

    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('jam_highlights')
              .select(
                  '*, highlights(id, content, color, books(title, author)), jams(id, title)')
              .inFilter('shared_by', followingIds)
              .order('shared_at', ascending: false)
              .limit(60) as List,
    );
    if (rows.isEmpty) return [];

    // Defensive: drop highlights shared by a blocked user.
    rows.removeWhere(
        (r) => blockedIds.contains(r['shared_by'] as String? ?? ''));
    if (rows.isEmpty) return [];

    // Fetch profiles for the users who shared
    final userIds =
        rows.map((r) => r['shared_by'] as String).toSet().toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id, display_name, currently_reading_title')
              .inFilter('id', userIds) as List,
    );
    final profileById = {for (var p in profiles) p['id'] as String: p};

    return rows
        .map((r) => {...r, 'profile': profileById[r['shared_by'] as String]})
        .toList();
  }

  // ─── Other user profile ────────────────────────────────────────────────────

  /// Returns null when the targetId is a soft-deleted account
  /// (deleted_at IS NOT NULL). The profile row still exists so chat
  /// history resolves, but the public profile page should treat the user
  /// as gone — caller renders an "account no longer exists" empty state.
  Future<Map<String, dynamic>?> fetchPublicProfile(String targetId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', targetId)
        .maybeSingle();
    if (row == null) return null;
    if (row['deleted_at'] != null) return null;
    return row;
  }

  /// Real aggregate counts for ANOTHER user's public profile stats row.
  ///
  /// The four numbers and their server-side sources:
  ///   • highlights → rows in `highlights` owned by the user (user_id).
  ///   • shared     → rows in `jam_highlights` the user shared (shared_by).
  ///                  Same source as fetchUserSharedHighlights /
  ///                  fetchMySharedHighlights — "condivisi" = highlights this
  ///                  user has shared into any Jam, so the count agrees with
  ///                  the shared grid.
  ///   • following  → rows in `follows` where the user is the follower.
  ///   • followers  → rows in `follows` where the user is being followed.
  ///
  /// ⚠️ RLS caveat that forced the RPC: `highlights` and `jam_highlights` are
  /// NOT world-readable (migration 002: highlights are owner-only, visible to
  /// others only when shared in a common Jam). So counting them directly from
  /// the client returns the WRONG total when viewing a stranger — it would only
  /// see the subset shared into Jams you both belong to. `follows`, by
  /// contrast, is readable by any authenticated user (migration 003).
  ///
  /// To get the TRUE totals we call the SECURITY DEFINER RPC
  /// `public_user_stats(target_id)` (migration 035) which computes the counts
  /// server-side, bypassing RLS. It returns only four integers — counts, never
  /// highlight content — so it leaks nothing sensitive.
  ///
  /// Fallback: if the RPC isn't deployed yet, we degrade to the direct
  /// per-table counts (accurate for follows; RLS-limited for highlights/shared)
  /// so the screen still renders instead of erroring.
  Future<Map<String, int>> fetchUserStats(String targetId) async {
    try {
      final res = await _client
          .rpc('public_user_stats', params: {'target_id': targetId});
      // The RPC returns a single JSON object (or a 1-row set, depending on
      // how PostgREST wraps it). Normalise both shapes.
      final row = res is List
          ? (res.isNotEmpty ? res.first as Map<String, dynamic> : null)
          : res as Map<String, dynamic>?;
      if (row != null) {
        int asInt(dynamic v) =>
            v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
        return {
          'highlights': asInt(row['highlights']),
          'shared': asInt(row['shared']),
          'following': asInt(row['following']),
          'followers': asInt(row['followers']),
        };
      }
    } catch (_) {
      // RPC missing / not yet applied → fall back to direct counts below.
    }

    final results = await Future.wait([
      _client.from('highlights').select('id').eq('user_id', targetId),
      _client.from('jam_highlights').select('highlight_id').eq('shared_by', targetId),
      _client.from('follows').select('following_id').eq('follower_id', targetId),
      _client.from('follows').select('follower_id').eq('following_id', targetId),
    ]);
    return {
      'highlights': (results[0] as List).length,
      'shared': (results[1] as List).length,
      'following': (results[2] as List).length,
      'followers': (results[3] as List).length,
    };
  }

  Future<List<Map<String, dynamic>>> fetchUserSharedHighlights(
      String targetId) async {
    final response = await _client
        .from('jam_highlights')
        .select(
            '*, highlights(content, color, books(title, author)), jams(title, id)')
        .eq('shared_by', targetId)
        .order('shared_at', ascending: false)
        .limit(120); // profile grid — newest 120 is plenty
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── My profile ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMyBooks() async {
    if (!isAuthenticated || userId == null) return [];
    final rows = await _client
        .from('books')
        .select('id, title, author')
        .eq('user_id', userId!)
        .order('title') as List;
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Returns the longest highlight the user has (good for spotlight card).
  Future<Map<String, dynamic>?> fetchMyHighlightSpotlight() async {
    if (!isAuthenticated || userId == null) return null;
    final rows = await _client
        .from('highlights')
        .select('id, content, color, books(title, author)')
        .eq('user_id', userId!)
        .order('added_at', ascending: false)
        .limit(30) as List;
    if (rows.isEmpty) return null;
    final list = List<Map<String, dynamic>>.from(rows);
    list.sort((a, b) =>
        (b['content'] as String? ?? '').length
            .compareTo((a['content'] as String? ?? '').length));
    return list.first;
  }

  /// Saves the user's 6 favourite books (title + author) to their profile.
  /// Requires migration 024 to add `favorite_books jsonb` to profiles.
  Future<void> updateFavoriteBooks(
      List<Map<String, String>> books) async {
    if (!isAuthenticated || userId == null) return;
    await _client.from('profiles').update({
      'favorite_books': books,
    }).eq('id', userId!);
  }

  Future<void> updateProfileAppearance(
      String gradientPreset, String patternPreset) async {
    if (!isAuthenticated || userId == null) return;
    await _client.from('profiles').update({
      'gradient_preset': gradientPreset,
      'pattern_preset': patternPreset,
    }).eq('id', userId!);
  }

  /// Best-effort mirror of the LOCAL Ripasso streak to the user's profile so it
  /// can become social later (leaderboards, profile badge). The local Isar
  /// ReviewState is authoritative; this is a fire-and-forget publish. Requires
  /// migration 050 (review_streak / review_best_streak / last_reviewed_on) —
  /// the caller wraps this in try/catch, so it degrades silently until applied.
  Future<void> updateReviewStreak({
    required int streak,
    required int bestStreak,
    required DateTime lastReviewedOn,
  }) async {
    if (!isAuthenticated || userId == null) return;
    // `last_reviewed_on` is a Postgres `date` — send a plain YYYY-MM-DD string.
    final d = lastReviewedOn;
    final dateStr =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _client.from('profiles').update({
      'review_streak': streak,
      'review_best_streak': bestStreak,
      'last_reviewed_on': dateStr,
    }).eq('id', userId!);
  }

  // ─── Realtime ─────────────────────────────────────────────────────────────

  RealtimeChannel subscribeToJam(String jamId, void Function(Map<String, dynamic>) onHighlightShared) {
    return _client
        .channel('jam:$jamId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'jam_highlights',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'jam_id', value: jamId),
          callback: (payload) => onHighlightShared(payload.newRecord),
        )
        .subscribe();
  }

  // ─── Avatar + Cover photo upload ─────────────────────────────────────────

  /// Ensures a storage bucket exists (creates it if missing, ignores errors if it already exists).
  Future<void> _ensureBucket(String bucketId, {bool public = true}) async {
    try {
      await _client.storage.createBucket(
        bucketId,
        BucketOptions(public: public),
      );
    } catch (_) {
      // Bucket likely already exists — ignore.
    }
  }

  // ─── Image moderation ──────────────────────────────────────────────────────

  /// Asks the moderate-image edge function whether [bytes] is objectionable
  /// (NSFW / gore / violence / offensive). FAIL-OPEN: returns false on any
  /// error or when the provider keys aren't configured, so uploads never break.
  Future<bool> moderateImageBytes(List<int> bytes) async {
    // Skip very large payloads (base64 balloons them); the picker already caps
    // sizes, and an outsized image is better allowed than blocking the upload.
    if (bytes.length > 8 * 1024 * 1024) return false;
    try {
      final res = await _client.functions.invoke(
        'moderate-image',
        body: {'image': base64Encode(bytes)},
      );
      final data = res.data;
      return data is Map && data['flagged'] == true;
    } catch (_) {
      return false; // fail-open
    }
  }

  /// Throws [ImageModerationException] when [bytes] is flagged by moderation.
  /// Call this BEFORE committing an image to public storage so objectionable
  /// images never persist.
  Future<void> _assertImageClean(List<int> bytes) async {
    if (await moderateImageBytes(bytes)) {
      throw const ImageModerationException();
    }
  }

  /// Uploads avatar image to Supabase Storage and returns a public URL.
  ///
  /// Uses getPublicUrl (no expiry) — requires the 'avatars' bucket to be public,
  /// which is enforced by migration 011/012. Previously used createSignedUrl,
  /// which failed silently when bucket download policies were missing.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    await _ensureBucket('avatars');
    final path = '${userId!}/avatar.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = '${_client.storage.from('avatars').getPublicUrl(path)}?v=$ts';
    await _client.from('profiles').update({'avatar_url': url}).eq('id', userId!);
    return url;
  }

  /// Uploads cover photo to Supabase Storage and returns a public URL.
  Future<String> uploadCover(Uint8List bytes, String ext) async {
    await _ensureBucket('covers');
    final path = '${userId!}/cover.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('covers').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = '${_client.storage.from('covers').getPublicUrl(path)}?v=$ts';
    await _client.from('profiles').update({'cover_url': url}).eq('id', userId!);
    return url;
  }

  /// Uploads a CUSTOM book cover and returns its public URL. Keyed per book so
  /// each library book owns one cover object. The book row itself is updated
  /// separately (via upsertBook) by the caller. Image is moderated first.
  Future<String> uploadBookCover(
      Uint8List bytes, String ext, String bookKey) async {
    await _ensureBucket('book-covers');
    final safeKey = bookKey.isNotEmpty
        ? bookKey
        : DateTime.now().millisecondsSinceEpoch.toString();
    final path = '${userId!}/$safeKey.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('book-covers').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${_client.storage.from('book-covers').getPublicUrl(path)}?v=$ts';
  }

  /// Uploads a Jam cover photo and updates the jam's cover_url column.
  Future<String> uploadJamCover(
      String jamId, Uint8List bytes, String ext) async {
    await _ensureBucket('jam-covers');
    final path = '$jamId/cover.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('jam-covers').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = '${_client.storage.from('jam-covers').getPublicUrl(path)}?v=$ts';
    await _client.from('jams').update({'cover_url': url}).eq('id', jamId);
    return url;
  }

  /// Renames a Jam. RLS + the explicit owner_id filter ensure only the owner
  /// can change the title. Returns the trimmed title that was persisted.
  Future<String> updateJamTitle(String jamId, String title) async {
    final trimmed = title.trim();
    await _client
        .from('jams')
        .update({'title': trimmed})
        .eq('id', jamId)
        .eq('owner_id', userId!);
    return trimmed;
  }

  // ─── Pinned highlights ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPinnedHighlights(String targetUserId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('pinned_highlights')
              .select('sort_order, highlight_id')
              .eq('user_id', targetUserId)
              .order('sort_order') as List,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['highlight_id'] as String).toList();
    final highlights = List<Map<String, dynamic>>.from(
      await _client
              .from('highlights')
              .select('id, content, color, books(title, author)')
              .inFilter('id', ids) as List,
    );
    final hlById = {for (var h in highlights) h['id'] as String: h};
    return [
      for (var r in rows)
        if (hlById.containsKey(r['highlight_id'] as String))
          {...hlById[r['highlight_id'] as String]!, 'sort_order': r['sort_order']},
    ];
  }

  /// Replaces the current user's pinned highlights (max 3).
  Future<void> updatePinnedHighlights(List<String> highlightIds) async {
    final uid = userId!;
    await _client.from('pinned_highlights').delete().eq('user_id', uid);
    if (highlightIds.isEmpty) return;
    await _client.from('pinned_highlights').insert([
      for (var i = 0; i < highlightIds.length && i < 3; i++)
        {'user_id': uid, 'highlight_id': highlightIds[i], 'sort_order': i},
    ]);
  }

  // ─── Posts ────────────────────────────────────────────────────────────────

  Future<void> createPost({
    String? body,
    String? highlightSupabaseId,
    String? jamId,
    String? imageUrl,
    List<String> mentions = const [],
  }) async {
    final inserted = await _client.from('posts').insert({
      'user_id': userId,
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      if (highlightSupabaseId != null) 'highlight_id': highlightSupabaseId,
      if (jamId != null) 'jam_id': jamId,
      if (imageUrl != null) 'image_url': imageUrl,
      if (mentions.isNotEmpty) 'mentions': mentions,
    }).select('id').single();
    final newId = inserted['id'] as String?;

    // Notify mentioned users — best-effort, never blocks post creation.
    if (newId != null && mentions.isNotEmpty) {
      // ignore: discarded_futures
      _notifyPostMentions(newId);
    }
  }

  /// Uploads an image for a post and returns the public URL.
  Future<String> uploadPostImage(Uint8List bytes, String ext) async {
    await _ensureBucket('post-images');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${userId!}/$ts.$ext';
    await _assertImageClean(bytes);
    await _client.storage.from('post-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    return _client.storage.from('post-images').getPublicUrl(path);
  }

  /// Fetch posts: from people I follow + my own, newest first.
  Future<List<Map<String, dynamic>>> fetchPosts() async {
    if (!isAuthenticated) return [];
    final followingIds = await fetchFollowingIds();
    final blockedIds = await fetchBlockedUserIds();
    // Exclude blocked users from the authors we query for (never my own posts).
    final allIds = {...followingIds, userId!}
        .where((id) => id == userId || !blockedIds.contains(id))
        .toList();

    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('posts')
              .select('''
                *,
                highlights(id, content, color, books(title, author))
              ''')
              .inFilter('user_id', allIds)
              .order('created_at', ascending: false)
              .limit(80) as List,
    );
    if (rows.isEmpty) return [];

    // Defensive: drop any post authored by a blocked user that slipped through.
    rows.removeWhere(
        (r) => blockedIds.contains(r['user_id'] as String? ?? ''));
    if (rows.isEmpty) return [];

    // Fetch profiles in parallel (include currently_reading for "reading X"
    // display). Also include every mentioned user id so we can resolve the
    // tappable @username spans without a second round-trip.
    final authorIds = rows.map((r) => r['user_id'] as String).toSet();
    final mentionedIds = _collectMentionedIds(rows);
    final allProfileIds = {...authorIds, ...mentionedIds}.toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select(
                  'id, display_name, avatar_url, currently_reading_title, username')
              .inFilter('id', allProfileIds) as List,
    );
    final profileById = {for (var p in profiles) p['id'] as String: p};

    // Fetch my likes for quick "isLiked" state
    final postIds = rows.map((r) => r['id'] as String).toList();
    final myLikes = List<Map<String, dynamic>>.from(
      await _client
              .from('post_likes')
              .select('post_id')
              .eq('user_id', userId!)
              .inFilter('post_id', postIds) as List,
    );
    final likedIds = myLikes.map((l) => l['post_id'] as String).toSet();

    return rows.map((r) {
      return {
        ...r,
        'profile': profileById[r['user_id'] as String],
        'is_liked': likedIds.contains(r['id'] as String),
        'mentioned_profiles': _buildMentionedProfiles(r, profileById),
      };
    }).toList();
  }

  /// Collects the union of all uuids found in each post's `mentions` array.
  Set<String> _collectMentionedIds(List<Map<String, dynamic>> rows) {
    final ids = <String>{};
    for (final r in rows) {
      final mentions = r['mentions'];
      if (mentions is List) {
        for (final m in mentions) {
          if (m is String && m.isNotEmpty) ids.add(m);
        }
      }
    }
    return ids;
  }

  /// Builds the `mentioned_profiles` map for a single post row: a map from each
  /// mentioned user id to {username, display_name}. Returns an empty map when
  /// the post has no mentions (or none of them resolve to a known profile).
  Map<String, Map<String, String>> _buildMentionedProfiles(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> profileById,
  ) {
    final result = <String, Map<String, String>>{};
    final mentions = row['mentions'];
    if (mentions is! List) return result;
    for (final m in mentions) {
      if (m is! String || m.isEmpty) continue;
      final profile = profileById[m];
      if (profile == null) continue;
      result[m] = {
        'username': profile['username'] as String? ?? '',
        'display_name': profile['display_name'] as String? ?? '',
      };
    }
    return result;
  }

  /// Fetch a SINGLE post by id, shaped exactly like the rows from
  /// [fetchPosts] (same highlight/book join, author profile, and the
  /// current user's like state) so the same post card can render it.
  /// Returns null when the post doesn't exist (or is not visible under RLS).
  Future<Map<String, dynamic>?> fetchPost(String postId) async {
    final row = await _client
        .from('posts')
        .select('''
          *,
          highlights(id, content, color, books(title, author))
        ''')
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return null;

    final post = Map<String, dynamic>.from(row);

    // Author profile (same fields as fetchPosts).
    final ownerId = post['user_id'] as String?;
    if (ownerId != null) {
      final profile = await _client
          .from('profiles')
          .select(
              'id, display_name, avatar_url, currently_reading_title, username')
          .eq('id', ownerId)
          .maybeSingle();
      post['profile'] = profile;
    }

    // Resolve mentioned users (id -> {username, display_name}) for tappable
    // @username spans. Empty when the post mentions no one.
    final mentionedIds = _collectMentionedIds([post]);
    if (mentionedIds.isEmpty) {
      post['mentioned_profiles'] = <String, Map<String, String>>{};
    } else {
      final mentionProfiles = List<Map<String, dynamic>>.from(
        await _client
                .from('profiles')
                .select('id, display_name, username')
                .inFilter('id', mentionedIds.toList()) as List,
      );
      final profileById = {
        for (var p in mentionProfiles) p['id'] as String: p
      };
      post['mentioned_profiles'] = _buildMentionedProfiles(post, profileById);
    }

    // Whether the current user liked it.
    var isLiked = false;
    if (isAuthenticated && userId != null) {
      final like = await _client
          .from('post_likes')
          .select('post_id')
          .eq('post_id', postId)
          .eq('user_id', userId!)
          .maybeSingle();
      isLiked = like != null;
    }
    post['is_liked'] = isLiked;

    return post;
  }

  Future<void> togglePostLike(String postId, bool currentlyLiked) async {
    if (currentlyLiked) {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId!);
    } else {
      await _client.from('post_likes').upsert({
        'post_id': postId,
        'user_id': userId,
      });
    }
    // Recompute the denormalised count from the likes table.
    final rows = List<Map<String, dynamic>>.from(
      await _client.from('post_likes').select('post_id').eq('post_id', postId)
          as List,
    );
    await _client
        .from('posts')
        .update({'likes_count': rows.length})
        .eq('id', postId);

    // Notify the post owner — only when ADDING a like, never on un-like.
    if (!currentlyLiked) {
      // ignore: discarded_futures
      _notifyPostInteraction(postId, 'like');
      // ignore: discarded_futures
      _pushPostInteraction(postId, 'like');
    }
  }

  /// Fetch posts by a specific user (for profile views), newest first.
  Future<List<Map<String, dynamic>>> fetchUserPosts(String targetUserId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('posts')
              .select('*, highlights(id, content, color, books(title, author))')
              .eq('user_id', targetUserId)
              .order('created_at', ascending: false)
              .limit(50) as List,
    );
    if (rows.isEmpty) return [];

    // Fetch my likes so we can show liked state
    List<Map<String, dynamic>> myLikes = [];
    if (isAuthenticated && userId != null) {
      final postIds = rows.map((r) => r['id'] as String).toList();
      myLikes = List<Map<String, dynamic>>.from(
        await _client
                .from('post_likes')
                .select('post_id')
                .eq('user_id', userId!)
                .inFilter('post_id', postIds) as List,
      );
    }
    final likedIds = myLikes.map((l) => l['post_id'] as String).toSet();

    // Resolve mentioned users (id -> {username, display_name}) so the post
    // cards can render tappable @username spans. One query for the whole set.
    final mentionedIds = _collectMentionedIds(rows);
    var profileById = <String, Map<String, dynamic>>{};
    if (mentionedIds.isNotEmpty) {
      final mentionProfiles = List<Map<String, dynamic>>.from(
        await _client
                .from('profiles')
                .select('id, display_name, username')
                .inFilter('id', mentionedIds.toList()) as List,
      );
      profileById = {for (var p in mentionProfiles) p['id'] as String: p};
    }

    return rows.map((r) => {
      ...r,
      'is_liked': likedIds.contains(r['id'] as String),
      'mentioned_profiles': _buildMentionedProfiles(r, profileById),
    }).toList();
  }

  // ─── Post Comments ────────────────────────────────────────────────────────────

  /// Fetch comments for a post in ascending order, with commenter profiles.
  /// Profiles are fetched in a separate query to avoid PostgREST FK ambiguity
  /// (post_comments.user_id → auth.users, not profiles directly).
  Future<List<Map<String, dynamic>>> fetchPostComments(String postId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('post_comments')
          .select(
              'id, post_id, user_id, content, image_url, gif_url, '
              'created_at, parent_comment_id')
          .eq('post_id', postId)
          .order('created_at', ascending: true) as List,
    );
    if (rows.isEmpty) return [];

    // Hide comments authored by users I've blocked.
    final blockedIds = await fetchBlockedUserIds();
    if (blockedIds.isNotEmpty) {
      rows.removeWhere(
          (r) => blockedIds.contains(r['user_id'] as String? ?? ''));
    }
    if (rows.isEmpty) return [];

    final commentIds = rows.map((r) => r['id'] as String).toList();

    // Fetch profiles + likes in parallel.
    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    final results = await Future.wait([
      _client
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', userIds),
      _client
          .from('comment_likes')
          .select('comment_id, user_id')
          .inFilter('comment_id', commentIds),
    ]);

    final profileMap = {
      for (final p in List<Map<String, dynamic>>.from(results[0] as List))
        p['id'] as String: p,
    };

    // Build like counts and has_liked flags.
    final likeMap = <String, List<String>>{};
    for (final like in List<Map<String, dynamic>>.from(results[1] as List)) {
      final cid = like['comment_id'] as String;
      likeMap.putIfAbsent(cid, () => []).add(like['user_id'] as String);
    }

    return rows.map((r) {
      final uid = r['user_id'] as String? ?? '';
      final cid = r['id'] as String;
      final likers = likeMap[cid] ?? [];
      return {
        ...r,
        'profiles': profileMap[uid],
        'like_count': likers.length,
        'has_liked': likers.contains(userId),
      };
    }).toList();
  }

  /// Add a comment to a post (text, image, or GIF — at least one required).
  /// Pass [parentCommentId] to create a reply to an existing top-level comment.
  Future<void> addPostComment(
    String postId, {
    String? content,
    String? imageUrl,
    String? gifUrl,
    String? parentCommentId,
  }) async {
    await _client.from('post_comments').insert({
      'post_id': postId,
      'user_id': userId,
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      if (imageUrl != null) 'image_url': imageUrl,
      if (gifUrl != null) 'gif_url': gifUrl,
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
    });

    // Notify the post owner that someone commented. A short preview of the
    // text (if any) is passed so the notification body can show it.
    // ignore: discarded_futures
    _notifyPostInteraction(postId, 'comment', preview: content?.trim());
    // ignore: discarded_futures
    _pushPostInteraction(postId, 'comment', preview: content?.trim());
  }

  /// Fire-and-forget: create an in-app notification for the OWNER of [postId]
  /// when the current user likes or comments on their post.
  ///
  /// [kind] is 'like' or 'comment'. [preview] is an optional short text snippet
  /// (used for comments) shown in the notification body.
  ///
  /// WHY AN RPC (and not a direct insert): the client cannot write to
  /// `notifications` directly — migration 032 deliberately removed the INSERT
  /// policy (RLS fail-closed) and migration 028 revoked EXECUTE on
  /// `create_notification` from authenticated users, both to stop forged/spam
  /// alerts. So we route through `notify_post_interaction` (migration 035): a
  /// SECURITY DEFINER function that derives the post owner server-side, uses
  /// `auth.uid()` as the actor (cannot be spoofed), and SKIPS the insert when
  /// the actor is the owner (no self-notifications). It stores the post id +
  /// actor id in the notification `data` jsonb for navigation.
  ///
  /// Never throws: a notification failure must not break liking/commenting.
  /// If the migration isn't applied yet, the RPC is simply absent and we
  /// swallow the error — the like/comment already succeeded.
  Future<void> _notifyPostInteraction(
    String postId,
    String kind, {
    String? preview,
  }) async {
    try {
      await _client.rpc('notify_post_interaction', params: {
        'p_post_id': postId,
        'p_kind': kind,
        if (preview != null && preview.isNotEmpty) 'p_preview': preview,
      });
    } catch (_) {
      // Best-effort — ignore (RPC missing, network blip, etc.).
    }
  }

  /// Fire-and-forget: send an APNs PUSH to the OWNER of [postId] when the
  /// current user likes or comments on their post. This complements the in-app
  /// notification created by [_notifyPostInteraction]; it reaches owners whose
  /// app is closed (same pattern as [_notifyConversationMembers] for messages).
  ///
  /// The recipient (post owner) and the right to push are resolved SERVER-SIDE
  /// by the `send-push-notification` edge function: we only send {post_id, kind}
  /// (+ an optional comment [preview]). The function derives the owner, verifies
  /// we actually liked/commented the post, and never notifies ourselves — so no
  /// recipient/title/body is trusted from the client.
  ///
  /// Never throws: a push failure must not break liking/commenting.
  Future<void> _pushPostInteraction(
    String postId,
    String kind, {
    String? preview,
  }) async {
    try {
      final text = preview?.trim();
      await _client.functions.invoke(
        'send-push-notification',
        body: {
          'post_id': postId,
          'kind': kind,
          if (text != null && text.isNotEmpty) 'preview': text,
        },
      );
    } catch (_) {
      // Push is best-effort; a failure must never affect the like/comment.
    }
  }

  /// Fire-and-forget: ask the server to create one in-app notification per user
  /// mentioned in [postId] (SECURITY DEFINER RPC from migration 048). Never
  /// throws — a missing RPC or network blip must not break post creation.
  Future<void> _notifyPostMentions(String postId) async {
    try {
      await _client.rpc('notify_post_mentions', params: {'p_post_id': postId});
    } catch (_) {
      // Best-effort — ignore (RPC missing, network blip, etc.).
    }
  }

  /// Like a comment (idempotent — server has UNIQUE constraint).
  Future<void> likeComment(String commentId) async {
    await _client.from('comment_likes').insert({
      'comment_id': commentId,
      'user_id': userId,
    });
  }

  /// Remove like from a comment.
  Future<void> unlikeComment(String commentId) async {
    await _client
        .from('comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', userId!);
  }

  /// Delete own comment.
  Future<void> deletePostComment(String commentId) async {
    await _client
        .from('post_comments')
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId!);
  }

  // ─── Followers/Following for any user (public profiles) ──────────────────

  Future<List<Map<String, dynamic>>> fetchUserFollowers(String targetId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('follows')
              .select('follower_id')
              .eq('following_id', targetId) as List,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['follower_id'] as String).toList();
    return List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id, display_name, avatar_url, currently_reading_title')
              .inFilter('id', ids) as List,
    );
  }

  Future<List<Map<String, dynamic>>> fetchUserFollowing(String targetId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
              .from('follows')
              .select('following_id')
              .eq('follower_id', targetId) as List,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['following_id'] as String).toList();
    return List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id, display_name, avatar_url, currently_reading_title')
              .inFilter('id', ids) as List,
    );
  }

  Future<List<Map<String, dynamic>>> fetchUserBooks(String targetId) async {
    final rows = await _client
            .from('books')
            .select('id, title, author')
            .eq('user_id', targetId)
            .order('title') as List;
    return List<Map<String, dynamic>>.from(rows);
  }

  // ─── File upload (My Clippings.txt) ───────────────────────────────────────

  Future<String> uploadClippingsFile(Uint8List bytes, String filename) async {
    // Defence-in-depth: reduce the supplied name to a safe base name so a
    // crafted filename (e.g. "../other/x") can't escape the user's own folder.
    // The clippings bucket is already private + owner-scoped, but a
    // client-supplied path segment must never be trusted verbatim.
    final base = filename.split(RegExp(r'[\\/]+')).last;
    final cleaned = base
        .replaceAll('..', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    final safeName = cleaned.isEmpty
        ? 'clippings_${DateTime.now().millisecondsSinceEpoch}.txt'
        : cleaned;
    final path = '$userId/$safeName';
    await _client.storage.from('clippings').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  // ─── User search ─────────────────────────────────────────────────────────────

  /// Full-text search on display_name and username fields.
  /// Excludes soft-deleted accounts (deleted_at IS NOT NULL).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim();
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('profiles')
          .select('id, display_name, username, avatar_url, bio')
          .or('display_name.ilike.%$q%,username.ilike.%$q%')
          .filter('deleted_at', 'is', null)
          .neq('id', userId ?? '')
          .limit(30) as List,
    );
    return rows;
  }

  // ─── Username ─────────────────────────────────────────────────────────────────

  /// Returns true if the username is not already taken by another user.
  Future<bool> isUsernameAvailable(String username) async {
    final q = username.toLowerCase().trim();
    if (q.isEmpty) return false;
    final rows = await _client
        .from('profiles')
        .select('id')
        .eq('username', q)
        .neq('id', userId ?? '')
        .limit(1);
    return (rows as List).isEmpty;
  }

  // ─── Messaging ───────────────────────────────────────────────────────────────

  /// All conversations the current user is a member of, with last message and
  /// member profiles pre-fetched. Sorted by most recently updated.
  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final uid = userId!;
    final blockedIds = await fetchBlockedUserIds();

    // Conversations I'm in — also fetch last_read_at for unread badge
    final memberRows = List<Map<String, dynamic>>.from(
      await _client
          .from('conversation_members')
          .select('conversation_id, last_read_at')
          .eq('user_id', uid) as List,
    );
    if (memberRows.isEmpty) return [];

    final lastReadMap = {
      for (final r in memberRows)
        r['conversation_id'] as String: r['last_read_at'] as String?,
    };
    final convIds = lastReadMap.keys.toList();

    final convRows = List<Map<String, dynamic>>.from(
      await _client
          .from('conversations')
          .select()
          .inFilter('id', convIds)
          .order('updated_at', ascending: false) as List,
    );
    if (convRows.isEmpty) return [];

    final result = <Map<String, dynamic>>[];
    for (final conv in convRows) {
      final convId = conv['id'] as String;

      // Use SECURITY DEFINER RPC to get all members despite restricted RLS
      final profiles = List<Map<String, dynamic>>.from(
        await _client.rpc('get_conversation_member_profiles',
            params: {'p_conversation_id': convId}) as List,
      );

      final lastMsgs = List<Map<String, dynamic>>.from(
        await _client
            .from('messages')
            .select('id, content, sender_id, image_url, created_at')
            .eq('conversation_id', convId)
            .order('created_at', ascending: false)
            .limit(1) as List,
      );

      final otherMembers =
          profiles.where((p) => p['id'] != uid).toList();

      // Hide conversations whose every other member is blocked. For a 1:1 DM
      // this drops the chat with a blocked user; in a group it only hides when
      // no non-blocked member remains.
      if (otherMembers.isNotEmpty &&
          otherMembers.every(
              (p) => blockedIds.contains(p['id'] as String? ?? ''))) {
        continue;
      }

      result.add({
        ...conv,
        'members': otherMembers,
        'last_message': lastMsgs.isEmpty ? null : lastMsgs.first,
        'my_last_read_at': lastReadMap[convId],
        'current_user_id': uid,
      });
    }
    return result;
  }

  /// Mark all messages in [conversationId] as read for the current user.
  ///
  /// Routes through the SECURITY DEFINER RPC `mark_conversation_read`
  /// (migration 030) so the update bypasses the historical lack of an
  /// UPDATE policy on conversation_members AND uses server-side now()
  /// for the timestamp — both prerequisites for the nav badge to
  /// actually clear without a manual refresh.
  Future<void> markConversationRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      // Swallow but log — the badge will just stay until the next
      // pull-to-refresh in the rare case the RPC fails.
      // ignore: avoid_print
      print('[markConversationRead] $e');
    }
  }

  /// Leave (delete) a conversation for the CURRENT user only.
  ///
  /// This removes the caller's row from `conversation_members` for
  /// [conversationId]. It is a *leave*, not a hard-delete: the other
  /// members keep the chat. When the last member leaves, the now-orphaned
  /// conversation row can be cleaned up server-side; its messages and any
  /// remaining member rows cascade via the FKs in migration 014
  /// (`ON DELETE CASCADE`).
  ///
  /// WHY RPC-FIRST: migration 014 only ever created SELECT + INSERT RLS
  /// policies on `conversation_members` — there was no DELETE policy (the
  /// same gap migration 030 called out for UPDATE). With RLS enabled and
  /// fail-closed, a bare client `.delete()` silently affects zero rows.
  /// So we prefer the SECURITY DEFINER RPC `leave_conversation`
  /// (migration 037), mirroring `mark_conversation_read`. If that RPC
  /// isn't deployed yet we fall back to a direct delete, which succeeds
  /// once migration 037's `conv_members_delete` policy is applied. The
  /// direct delete is always scoped to the caller (`user_id = auth.uid()`),
  /// so it can never remove anyone else's membership even if the policy
  /// were ever loosened.
  Future<void> deleteConversation(String conversationId) async {
    final uid = userId;
    if (uid == null) throw Exception('not authenticated');

    try {
      await _client.rpc(
        'leave_conversation',
        params: {'p_conversation_id': conversationId},
      );
      return;
    } catch (_) {
      // RPC missing / not yet applied → fall back to the direct delete,
      // which is allowed once the conv_members_delete policy exists.
    }

    await _client
        .from('conversation_members')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', uid);
  }

  /// Upload an image to the (private) message-images bucket and return its
  /// storage PATH. The path — not a public URL — is stored on the message;
  /// readers resolve it to a short-lived signed URL via
  /// [signedMessageImageUrl] (the bucket is private, so only conversation
  /// members can read each object). See migration 046.
  Future<String> uploadMessageImage(
      String fileName, List<int> bytes) async {
    // Reduce the supplied name to a safe base name (no path separators or
    // parent-dir segments) so a crafted name can't escape the user's folder.
    final base = fileName.split(RegExp(r'[\\/]+')).last.replaceAll('..', '');
    final safeName = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '${userId!}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _assertImageClean(bytes);
    await _client.storage
        .from('message-images')
        .uploadBinary(path, bytes as dynamic);
    return path;
  }

  /// Resolve a stored message-image reference to a displayable URL.
  ///
  /// `messages.image_url` can carry three kinds of reference:
  ///   • a bare storage path (new uploads)               -> sign it
  ///   • a full message-images public URL (old uploads)  -> extract path, sign
  ///   • an external URL, e.g. a GIPHY GIF               -> return unchanged
  /// The message-images bucket is private, so its objects are served via a
  /// short-lived signed URL. RLS (migration 046) lets only conversation members
  /// sign a given object. Returns null if signing fails.
  Future<String?> signedMessageImageUrl(String stored) async {
    if (stored.isEmpty) return null;
    const marker = '/message-images/';
    String path;
    if (stored.startsWith('http')) {
      final i = stored.indexOf(marker);
      if (i < 0) return stored; // external (e.g. GIPHY) — use directly
      path = stored.substring(i + marker.length).split('?').first;
    } else {
      path = stored; // already a bare storage path
    }
    try {
      return await _client.storage
          .from('message-images')
          .createSignedUrl(path, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  /// Messages for a single conversation in chronological order, with sender
  /// profiles pre-fetched.
  Future<List<Map<String, dynamic>>> fetchMessages(
      String conversationId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('messages')
          .select(
              'id, conversation_id, sender_id, content, image_url, shared_post_id, created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .limit(200) as List,
    );
    if (rows.isEmpty) return [];

    final senderIds =
        rows.map((r) => r['sender_id'] as String).toSet().toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', senderIds) as List,
    );
    final profileMap = {
      for (final p in profiles) p['id'] as String: p,
    };
    return rows.map((r) {
      final sid = r['sender_id'] as String? ?? '';
      return {...r, 'sender': profileMap[sid]};
    }).toList();
  }

  /// Send a text or image message in a conversation.
  ///
  /// [sharedPostId], when provided, attaches a reference to a feed post so the
  /// message renders in the chat as a tappable "post condiviso" card (see
  /// migration 040). It is independent of [content]/[imageUrl] — a share
  /// usually carries a short preview [content] plus the post id.
  Future<void> sendMessage(
    String conversationId, {
    String? content,
    String? imageUrl,
    String? sharedPostId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      if (imageUrl != null) 'image_url': imageUrl,
      if (sharedPostId != null) 'shared_post_id': sharedPostId,
      'created_at': now,
    });
    await _client
        .from('conversations')
        .update({'updated_at': now})
        .eq('id', conversationId);

    // Best-effort push to the other members (realtime covers the in-app case;
    // this reaches recipients whose app is closed). Never blocks/fails the send.
    // ignore: discarded_futures
    _notifyConversationMembers(conversationId, content: content);
  }

  /// Share a feed post into an existing conversation.
  ///
  /// Sends a normal message carrying a short [previewText] (falling back to
  /// "Post condiviso") AND the post reference, so the recipient sees a tappable
  /// card in the chat that opens /post/:id. Reuses [sendMessage], so the push
  /// notification + conversation `updated_at` bump happen exactly as for any
  /// other message.
  Future<void> sharePostToConversation(
    String conversationId,
    String postId, {
    String? previewText,
  }) async {
    final preview = (previewText != null && previewText.trim().isNotEmpty)
        ? previewText.trim()
        : 'Post condiviso';
    await sendMessage(
      conversationId,
      content: preview,
      sharedPostId: postId,
    );
  }

  /// Best-effort APNs push to the OTHER members of [conversationId] when a
  /// message is sent. Fire-and-forget — never throws.
  Future<void> _notifyConversationMembers(
    String conversationId, {
    String? content,
  }) async {
    try {
      final me = userId;
      // RLS on conversation_members only returns the CALLER's own row, so a
      // direct select would yield an empty recipient list and the push would
      // never be sent. Use the SECURITY DEFINER RPC (the same one
      // fetchConversations uses) to read ALL members; it returns profile rows
      // keyed by `id`.
      final rows = await _client.rpc(
        'get_conversation_member_profiles',
        params: {'p_conversation_id': conversationId},
      ) as List;
      // Group context, so a group push reads "GroupName" / "Sender: message"
      // instead of just the sender. Best-effort: on any failure it falls back to
      // the 1:1-style push (the edge function ignores empty group fields).
      bool isGroup = false;
      String groupName = '';
      try {
        final conv = await _client
            .from('conversations')
            .select('is_group, group_name')
            .eq('id', conversationId)
            .maybeSingle();
        isGroup = conv?['is_group'] == true;
        groupName = (conv?['group_name'] as String?)?.trim() ?? '';
      } catch (_) {
        // ignore — push degrades to the 1:1 layout
      }
      final text = content?.trim() ?? '';
      final preview = text.isNotEmpty
          ? (text.length > 140 ? '${text.substring(0, 140)}…' : text)
          : 'Ti ha inviato una foto';
      for (final row in rows) {
        final uid = (row as Map)['id'] as String?;
        if (uid == null || uid == me) continue;
        await _client.functions.invoke(
          'send-push-notification',
          body: {
            'user_id': uid,
            'title': 'Nuovo messaggio',
            'body': preview,
            'is_group': isGroup,
            'group_name': groupName,
            'data': {'conversation_id': conversationId},
          },
        );
      }
    } catch (_) {
      // Push is best-effort; a failure must never affect message delivery.
    }
  }

  /// Returns the conversation ID for a DM with [otherUserId].
  /// Uses a SECURITY DEFINER RPC function to avoid RLS chicken-and-egg.
  Future<String> createOrFetchDirectConversation(String otherUserId) async {
    final result = await _client.rpc(
      'create_direct_conversation',
      params: {'p_other_user_id': otherUserId},
    );
    return result as String;
  }

  /// Create a group conversation with [memberIds] (current user is auto-added).
  Future<String> createGroupConversation(
    List<String> memberIds, {
    required String groupName,
  }) async {
    final result = await _client.rpc(
      'create_group_conversation',
      params: {
        'p_member_ids': memberIds,
        'p_group_name': groupName.trim(),
      },
    );
    return result as String;
  }

  // ─── Post CRUD (author only) ──────────────────────────────────────────────

  /// Delete a post by ID. Only succeeds if current user is the author (RLS).
  Future<void> deletePost(String postId) async {
    await _client.from('posts').delete().eq('id', postId).eq('user_id', userId!);
  }

  /// Edit the body of an existing post. Only succeeds if current user is author.
  Future<void> updatePost(String postId, String newBody) async {
    await _client
        .from('posts')
        .update({'body': newBody.trim()})
        .eq('id', postId)
        .eq('user_id', userId!);
  }

  // ─── Jam 2.0: Book Voting ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchBookProposals(String jamId) async {
    final res = await _client
        .from('jam_book_proposals')
        .select('*, profiles:proposed_by(display_name, username, avatar_url), jam_book_votes(user_id)')
        .eq('jam_id', jamId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> proposeBook({
    required String jamId,
    required String title,
    String? author,
    String? description,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_book_proposals').insert({
      'jam_id': jamId,
      'proposed_by': userId,
      'title': title.trim(),
      'author': author?.trim(),
      'description': description?.trim(),
    });
  }

  Future<void> voteForBook(String proposalId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_book_votes').upsert({
      'proposal_id': proposalId,
      'user_id': userId,
    });
  }

  Future<void> unvoteForBook(String proposalId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client
        .from('jam_book_votes')
        .delete()
        .eq('proposal_id', proposalId)
        .eq('user_id', userId);
  }

  Future<void> deleteBookProposal(String proposalId) async {
    await _client.from('jam_book_proposals').delete().eq('id', proposalId);
  }

  // ─── Jam 2.0: Reading Challenges ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchJamChallenges(String jamId) async {
    final res = await _client
        .from('jam_challenges')
        .select('*, jam_challenge_progress(user_id, current_count)')
        .eq('jam_id', jamId)
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> createChallenge({
    required String jamId,
    required String title,
    String? description,
    required int targetCount,
    String unit = 'books',
    DateTime? deadline,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_challenges').insert({
      'jam_id': jamId,
      'created_by': userId,
      'title': title.trim(),
      'description': description?.trim(),
      'target_count': targetCount,
      'unit': unit,
      'deadline': deadline?.toIso8601String(),
    });
  }

  Future<void> updateChallengeProgress({
    required String challengeId,
    required int count,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_challenge_progress').upsert({
      'challenge_id': challengeId,
      'user_id': userId,
      'current_count': count,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ─── Jam 2.0: Highlight Polls ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchJamPolls(String jamId) async {
    final res = await _client
        .from('jam_highlight_polls')
        .select('*, jam_poll_candidates(id, submitted_by, highlight_content, book_title, book_author, jam_poll_votes(user_id))')
        .eq('jam_id', jamId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<void> createPoll({
    required String jamId,
    required String title,
    required DateTime endsAt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_highlight_polls').insert({
      'jam_id': jamId,
      'created_by': userId,
      'title': title.trim(),
      'ends_at': endsAt.toIso8601String(),
    });
  }

  Future<void> submitPollCandidate({
    required String pollId,
    required String highlightContent,
    String? bookTitle,
    String? bookAuthor,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_poll_candidates').upsert({
      'poll_id': pollId,
      'submitted_by': userId,
      'highlight_content': highlightContent.trim(),
      'book_title': bookTitle?.trim(),
      'book_author': bookAuthor?.trim(),
    });
  }

  Future<void> voteOnPollCandidate(String candidateId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('jam_poll_votes').upsert({
      'candidate_id': candidateId,
      'user_id': userId,
    });
  }

  Future<void> unvoteOnPollCandidate(String candidateId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client
        .from('jam_poll_votes')
        .delete()
        .eq('candidate_id', candidateId)
        .eq('user_id', userId);
  }

  // ─── Jam 2.0: Notifications ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final res = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  }

  Future<int> fetchUnreadNotificationCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final res = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false)
        .count(CountOption.exact);
    return res.count;
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllNotificationsRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Registers the APNs device token for push notifications.
  ///
  /// Upserts on the table's `unique(user_id, token)` constraint (see migration
  /// 023_notifications.sql), so re-registering the SAME token for a user is a
  /// no-op-but-fresh (no duplicate-key error, no duplicate row), while a NEW
  /// token after a TestFlight update inserts a new row. Without `onConflict`,
  /// supabase-flutter defaults the conflict target to the primary key (`id`),
  /// which we never supply — so each call would generate a fresh `id` and
  /// collide with the `(user_id, token)` unique index on re-registration.
  Future<void> registerDeviceToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('device_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'platform': 'ios',
      },
      onConflict: 'user_id,token',
    );
    // Remember the token for this device so signOut() can delete exactly this
    // row (this user + this device) and not leak pushes to the next account.
    _currentDeviceToken = token;
  }

  RealtimeChannel subscribeToNotifications(
    String userId,
    void Function(Map<String, dynamic>) onNew,
  ) {
    return _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => onNew(payload.newRecord),
        )
        .subscribe();
  }
}
