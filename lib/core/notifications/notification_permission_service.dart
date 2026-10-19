import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Service managing system push notification permissions.
class NotificationPermissionService {
  NotificationPermissionService._();
  static final NotificationPermissionService instance =
      NotificationPermissionService._();

  /// Requests notification permission from the customer.
  /// Safe to call after authentication or in settings UI.
  Future<NotificationSettings> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (kDebugMode) {
        developer.log(
          'Notification permission status: ${settings.authorizationStatus}',
          name: 'NotificationPermissionService',
        );
      }

      return settings;
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Error requesting notification permission: $e',
          name: 'NotificationPermissionService',
        );
      }
      return await FirebaseMessaging.instance.getNotificationSettings();
    }
  }

  /// Returns current notification permission authorization status.
  Future<AuthorizationStatus> getPermissionStatus() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus;
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Error checking notification permission: $e',
          name: 'NotificationPermissionService',
        );
      }
      return AuthorizationStatus.notDetermined;
    }
  }

  /// Returns true if push notifications are currently authorized.
  Future<bool> isPermissionGranted() async {
    final status = await getPermissionStatus();
    return status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
  }
}
