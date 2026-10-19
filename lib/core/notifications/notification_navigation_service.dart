import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_router.dart';
import 'notification_payload.dart';

/// Central navigation coordinator for notifications.
/// Ensures deep-links are navigated once, routes are safe, and
/// handles logged-out -> login -> target route resumption.
class NotificationNavigationService {
  NotificationNavigationService._();
  static final NotificationNavigationService instance =
      NotificationNavigationService._();

  String? _pendingRoute;
  final Set<String> _handledIdentifiers = <String>{};

  /// Handles incoming notification navigation payload.
  void handleNotificationTap(NotificationPayload payload) {
    final route = payload.targetRoute;
    final dedupeKey =
        '${payload.type}_${payload.id ?? payload.orderId ?? route}';

    // Prevent immediate duplicate navigation for same notification click
    if (_handledIdentifiers.contains(dedupeKey)) {
      if (kDebugMode) {
        developer.log(
          'Ignoring duplicate notification navigation for key: $dedupeKey',
          name: 'NotificationNavigationService',
        );
      }
      return;
    }
    _handledIdentifiers.add(dedupeKey);

    // Keep dedupe set bounded
    if (_handledIdentifiers.length > 50) {
      _handledIdentifiers.clear();
      _handledIdentifiers.add(dedupeKey);
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null && _isProtectedRoute(route)) {
      if (kDebugMode) {
        developer.log(
          'User logged out. Preserving pending destination: $route',
          name: 'NotificationNavigationService',
        );
      }
      _pendingRoute = route;
      return;
    }

    _navigateNow(route);
  }

  /// Called after successful authentication to execute any deferred deep links.
  void onUserAuthenticated() {
    if (_pendingRoute != null) {
      final route = _pendingRoute!;
      _pendingRoute = null;
      if (kDebugMode) {
        developer.log(
          'Executing deferred notification navigation: $route',
          name: 'NotificationNavigationService',
        );
      }
      _navigateNow(route);
    }
  }

  void _navigateNow(String route) {
    try {
      AppRouter.router.push(route);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Failed to navigate to route $route: $e',
          name: 'NotificationNavigationService',
          error: e,
          stackTrace: stackTrace,
        );
      }
      // Fallback to safe notifications route
      try {
        AppRouter.router.push('/notifications');
      } catch (_) {}
    }
  }

  bool _isProtectedRoute(String route) {
    const protected = [
      '/orders',
      '/account',
      '/wallet',
      '/notifications',
      '/checkout',
      '/addresses',
    ];
    return protected.any((p) => route == p || route.startsWith('$p/'));
  }
}
