import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_repository.dart';

sealed class AppAuthState {
  const AppAuthState();
}

class AuthInitial extends AppAuthState {
  const AuthInitial();
}

class AuthLoading extends AppAuthState {
  const AuthLoading();
}

class Authenticated extends AppAuthState {
  const Authenticated(this.user);
  final User user;
}

class Unauthenticated extends AppAuthState {
  const Unauthenticated();
}

class AuthError extends AppAuthState {
  const AuthError(this.message);
  final String message;
}

class AuthNotifier extends Notifier<AppAuthState> {
  @override
  AppAuthState build() {
    final authRepo = ref.watch(authRepositoryProvider);
    final user = authRepo.currentUser;
    if (user != null) {
      return Authenticated(user);
    }
    return const Unauthenticated();
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final response = await authRepo.signInWithEmail(
        email: email,
        password: password,
      );
      if (response.user != null) {
        state = Authenticated(response.user!);
        return true;
      } else {
        state = const Unauthenticated();
        return false;
      }
    } catch (e) {
      state = AuthError(e.toString());
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    state = const AuthLoading();
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final response = await authRepo.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
      if (response.user != null) {
        state = Authenticated(response.user!);
        return true;
      } else {
        state = const Unauthenticated();
        return false;
      }
    } catch (e) {
      state = AuthError(e.toString());
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    state = const AuthLoading();
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final response = await authRepo.signInWithGoogle();
      if (response.user != null) {
        state = Authenticated(response.user!);
        return true;
      } else {
        state = const Unauthenticated();
        return false;
      }
    } catch (e) {
      state = AuthError(e.toString());
      return false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.sendPasswordResetEmail(email);
  }

  Future<void> signOut() async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.signOut();
    state = const Unauthenticated();
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AppAuthState>(
  AuthNotifier.new,
);
