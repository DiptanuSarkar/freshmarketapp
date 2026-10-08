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
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String? actionRoute;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? 'system').toLowerCase();
    NotificationType nType;
    switch (rawType) {
      case 'order':
        nType = NotificationType.order;
        break;
      case 'offer':
      case 'promotion':
        nType = NotificationType.offer;
        break;
      case 'wallet':
        nType = NotificationType.wallet;
        break;
      default:
        nType = NotificationType.system;
        break;
    }

    String? route;
    if (json['data'] != null && json['data'] is Map) {
      route = (json['data'] as Map<String, dynamic>)['route'] as String?;
    }

    return NotificationItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String? ?? '',
      type: nType,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      actionRoute: route,
    );
  }
}
