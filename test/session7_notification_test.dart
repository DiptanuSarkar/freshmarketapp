import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/core/notifications/notification_payload.dart';
import 'package:freshmarket/shared/models/notification_item.dart';

void main() {
  group('Session 7 Notification Payload Parsing & Whitelist Routing', () {
    test('Parses order_placed payload and routes to order details', () {
      final raw = {
        'id': 'notif-1',
        'type': 'order_placed',
        'order_id': 'ord-1234',
        'order_number': 'FM-2026-001',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('order_placed'));
      expect(payload.orderId, equals('ord-1234'));
      expect(payload.orderNumber, equals('FM-2026-001'));
      expect(payload.targetRoute, equals('/orders/ord-1234'));
      expect(payload.channelId, equals('freshmarket_orders'));
    });

    test('Parses order_confirmed payload and routes to order details', () {
      final raw = {
        'id': 'notif-2',
        'type': 'order_confirmed',
        'order_id': 'ord-5678',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('order_confirmed'));
      expect(payload.targetRoute, equals('/orders/ord-5678'));
      expect(payload.channelId, equals('freshmarket_orders'));
    });

    test('Parses payment_completed payload and routes to order details', () {
      final raw = {
        'id': 'notif-3',
        'type': 'payment_completed',
        'order_id': 'ord-9999',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('payment_completed'));
      expect(payload.targetRoute, equals('/orders/ord-9999'));
      expect(payload.channelId, equals('freshmarket_payments'));
    });

    test('Parses payment_failed payload and routes to order details', () {
      final raw = {
        'id': 'notif-4',
        'type': 'payment_failed',
        'order_id': 'ord-9999',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('payment_failed'));
      expect(payload.targetRoute, equals('/orders/ord-9999'));
      expect(payload.channelId, equals('freshmarket_payments'));
    });

    test('Parses refund_processed payload and routes to order details', () {
      final raw = {
        'id': 'notif-5',
        'type': 'refund_processed',
        'order_id': 'ord-7777',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('refund_processed'));
      expect(payload.targetRoute, equals('/orders/ord-7777'));
      expect(payload.channelId, equals('freshmarket_refunds'));
    });

    test('Parses wallet_refund payload and routes to wallet', () {
      final raw = {'id': 'notif-6', 'type': 'wallet_refund'};

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('wallet_refund'));
      expect(payload.targetRoute, equals('/wallet'));
      expect(payload.channelId, equals('freshmarket_refunds'));
    });

    test('Falls back safely to /notifications on unknown payload type', () {
      final raw = {
        'id': 'notif-8',
        'type': 'promotional_blast_unknown',
        'unknown_field': 'content',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.type, equals('promotional_blast_unknown'));
      expect(payload.targetRoute, equals('/notifications'));
      expect(payload.channelId, equals('freshmarket_general'));
    });

    test('Rejects arbitrary raw network paths and enforces whitelist', () {
      final raw = {
        'id': 'notif-9',
        'type': 'unknown',
        'route': '/admin/secret-backdoor',
      };

      final payload = NotificationPayload.fromMap(raw);
      expect(payload.targetRoute, equals('/notifications'));
    });

    test('Gracefully handles empty payload map', () {
      final payload = NotificationPayload.fromMap({});
      expect(payload.type, equals('general'));
      expect(payload.targetRoute, equals('/notifications'));
      expect(payload.channelId, equals('freshmarket_general'));
    });
  });

  group('Session 7 NotificationItem Model & Backward Compatibility', () {
    test('Parses legacy Supabase notification row without data jsonb', () {
      final legacyJson = {
        'id': 'e1b2c3d4-0000-0000-0000-000000000001',
        'title': 'Legacy Notification',
        'body': 'This is an older message format.',
        'type': 'system',
        'is_read': false,
        'created_at': '2026-10-18T10:00:00.000Z',
      };

      final item = NotificationItem.fromJson(legacyJson);
      expect(item.id, equals('e1b2c3d4-0000-0000-0000-000000000001'));
      expect(item.title, equals('Legacy Notification'));
      expect(item.body, equals('This is an older message format.'));
      expect(item.type, equals(NotificationType.system));
      expect(item.isRead, isFalse);
      expect(item.orderId, isNull);
    });

    test('Parses new Session 7 notification row with data and orderId', () {
      final modernJson = {
        'id': 'e1b2c3d4-0000-0000-0000-000000000002',
        'title': 'Order Confirmed',
        'body': 'Your order FM-2026-999 has been confirmed!',
        'type': 'order_confirmed',
        'data': {'order_id': 'ord-uuid-1234', 'order_number': 'FM-2026-999'},
        'is_read': true,
        'created_at': '2026-10-19T07:55:00.000Z',
      };

      final item = NotificationItem.fromJson(modernJson);
      expect(item.id, equals('e1b2c3d4-0000-0000-0000-000000000002'));
      expect(item.title, equals('Order Confirmed'));
      expect(item.type, equals(NotificationType.order));
      expect(item.isRead, isTrue);
      expect(item.orderId, equals('ord-uuid-1234'));
      expect(item.actionRoute, equals('/orders/ord-uuid-1234'));
      expect(item.data['order_number'], equals('FM-2026-999'));
    });

    test('copyWith updates read status correctly for UI reactivity', () {
      final item = NotificationItem(
        id: 'item-1',
        title: 'Title',
        body: 'Body',
        type: NotificationType.order,
        createdAt: DateTime.now(),
        isRead: false,
      );

      final readItem = item.copyWith(isRead: true);
      expect(readItem.isRead, isTrue);
      expect(readItem.id, equals(item.id));
      expect(readItem.title, equals(item.title));
      expect(readItem.type, equals(item.type));
    });
  });
}
