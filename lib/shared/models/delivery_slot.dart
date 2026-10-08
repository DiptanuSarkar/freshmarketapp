class DeliverySlot {
  const DeliverySlot({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.maxOrders = 50,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final int maxOrders;
  final bool isActive;

  factory DeliverySlot.fromJson(Map<String, dynamic> json) {
    return DeliverySlot(
      id: json['id'] as String,
      name: json['name'] as String,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      maxOrders: json['max_orders'] as int? ?? 50,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
