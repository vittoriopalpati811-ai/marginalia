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
