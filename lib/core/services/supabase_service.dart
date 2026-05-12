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
