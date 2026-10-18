import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'location_exceptions.dart';

abstract interface class ILocationService {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position?> getLastKnownPosition();
  Future<Position> getCurrentPosition({Duration timeout});
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorLocationService implements ILocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> isLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermission> checkPermission() async {
    return Geolocator.checkPermission();
  }

  @override
  Future<LocationPermission> requestPermission() async {
    return Geolocator.requestPermission();
  }

  @override
  Future<Position?> getLastKnownPosition() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) return null;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Position> getCurrentPosition({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      throw const LocationServiceDisabledFailure();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationPermissionDeniedFailure();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedForeverFailure();
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } on TimeoutException {
      throw const LocationTimeoutFailure();
    } catch (e) {
      if (e is LocationFailure) rethrow;
      throw LocationGenericFailure(e.toString());
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

final locationServiceProvider = Provider<ILocationService>((ref) {
  return const GeolocatorLocationService();
});
