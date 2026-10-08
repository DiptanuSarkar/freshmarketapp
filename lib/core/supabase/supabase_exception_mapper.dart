import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// User-facing application domain exception with sanitized message and optional code.
class AppException implements Exception {
  const AppException(this.message, {this.code, this.originalError});

  final String message;
  final String? code;
  final dynamic originalError;

  @override
  String toString() => message;
}

/// Maps raw Supabase PostgrestException, AuthException, and network errors into
/// friendly, user-safe AppException instances that never leak raw SQL or internals.
abstract final class SupabaseExceptionMapper {
  static AppException map(dynamic error, [StackTrace? stackTrace]) {
    if (error is AppException) {
      return error;
    }

    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials')) {
        return const AppException(
          'Invalid email address or password. Please try again.',
          code: 'invalid_credentials',
        );
      }
      if (msg.contains('user already registered') ||
          msg.contains('already exists')) {
        return const AppException(
          'An account with this email address already exists. Please sign in.',
          code: 'user_already_exists',
        );
      }
      if (msg.contains('email not confirmed')) {
        return const AppException(
          'Please verify your email address to continue.',
          code: 'email_not_confirmed',
        );
      }
      if (msg.contains('rate limit') || msg.contains('too many requests')) {
        return const AppException(
          'Too many requests. Please wait a moment and try again.',
          code: 'rate_limited',
        );
      }
      if (msg.contains('password') && msg.contains('short')) {
        return const AppException(
          'Password should be at least 6 characters long.',
          code: 'weak_password',
        );
      }
      return AppException(error.message, code: error.statusCode);
    }

    if (error is PostgrestException) {
      // Common PostgreSQL error codes
      switch (error.code) {
        case '23505': // unique_violation
          return const AppException(
            'A record with this information already exists.',
            code: '23505',
          );
        case '23503': // foreign_key_violation
          return const AppException(
            'The referenced item does not exist or has been removed.',
            code: '23503',
          );
        case '42501': // insufficient_privilege / RLS violation
          return const AppException(
            'Access denied. You do not have permission to perform this action.',
            code: '42501',
          );
        case 'PGRST116': // JSON result single row not found
          return const AppException(
            'Requested item not found.',
            code: 'PGRST116',
          );
        default:
          return const AppException(
            'Unable to process data request. Please try again.',
            code: 'database_error',
          );
      }
    }

    if (error is SocketException || error is TimeoutException) {
      return const AppException(
        'No internet connection. Please check your network and try again.',
        code: 'network_error',
      );
    }

    final str = error.toString().toLowerCase();
    if (str.contains('network') ||
        str.contains('connection') ||
        str.contains('socket') ||
        str.contains('clientexception')) {
      return const AppException(
        'No internet connection. Please check your network and try again.',
        code: 'network_error',
      );
    }

    return const AppException(
      'An unexpected error occurred. Please try again.',
      code: 'unknown_error',
    );
  }
}
