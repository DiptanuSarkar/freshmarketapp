import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'fcm_token_service.dart';
import 'local_notification_service.dart';
import 'notification_navigation_service.dart';
import 'notification_payload.dart';

/// Top-level background message handler satisfying FlutterFire isolate requirements.
/// Never accesses BuildContext, Riverpod widget state, or GoRouter.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  if (kDebugMode) {
    developer.log(
      'FCM background message received: messageId=${message.messageId}, type=${message.data['type']}',
      name: 'FCMBackgroundHandler',
    );
  }
  // Keep background isolate work minimal. Commerce state is handled authoritatively by backend.
}

/// Dedicated bootstrap service for Firebase Cloud Messaging & Local Notifications.
/// Guarantees FreshMarket startup never hangs or permanently fails if Firebase is temporarily unavailable.
class NotificationBootstrap {
  NotificationBootstrap._();

  static bool _isInitialized = false;
  static VoidCallback? onForegroundMessageReceived;

  /// Initializes Firebase and notification subsystems safely.
  static Future<void> initialize({VoidCallback? onForegroundMessage}) async {
    if (_isInitialized) return;
    onForegroundMessageReceived = onForegroundMessage;

    // 1. Initialize Firebase safely
    try {
      await Firebase.initializeApp();
      if (kDebugMode) {
        developer.log(
          'Firebase initialized successfully',
          name: 'NotificationBootstrap',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        developer.log(
          'Firebase initialization failed (continuing app launch safely): $e',
          name: 'NotificationBootstrap',
          error: e,
          stackTrace: stackTrace,
        );
      }
      // Return early but gracefully: core Supabase app stays completely usable!
      return;
    }

    // 2. Initialize local notifications
    try {
      await LocalNotificationService.instance.initialize(
        onNotificationTapped: (payload) {
          NotificationNavigationService.instance.handleNotificationTap(payload);
        },
      );
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Local notifications initialization error: $e',
          name: 'NotificationBootstrap',
        );
      }
    }

    // 3. Register top-level background handler
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Error setting background message handler: $e',
          name: 'NotificationBootstrap',
        );
      }
    }

    // 4. Handle terminated notification tap (cold launch)
    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          developer.log(
            'App opened from terminated state by notification: ${initialMessage.messageId}',
            name: 'NotificationBootstrap',
          );
        }
        final payload = NotificationPayload.fromMap(initialMessage.data);
        NotificationNavigationService.instance.handleNotificationTap(payload);
      }
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Error checking initial notification message: $e',
          name: 'NotificationBootstrap',
        );
      }
    }

    // 5. Handle background notification tap (app resumed from background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        developer.log(
          'App opened from background by notification: ${message.messageId}',
          name: 'NotificationBootstrap',
        );
      }
      final payload = NotificationPayload.fromMap(message.data);
      NotificationNavigationService.instance.handleNotificationTap(payload);
    });

    // 6. Handle foreground push delivery
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        developer.log(
          'FCM foreground message received: ${message.messageId}, data=${message.data}',
          name: 'NotificationBootstrap',
        );
      }

      final payload = NotificationPayload.fromMap(message.data);

      final title =
          message.notification?.title ??
          message.data['title'] as String? ??
          'FreshMarket';
      final body =
          message.notification?.body ?? message.data['body'] as String? ?? '';

      // Show local notification for foreground message
      final notifId =
          (message.messageId ??
                  message.sentTime?.millisecondsSinceEpoch.toString() ??
                  DateTime.now().millisecondsSinceEpoch.toString())
              .hashCode;

      await LocalNotificationService.instance.showNotification(
        id: notifId,
        title: title,
        body: body,
        channelId: payload.channelId,
        payload: payload,
      );

      // Notify UI callback to refresh in-app notification list and badge
      onForegroundMessageReceived?.call();
    });

    // 7. Initialize FCM token service
    try {
      await FcmTokenService.instance.initialize();
    } catch (e) {
      if (kDebugMode) {
        developer.log(
          'Error initializing FcmTokenService: $e',
          name: 'NotificationBootstrap',
        );
      }
    }

    _isInitialized = true;
  }
}
