class UserAddress {
  const UserAddress({
    required this.id,
    required this.tag,
    required this.recipientName,
    required this.phone,
    required this.houseOrFlat,
    required this.streetOrArea,
    required this.city,
    required this.pincode,
    this.landmark,
    this.latitude = 12.9716,
    this.longitude = 77.5946,
    this.isDefault = false,
  });

  final String id;
  final String tag; // "Home", "Work", "Other"
  final String recipientName;
  final String phone;
  final String houseOrFlat;
  final String streetOrArea;
  final String? landmark;
  final String city;
  final String pincode;
  final double latitude;
  final double longitude;
  final bool isDefault;

  String get formattedAddress {
    final parts = [
      houseOrFlat,
      streetOrArea,
      if (landmark != null && landmark!.isNotEmpty) 'Near $landmark',
      '$city - $pincode',
    ];
    return parts.join(', ');
  }
}
