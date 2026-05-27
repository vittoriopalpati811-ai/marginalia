import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book.dart';
import '../models/highlight.dart';
import '../models/jam.dart';

// Thin wrapper around Supabase client. Encapsulates table names and RLS
// assumptions so screens don't need to know the schema.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

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

  Future<void> signOut() => _client.auth.signOut();

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
    final hash = sha256.convert(utf8.encode(content)).toString();
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
        .order('shared_at', ascending: false);
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
    return List<Map<String, dynamic>>.from(response as List);
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

  // ─── Follows ──────────────────────────────────────────────────────────────

  /// Follow another user (idempotent upsert).
  Future<void> followUser(String targetId) async {
    await _client.from('follows').upsert({
      'follower_id': userId,
      'following_id': targetId,
    });
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
        .order('shared_at', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  // ─── Feed (highlights shared by people I follow) ──────────────────────────

  /// Recent highlights shared by followed users across all Jams, newest first.
  Future<List<Map<String, dynamic>>> fetchFeed() async {
    if (!isAuthenticated) return [];
    final followingIds = (await fetchFollowingIds()).toList();
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

  Future<Map<String, int>> fetchUserStats(String targetId) async {
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
        .order('shared_at', ascending: false);
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

  /// Uploads avatar image to Supabase Storage and returns a public URL.
  ///
  /// Uses getPublicUrl (no expiry) — requires the 'avatars' bucket to be public,
  /// which is enforced by migration 011/012. Previously used createSignedUrl,
  /// which failed silently when bucket download policies were missing.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    await _ensureBucket('avatars');
    final path = '${userId!}/avatar.$ext';
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

  /// Uploads a Jam cover photo and updates the jam's cover_url column.
  Future<String> uploadJamCover(
      String jamId, Uint8List bytes, String ext) async {
    await _ensureBucket('jam-covers');
    final path = '$jamId/cover.$ext';
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
  }) async {
    await _client.from('posts').insert({
      'user_id': userId,
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      if (highlightSupabaseId != null) 'highlight_id': highlightSupabaseId,
      if (jamId != null) 'jam_id': jamId,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  /// Uploads an image for a post and returns the public URL.
  Future<String> uploadPostImage(Uint8List bytes, String ext) async {
    await _ensureBucket('post-images');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${userId!}/$ts.$ext';
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
    final allIds = {...followingIds, userId!}.toList();

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

    // Fetch profiles in parallel (include currently_reading for "reading X" display)
    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id, display_name, avatar_url, currently_reading_title')
              .inFilter('id', userIds) as List,
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
      };
    }).toList();
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

    return rows.map((r) => {
      ...r,
      'is_liked': likedIds.contains(r['id'] as String),
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
    final path = '$userId/$filename';
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

      result.add({
        ...conv,
        'members': profiles.where((p) => p['id'] != uid).toList(),
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

  /// Upload an image to the message-images bucket and return its public URL.
  Future<String> uploadMessageImage(
      String fileName, List<int> bytes) async {
    final path = '${userId!}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await _client.storage
        .from('message-images')
        .uploadBinary(path, bytes as dynamic);
    return _client.storage.from('message-images').getPublicUrl(path);
  }

  /// Messages for a single conversation in chronological order, with sender
  /// profiles pre-fetched.
  Future<List<Map<String, dynamic>>> fetchMessages(
      String conversationId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('messages')
          .select('id, conversation_id, sender_id, content, image_url, created_at')
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
  Future<void> sendMessage(
    String conversationId, {
    String? content,
    String? imageUrl,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': userId,
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      if (imageUrl != null) 'image_url': imageUrl,
      'created_at': now,
    });
    await _client
        .from('conversations')
        .update({'updated_at': now})
        .eq('id', conversationId);
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
    return res.count ?? 0;
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
  Future<void> registerDeviceToken(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': 'ios',
    });
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
