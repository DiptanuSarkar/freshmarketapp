import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_navigation_service.dart';

/// Service managing customer FCM device token lifecycle:
/// registration, refresh, logout deactivation, and multi-user isolation on shared devices.
class FcmTokenService {
  FcmTokenService._();
  static final FcmTokenService instance = FcmTokenService._();

  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastRegisteredToken;

  /// Masks token for safe logging. Never logs complete FCM token.
  static String maskToken(String? token) {
    if (token == null || token.isEmpty) return '<null>';
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }

  /// Initializes token listeners and registers current device token if user is signed in.
  Future<void> initialize() async {
    // Listen for FCM token refresh
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((newToken) {
          if (kDebugMode) {
            developer.log(
              'FCM token refreshed: ${maskToken(newToken)}',
              name: 'FcmTokenService',
            );
          }
          syncToken(newToken);
        });

    // Listen to Supabase auth state transitions
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        syncCurrentToken();
        NotificationNavigationService.instance.onUserAuthenticated();
      }
    });

    // Check if session is already active
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await syncCurrentToken();
    }
  }

  /// Fetches the current FCM token from Firebase.
  Future<String?> getCurrentToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      if (kDebugMode) {
        developer.log('Failed to get FCM token: $e', name: 'FcmTokenService');
      }
      return null;
    }
  }

  /// Syncs current device token with Supabase for the authenticated user.
  Future<void> syncCurrentToken() async {
    final token = await getCurrentToken();
    if (token != null && token.isNotEmpty) {
      await syncToken(token);
    }
  }

  /// Registers given token with Supabase backend.
  Future<void> syncToken(String token) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        developer.log(
          'Skipping token registration: No authenticated user',
          name: 'FcmTokenService',
        );
      }
      return;
    }

    try {
      final deviceType = Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'web');

      // Preferred: Call register-fcm-token Edge Function
      try {
        final res = await client.functions.invoke(
          'register-fcm-token',
          body: {'token': token, 'device_type': deviceType},
        );
        if (res.status == 200) {
          _lastRegisteredToken = token;
          if (kDebugMode) {
            developer.log(
              'FCM token registered via Edge Function: ${maskToken(token)}',
              name: 'FcmTokenService',
            );
          }
          return;
        }
      } catch (efError) {
        if (kDebugMode) {
          developer.log(
            'register-fcm-token Edge Function failed, falling back to RPC: $efError',
            name: 'FcmTokenService',
          );
        }
      }

      // Fallback: Call rpc_register_fcm_token
      await client.rpc(
        'rpc_register_fcm_token',
        params: {'p_token': token, 'p_device_type': deviceType},
      );
      _lastRegisteredToken = token;
      if (kDebugMode) {
        developer.log(
          'FCM token registered via RPC: ${maskToken(token)}',
          name: 'FcmTokenService',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Failed to register FCM token: $e',
          name: 'FcmTokenService',
        );
      }
    }
  }

  /// Deactivates current device token on user logout.
  /// Does not throw or block logout if network is unavailable.
  Future<void> unregisterOnLogout() async {
    final token = _lastRegisteredToken ?? await getCurrentToken();
    if (token == null || token.isEmpty) return;

    final client = Supabase.instance.client;

    try {
      // Preferred: Call unregister-fcm-token Edge Function
      try {
        await client.functions.invoke(
          'unregister-fcm-token',
          body: {'token': token},
        );
      } catch (_) {
        // Fallback: Call rpc_unregister_fcm_token
        await client.rpc(
          'rpc_unregister_fcm_token',
          params: {'p_token': token},
        );
      }

      if (kDebugMode) {
        developer.log(
          'FCM token deactivated on logout: ${maskToken(token)}',
          name: 'FcmTokenService',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Failed to unregister FCM token on logout: $e',
          name: 'FcmTokenService',
        );
      }
    } finally {
      _lastRegisteredToken = null;
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }
}
