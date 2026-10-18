class SelectedLocation {
  const SelectedLocation({
    required this.latitude,
    required this.longitude,
    this.street = '',
    this.area = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.country = 'India',
    this.formattedAddress = '',
    this.isServiceable = false,
    this.serviceAreaName,
    this.deliveryFee,
    this.minOrderForFreeDelivery,
    this.isReverseGeocoding = false,
    this.isServiceabilityChecking = false,
    this.errorMessage,
  });

  final double latitude;
  final double longitude;
  final String street;
  final String area;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final String formattedAddress;
  final bool isServiceable;
  final String? serviceAreaName;
  final double? deliveryFee;
  final double? minOrderForFreeDelivery;
  final bool isReverseGeocoding;
  final bool isServiceabilityChecking;
  final String? errorMessage;

  bool get hasValidPostalCode {
    return RegExp(r'^\d{6}$').hasMatch(postalCode.trim());
  }

  bool get isMapVerified {
    return latitude >= -90.0 &&
        latitude <= 90.0 &&
        longitude >= -180.0 &&
        longitude <= 180.0;
  }

  SelectedLocation copyWith({
    double? latitude,
    double? longitude,
    String? street,
    String? area,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? formattedAddress,
    bool? isServiceable,
    String? serviceAreaName,
    double? deliveryFee,
    double? minOrderForFreeDelivery,
    bool? isReverseGeocoding,
    bool? isServiceabilityChecking,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return SelectedLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      street: street ?? this.street,
      area: area ?? this.area,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      formattedAddress: formattedAddress ?? this.formattedAddress,
      isServiceable: isServiceable ?? this.isServiceable,
      serviceAreaName: serviceAreaName ?? this.serviceAreaName,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      minOrderForFreeDelivery:
          minOrderForFreeDelivery ?? this.minOrderForFreeDelivery,
      isReverseGeocoding: isReverseGeocoding ?? this.isReverseGeocoding,
      isServiceabilityChecking:
          isServiceabilityChecking ?? this.isServiceabilityChecking,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() {
    return 'SelectedLocation($latitude, $longitude, PIN: $postalCode, serviceable: $isServiceable)';
  }
}
