class UserAddress {
  const UserAddress({
    required this.id,
    required this.tag,
    required this.recipientName,
    required this.phone,
    required this.houseOrFlat,
    required this.streetOrArea,
    required this.city,
    this.state = 'Karnataka',
    required this.pincode,
    this.landmark,
    this.deliveryInstructions,
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  final String id;
  final String tag; // "Home", "Work", "Other"
  final String recipientName;
  final String phone;
  final String houseOrFlat;
  final String streetOrArea;
  final String city;
  final String state;
  final String pincode;
  final String? landmark;
  final String? deliveryInstructions;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  String get formattedAddress {
    final parts = [
      houseOrFlat,
      if (streetOrArea.isNotEmpty) streetOrArea,
      if (landmark != null && landmark!.isNotEmpty)
        (landmark!.toLowerCase().startsWith('near')
            ? landmark!
            : 'Near $landmark'),
      '$city, $state - $pincode',
    ];
    return parts.join(', ');
  }

  factory UserAddress.fromJson(Map<String, dynamic> json) {
    return UserAddress(
      id: json['id'] as String,
      tag: json['label'] as String? ?? 'Home',
      recipientName: json['recipient_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      houseOrFlat: json['address_line1'] as String? ?? '',
      streetOrArea: json['address_line2'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? 'Karnataka',
      pincode: json['pincode'] as String? ?? '',
      landmark: json['landmark'] as String?,
      deliveryInstructions: json['delivery_instructions'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsertJson(String userId) {
    return {
      'user_id': userId,
      'label': tag,
      'recipient_name': recipientName,
      'phone': phone,
      'address_line1': houseOrFlat,
      'address_line2': streetOrArea,
      'city': city,
      'state': state,
      'pincode': pincode,
      'landmark': landmark,
      'delivery_instructions': deliveryInstructions,
      'latitude': latitude,
      'longitude': longitude,
      'is_default': isDefault,
    };
  }

  UserAddress copyWith({
    String? id,
    String? tag,
    String? recipientName,
    String? phone,
    String? houseOrFlat,
    String? streetOrArea,
    String? city,
    String? state,
    String? pincode,
    String? landmark,
    String? deliveryInstructions,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) {
    return UserAddress(
      id: id ?? this.id,
      tag: tag ?? this.tag,
      recipientName: recipientName ?? this.recipientName,
      phone: phone ?? this.phone,
      houseOrFlat: houseOrFlat ?? this.houseOrFlat,
      streetOrArea: streetOrArea ?? this.streetOrArea,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      landmark: landmark ?? this.landmark,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
