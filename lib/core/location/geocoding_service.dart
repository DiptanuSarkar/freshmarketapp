import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../../features/address/data/models/selected_location.dart';

abstract interface class IGeocodingService {
  Future<SelectedLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  });
}

class PlacemarkGeocodingService implements IGeocodingService {
  PlacemarkGeocodingService([Geocoding? geocoding])
    : _geocoding = geocoding ?? Geocoding();

  final Geocoding _geocoding;

  @override
  Future<SelectedLocation> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) {
        return SelectedLocation(
          latitude: latitude,
          longitude: longitude,
          errorMessage: 'No address details found for this pin location.',
        );
      }

      final place = placemarks.first;

      final street = (place.street ?? place.thoroughfare ?? '').trim();
      final area = (place.subLocality ?? place.subAdministrativeArea ?? '')
          .trim();
      final city = (place.locality ?? place.subAdministrativeArea ?? '').trim();
      final state = (place.administrativeArea ?? '').trim();
      final country = (place.country ?? 'India').trim();

      // Extract and sanitize 6-digit PIN code
      var rawPin = (place.postalCode ?? '').trim().replaceAll(
        RegExp(r'\s+'),
        '',
      );
      if (rawPin.length > 6) {
        final match = RegExp(r'\b\d{6}\b').firstMatch(rawPin);
        if (match != null) {
          rawPin = match.group(0)!;
        }
      }

      final parts = <String>[];
      if (street.isNotEmpty) parts.add(street);
      if (area.isNotEmpty && area != street) parts.add(area);
      if (city.isNotEmpty) parts.add(city);
      if (state.isNotEmpty) parts.add(state);
      if (rawPin.isNotEmpty) parts.add(rawPin);

      final formatted = parts.join(', ');

      return SelectedLocation(
        latitude: latitude,
        longitude: longitude,
        street: street,
        area: area,
        city: city,
        state: state,
        postalCode: rawPin,
        country: country,
        formattedAddress: formatted,
      );
    } catch (e) {
      // Preserve latitude and longitude even if geocoding network call fails
      return SelectedLocation(
        latitude: latitude,
        longitude: longitude,
        errorMessage: 'Unable to resolve address from coordinates: $e',
      );
    }
  }
}

final geocodingServiceProvider = Provider<IGeocodingService>((ref) {
  return PlacemarkGeocodingService();
});
