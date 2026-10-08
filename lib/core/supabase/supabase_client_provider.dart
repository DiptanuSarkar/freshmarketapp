import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides the active [SupabaseClient] singleton.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams authentication state changes from Supabase Auth.
final authStateChangeProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// Provides the currently authenticated [User], or null if unauthenticated.
final currentUserProvider = Provider<User?>((ref) {
  // Watch auth state changes to trigger reactivity
  ref.watch(authStateChangeProvider);
  final client = ref.watch(supabaseClientProvider);
  return client.auth.currentUser;
});

/// Provides whether a customer is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});
