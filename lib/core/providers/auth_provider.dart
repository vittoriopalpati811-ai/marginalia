import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final supabaseServiceProvider = Provider<SupabaseService>(
  (ref) => SupabaseService(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseServiceProvider).authStateChanges,
);

final currentUserProvider = Provider<User?>(
  (ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (state) => state.session?.user,
      loading: () => Supabase.instance.client.auth.currentUser,
      error: (_, __) => null,
    );
  },
);

final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider) != null,
);

/// Current user's display name, fetched from their public Supabase profile.
/// Cached for the lifetime of the provider (autoDispose = disposed when unused).
final myDisplayNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final svc = ref.watch(supabaseServiceProvider);
  if (!svc.isAuthenticated || svc.userId == null) return null;
  try {
    final p = await svc.fetchPublicProfile(svc.userId!);
    return p?['display_name'] as String?;
  } catch (_) {
    return null;
  }
});
