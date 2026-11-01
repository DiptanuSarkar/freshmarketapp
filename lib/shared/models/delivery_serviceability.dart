class DeliveryServiceability {
  const DeliveryServiceability({
    required this.serviceable,
    required this.reasonCode,
    this.zoneId,
    this.zoneCode,
    this.zoneName,
    this.deliveryFee,
    this.freeDeliveryThreshold,
    this.minimumOrderAmount,
    this.message,
  });

  final bool serviceable;
  final String reasonCode;
  final String? zoneId;
  final String? zoneCode;
  final String? zoneName;
  final double? deliveryFee;
  final double? freeDeliveryThreshold;
  final double? minimumOrderAmount;
  final String? message;

  factory DeliveryServiceability.fromJson(Map<String, dynamic> json) {
    return DeliveryServiceability(
      serviceable: json['serviceable'] as bool? ?? false,
      reasonCode: json['reason_code'] as String? ?? 'UNKNOWN',
      zoneId: json['zone_id'] as String?,
      zoneCode: json['zone_code'] as String?,
      zoneName: json['zone_name'] as String?,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
      freeDeliveryThreshold: (json['free_delivery_threshold'] as num?)
          ?.toDouble(),
      minimumOrderAmount: (json['minimum_order_amount'] as num?)?.toDouble(),
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serviceable': serviceable,
      'reason_code': reasonCode,
      if (zoneId != null) 'zone_id': zoneId,
      if (zoneCode != null) 'zone_code': zoneCode,
      if (zoneName != null) 'zone_name': zoneName,
      if (deliveryFee != null) 'delivery_fee': deliveryFee,
      if (freeDeliveryThreshold != null)
        'free_delivery_threshold': freeDeliveryThreshold,
      if (minimumOrderAmount != null)
        'minimum_order_amount': minimumOrderAmount,
      if (message != null) 'message': message,
    };
  }

  static const unverified = DeliveryServiceability(
    serviceable: false,
    reasonCode: 'ADDRESS_NOT_MAP_VERIFIED',
    message: 'Address location must be verified on the map.',
  );

  static const outsideZone = DeliveryServiceability(
    serviceable: false,
    reasonCode: 'OUTSIDE_DELIVERY_ZONE',
    message: 'FreshMarket currently delivers only within Agartala city.',
  );

  String get badgeLabel {
    if (reasonCode == 'ADDRESS_NOT_MAP_VERIFIED') {
      return 'VERIFY ON MAP';
    }
    if (serviceable) {
      return 'DELIVERY AVAILABLE';
    }
    return 'OUTSIDE DELIVERY AREA';
  }

  String get badgeDescription {
    if (serviceable) {
      return 'FreshMarket delivers to this location in Agartala.';
    }
    return message ??
        'FreshMarket currently delivers only within Agartala city.';
  }
}
