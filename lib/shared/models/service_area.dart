class ServiceArea {
  const ServiceArea({
    required this.id,
    required this.name,
    required this.pincode,
    required this.city,
    this.deliveryCharge = 30.0,
    this.minOrderForFreeDelivery = 499.0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String pincode;
  final String city;
  final double deliveryCharge;
  final double minOrderForFreeDelivery;
  final bool isActive;

  String get areaName => name;

  factory ServiceArea.fromJson(Map<String, dynamic> json) {
    return ServiceArea(
      id: json['id'] as String,
      name: json['name'] as String,
      pincode: json['pincode'] as String,
      city: json['city'] as String,
      deliveryCharge: (json['delivery_charge'] as num?)?.toDouble() ?? 30.0,
      minOrderForFreeDelivery:
          (json['min_order_for_free_delivery'] as num?)?.toDouble() ?? 499.0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
