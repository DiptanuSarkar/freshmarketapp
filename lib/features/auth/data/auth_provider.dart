import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

class AuthNotifier extends Notifier<AsyncValue<User?>> {
  @override
  AsyncValue<User?> build() {
    final repo = ref.watch(authRepositoryProvider);
    repo.authStateChanges.listen((data) {
      state = AsyncValue.data(data.session?.user);
    });
    return AsyncValue.data(repo.currentUser);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    state = const AsyncValue.loading();
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(
            email: email,
            password: password,
            fullName: fullName,
            phone: phone ?? '',
          );
      state = AsyncValue.data(res.user);
      return res;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final res = await ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: password);
      state = AsyncValue.data(res.user);
      return res;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AuthResponse> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      final res = await ref.read(authRepositoryProvider).signInWithGoogle();
      state = AsyncValue.data(res.user);
      return res;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> resetPassword({required String email}) async {
    await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    try {
      await ref.read(authRepositoryProvider).signOut();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AsyncValue<User?>>(
  AuthNotifier.new,
);
