import '../../core/notifications/notification_payload.dart';

enum NotificationType { order, offer, wallet, system }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.actionRoute,
    this.orderId,
    this.data = const {},
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String? actionRoute;
  final String? orderId;
  final Map<String, dynamic> data;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? 'system').toLowerCase();
    NotificationType nType;

    if (rawType.startsWith('order') || rawType.startsWith('payment')) {
      nType = NotificationType.order;
    } else if (rawType == 'offer' || rawType == 'promotion') {
      nType = NotificationType.offer;
    } else if (rawType.startsWith('refund') || rawType.startsWith('wallet')) {
      nType = NotificationType.wallet;
    } else {
      nType = NotificationType.system;
    }

    String? route;
    String? oId;
    Map<String, dynamic> rawDataMap = const {};

    if (json['data'] != null && json['data'] is Map) {
      rawDataMap = Map<String, dynamic>.from(json['data'] as Map);
      oId = rawDataMap['order_id'] as String?;

      if (rawDataMap.containsKey('route') &&
          rawDataMap['route'] is String &&
          (rawDataMap['route'] as String).isNotEmpty) {
        route = rawDataMap['route'] as String;
      } else {
        final payload = NotificationPayload.fromMap({
          'type': rawType,
          ...rawDataMap,
        });
        route = payload.targetRoute;
      }
    }

    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String? ?? '',
      type: nType,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      actionRoute: route,
      orderId: oId,
      data: rawDataMap,
    );
  }

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? createdAt,
    bool? isRead,
    String? actionRoute,
    String? orderId,
    Map<String, dynamic>? data,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      actionRoute: actionRoute ?? this.actionRoute,
      orderId: orderId ?? this.orderId,
      data: data ?? this.data,
    );
  }
}
