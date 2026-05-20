import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  // ─── Auth ─────────────────────────────────────────────────────────────────

  Future<AuthResponse> signInWithEmail(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUpWithEmail(String email, String password) =>
      _client.auth.signUp(email: email, password: password);

  Future<void> signOut() => _client.auth.signOut();

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
              .select(
                  'id, display_name, currently_reading_title, currently_reading_author')
              .inFilter('id', ids) as List,
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
                  'id, display_name, currently_reading_title, currently_reading_author')
              .inFilter('id', ids) as List,
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
                  'id, display_name, currently_reading_title, currently_reading_author')
              .inFilter('id', suggestionIds) as List,
    );
  }

  // ─── Profile stats ─────────────────────────────────────────────────────────

  Future<void> updateDisplayName(String displayName) async {
    await _client
        .from('profiles')
        .update({'display_name': displayName}).eq('id', userId!);
  }

  /// Update multiple profile fields at once.
  Future<void> updateProfileInfo({
    String? displayName,
    String? bio,
    String? currentlyReadingTitle,
    String? currentlyReadingAuthor,
  }) async {
    if (!isAuthenticated || userId == null) return;
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (bio != null) data['bio'] = bio;
    if (currentlyReadingTitle != null) data['currently_reading_title'] = currentlyReadingTitle;
    if (currentlyReadingAuthor != null) data['currently_reading_author'] = currentlyReadingAuthor;
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

  Future<Map<String, dynamic>?> fetchPublicProfile(String targetId) async {
    return await _client
        .from('profiles')
        .select()
        .eq('id', targetId)
        .maybeSingle();
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

  /// Uploads avatar image to Supabase Storage and returns a signed URL.
  ///
  /// Uses createSignedUrl (1-year expiry) instead of getPublicUrl so images
  /// load correctly regardless of whether the bucket's public flag is set —
  /// the signed URL is self-contained and works for any viewer who has it.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    await _ensureBucket('avatars');
    final path = '${userId!}/avatar.$ext';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    // Signed URL valid for 1 year (31 536 000 s). Works even if the bucket is
    // private, and the token bakes in a timestamp so the cache is always fresh.
    final url = await _client.storage
        .from('avatars')
        .createSignedUrl(path, 31536000);
    await _client.from('profiles').update({'avatar_url': url}).eq('id', userId!);
    return url;
  }

  /// Uploads cover photo to Supabase Storage and returns a signed URL.
  Future<String> uploadCover(Uint8List bytes, String ext) async {
    await _ensureBucket('covers');
    final path = '${userId!}/cover.$ext';
    await _client.storage.from('covers').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    final url = await _client.storage
        .from('covers')
        .createSignedUrl(path, 31536000);
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
    final url = _client.storage.from('jam-covers').getPublicUrl(path);
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

    // Fetch profiles in parallel
    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    final profiles = List<Map<String, dynamic>>.from(
      await _client
              .from('profiles')
              .select('id, display_name, avatar_url')
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
}
