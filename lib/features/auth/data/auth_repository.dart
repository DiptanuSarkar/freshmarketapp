import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';

abstract interface class IAuthRepository {
  User? get currentUser;
  Session? get currentSession;
  Stream<AuthState> get authStateChanges;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  });

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthResponse> signInWithGoogle();

  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();
}

class SupabaseAuthRepository implements IAuthRepository {
  SupabaseAuthRepository({
    required SupabaseClient supabaseClient,
    GoogleSignIn? googleSignIn,
  }) : _supabase = supabaseClient,
       _googleSignIn = googleSignIn ?? GoogleSignIn();

  final SupabaseClient _supabase;
  final GoogleSignIn _googleSignIn;

  @override
  User? get currentUser => _supabase.auth.currentUser;

  @override
  Session? get currentSession => _supabase.auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      final normalizedPhone = phone.trim().replaceAll(' ', '');
      final response = await _supabase.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {'full_name': fullName.trim(), 'phone': normalizedPhone},
      );
      return response;
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return response;
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AppException(
          'Google Sign-In was cancelled.',
          code: 'google_cancelled',
        );
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw const AppException(
          'Google Sign-In configuration error: missing ID Token. '
          'Please ensure Google Web Client ID is configured in your project.',
          code: 'google_missing_token',
        );
      }

      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      return response;
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim().toLowerCase());
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore Google Sign-In signout failures
    }
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseAuthRepository(supabaseClient: supabase);
});
