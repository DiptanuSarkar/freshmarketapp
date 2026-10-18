/// Typed exceptions for location and GPS operations.
sealed class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class LocationServiceDisabledFailure extends LocationFailure {
  const LocationServiceDisabledFailure([
    super.message =
        'Location services are disabled on your device. Please turn on GPS.',
  ]) : super(code: 'service_disabled');
}

class LocationPermissionDeniedFailure extends LocationFailure {
  const LocationPermissionDeniedFailure([
    super.message = 'Location permission was denied. Please grant location access to pick your delivery address.',
  ]) : super(code: 'permission_denied');
}

class LocationPermissionDeniedForeverFailure extends LocationFailure {
  const LocationPermissionDeniedForeverFailure([
    super.message = 'Location permission is permanently denied. Please enable location access in App Settings.',
  ]) : super(code: 'permission_denied_forever');
}

class LocationTimeoutFailure extends LocationFailure {
  const LocationTimeoutFailure([
    super.message = 'Location request timed out. Please retry or choose your location on the map.',
  ]) : super(code: 'timeout');
}

class LocationGenericFailure extends LocationFailure {
  const LocationGenericFailure(
    super.message, {
    super.code = 'location_generic_error',
  });
}

class GeocodingFailure implements Exception {
  const GeocodingFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
