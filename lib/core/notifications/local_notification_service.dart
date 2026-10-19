import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_payload.dart';

/// Service managing Android Notification Channels and local foreground notification presentation.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  void Function(NotificationPayload payload)? _onNotificationTapped;

  // Channel IDs
  static const String channelOrders = 'freshmarket_orders';
  static const String channelPayments = 'freshmarket_payments';
  static const String channelRefunds = 'freshmarket_refunds';
  static const String channelGeneral = 'freshmarket_general';

  /// Initializes flutter_local_notifications plugin and registers Android notification channels.
  Future<void> initialize({
    required void Function(NotificationPayload payload) onNotificationTapped,
  }) async {
    if (_isInitialized) return;
    _onNotificationTapped = onNotificationTapped;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.payload!);
            if (decoded is Map<String, dynamic>) {
              final payload = NotificationPayload.fromMap(decoded);
              _onNotificationTapped?.call(payload);
            }
          } catch (e) {
            if (kDebugMode) {
              developer.log(
                'Error parsing local notification payload: $e',
                name: 'LocalNotificationService',
              );
            }
          }
        }
      },
    );

    // Create Android Notification Channels
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelOrders,
          'Order Updates',
          description:
              'Updates on order placement, preparation, and live delivery.',
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelPayments,
          'Payment Updates',
          description:
              'Notifications for successful payments and transaction status.',
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelRefunds,
          'Refund Updates',
          description: 'Notifications for refund initiation, processing, and wallet credits.',
          importance: Importance.high,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelGeneral,
          'FreshMarket Updates',
          description: 'General system announcements and account updates.',
          importance: Importance.defaultImportance,
        ),
      );
    }

    _isInitialized = true;
  }

  /// Displays a local heads-up notification for foreground FCM messages.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    NotificationPayload? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(channelId),
      channelDescription: _getChannelDescription(channelId),
      importance: channelId == channelGeneral
          ? Importance.defaultImportance
          : Importance.high,
      priority: channelId == channelGeneral
          ? Priority.defaultPriority
          : Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    final payloadString = payload != null ? jsonEncode(payload.toMap()) : null;

    await _plugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payloadString,
    );
  }

  String _getChannelName(String channelId) {
    switch (channelId) {
      case channelOrders:
        return 'Order Updates';
      case channelPayments:
        return 'Payment Updates';
      case channelRefunds:
        return 'Refund Updates';
      case channelGeneral:
      default:
        return 'FreshMarket Updates';
    }
  }

  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case channelOrders:
        return 'Updates on order placement, preparation, and live delivery.';
      case channelPayments:
        return 'Notifications for successful payments and transaction status.';
      case channelRefunds:
        return 'Notifications for refund initiation, processing, and wallet credits.';
      case channelGeneral:
      default:
        return 'General system announcements and account updates.';
    }
  }
}
