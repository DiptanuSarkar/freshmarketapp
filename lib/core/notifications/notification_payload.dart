import 'dart:convert';

/// Whitelisted and strictly-typed notification payload for FreshMarket customer app.
/// Prevents untrusted route navigation and ensures robust parsing.
class NotificationPayload {
  const NotificationPayload({
    required this.type,
    this.id,
    this.orderId,
    this.orderNumber,
    this.paymentId,
    this.refundId,
    this.rawData = const {},
  });

  final String? id;
  final String type;
  final String? orderId;
  final String? orderNumber;
  final String? paymentId;
  final String? refundId;
  final Map<String, dynamic> rawData;

  /// Creates a [NotificationPayload] from a raw map (e.g. FCM RemoteMessage.data or Supabase jsonb).
  factory NotificationPayload.fromMap(Map<String, dynamic> data) {
    // Some providers may serialize nested data as JSON strings
    Map<String, dynamic> normalized = Map<String, dynamic>.from(data);
    if (normalized.containsKey('payload') && normalized['payload'] is String) {
      try {
        final decoded = jsonDecode(normalized['payload'] as String);
        if (decoded is Map<String, dynamic>) {
          normalized.addAll(decoded);
        }
      } catch (_) {}
    }

    final rawType = (normalized['type'] as String? ?? 'general')
        .toLowerCase()
        .trim();
    final notifId =
        normalized['notification_id'] as String? ?? normalized['id'] as String?;
    final oId = normalized['order_id'] as String?;
    final oNum = normalized['order_number'] as String?;
    final pId = normalized['payment_id'] as String?;
    final rId = normalized['refund_id'] as String?;

    return NotificationPayload(
      type: rawType,
      id: notifId,
      orderId: oId,
      orderNumber: oNum,
      paymentId: pId,
      refundId: rId,
      rawData: normalized,
    );
  }

  /// Maps payload to a safe, whitelisted in-app route.
  /// Never executes arbitrary URLs or route strings from remote payloads.
  String get targetRoute {
    switch (type) {
      // Order status updates
      case 'order_placed':
      case 'order_confirmed':
      case 'order_preparing':
      case 'order_packed':
      case 'order_out_for_delivery':
      case 'order_delivered':
      case 'order_cancelled':
        if (orderId != null && orderId!.isNotEmpty) {
          return '/orders/$orderId';
        }
        return '/orders';

      // Payment status updates
      case 'payment_completed':
      case 'payment_failed':
      case 'payment_pending':
        if (orderId != null && orderId!.isNotEmpty) {
          return '/orders/$orderId';
        }
        return '/orders';

      // Refund status updates
      case 'refund_initiated':
      case 'refund_processing':
      case 'refund_processed':
      case 'refund_failed':
        if (orderId != null && orderId!.isNotEmpty) {
          return '/orders/$orderId';
        }
        return '/wallet';

      // Wallet credit / wallet refund updates
      case 'wallet_refund':
      case 'wallet_credit':
      case 'wallet':
        return '/wallet';

      // General / Unknown fallback
      case 'general':
      case 'system':
      case 'offer':
      default:
        return '/notifications';
    }
  }

  /// Android notification channel ID corresponding to this payload type.
  String get channelId {
    if (type.startsWith('order_')) {
      return 'freshmarket_orders';
    }
    if (type.startsWith('payment_')) {
      return 'freshmarket_payments';
    }
    if (type.startsWith('refund_') || type.startsWith('wallet_')) {
      return 'freshmarket_refunds';
    }
    return 'freshmarket_general';
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'type': type,
    if (orderId != null) 'order_id': orderId,
    if (orderNumber != null) 'order_number': orderNumber,
    if (paymentId != null) 'payment_id': paymentId,
    if (refundId != null) 'refund_id': refundId,
    ...rawData,
  };
}
