import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/core/location/location_exceptions.dart';
import 'package:freshmarket/features/address/data/models/selected_location.dart';
import 'package:freshmarket/shared/models/address.dart';

void main() {
  group('Phase 14 & 23: UserAddress.isMapVerified Semantics', () {
    test('returns true when valid coordinates are provided', () {
      const address = UserAddress(
        id: 'addr-1',
        tag: 'Home',
        recipientName: 'Alice',
        phone: '9876543210',
        houseOrFlat: 'Flat 101',
        streetOrArea: 'Indiranagar',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560038',
        latitude: 12.9716,
        longitude: 77.5946,
      );

      expect(address.isMapVerified, isTrue);
    });

    test('returns false when latitude or longitude is null', () {
      const legacyAddress = UserAddress(
        id: 'addr-legacy',
        tag: 'Home',
        recipientName: 'Bob',
        phone: '9876543211',
        houseOrFlat: '456 5th Block',
        streetOrArea: 'Koramangala',
        city: 'Bengaluru',
        pincode: '560034',
        latitude: null,
        longitude: null,
      );

      expect(legacyAddress.isMapVerified, isFalse);

      const partialLat = UserAddress(
        id: 'addr-part-1',
        tag: 'Work',
        recipientName: 'Bob',
        phone: '9876543211',
        houseOrFlat: 'Office 2B',
        streetOrArea: 'HSR',
        city: 'Bengaluru',
        pincode: '560102',
        latitude: 12.9100,
        longitude: null,
      );
      expect(partialLat.isMapVerified, isFalse);

      const partialLng = UserAddress(
        id: 'addr-part-2',
        tag: 'Work',
        recipientName: 'Bob',
        phone: '9876543211',
        houseOrFlat: 'Office 2B',
        streetOrArea: 'HSR',
        city: 'Bengaluru',
        pincode: '560102',
        latitude: null,
        longitude: 77.6400,
      );
      expect(partialLng.isMapVerified, isFalse);
    });

    test('returns false when coordinates exceed geographical boundaries', () {
      const outOfBoundsLat = UserAddress(
        id: 'addr-invalid-lat',
        tag: 'Other',
        recipientName: 'Alice',
        phone: '9876543210',
        houseOrFlat: '1',
        streetOrArea: 'Main',
        city: 'Bengaluru',
        pincode: '560038',
        latitude: 91.5,
        longitude: 77.5946,
      );
      expect(outOfBoundsLat.isMapVerified, isFalse);

      const outOfBoundsLng = UserAddress(
        id: 'addr-invalid-lng',
        tag: 'Other',
        recipientName: 'Alice',
        phone: '9876543210',
        houseOrFlat: '1',
        streetOrArea: 'Main',
        city: 'Bengaluru',
        pincode: '560038',
        latitude: 12.9716,
        longitude: 181.0,
      );
      expect(outOfBoundsLng.isMapVerified, isFalse);
    });
  });

  group('Phase 9 & 23: Coordinate Serialization & Parsing', () {
    test('UserAddress.fromJson parses coordinates from json correctly', () {
      final json = {
        'id': 'a1000000-0000-0000-0000-000000000001',
        'label': 'Home',
        'recipient_name': 'Test User',
        'phone': '9876543210',
        'address_line1': 'Flat 302',
        'address_line2': '12th Cross',
        'city': 'Bengaluru',
        'state': 'Karnataka',
        'pincode': '560038',
        'landmark': 'Near Metro',
        'latitude': 12.9785,
        'longitude': 77.6408,
        'is_default': true,
      };

      final address = UserAddress.fromJson(json);

      expect(address.id, equals('a1000000-0000-0000-0000-000000000001'));
      expect(address.tag, equals('Home'));
      expect(address.latitude, equals(12.9785));
      expect(address.longitude, equals(77.6408));
      expect(address.isMapVerified, isTrue);
      expect(address.landmark, equals('Near Metro'));
    });

    test('UserAddress.toInsertJson serializes coordinates properly', () {
      const address = UserAddress(
        id: 'temp-id',
        tag: 'Work',
        recipientName: 'Alice',
        phone: '9876543210',
        houseOrFlat: 'Floor 4, Tower 1',
        streetOrArea: 'Embassy TechVillage',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560103',
        landmark: 'Near Outer Ring Road',
        latitude: 12.9298,
        longitude: 77.6834,
        isDefault: false,
      );

      final json = address.toInsertJson('user-uuid-123');

      expect(json['user_id'], equals('user-uuid-123'));
      expect(json['label'], equals('Work'));
      expect(json['address_line1'], equals('Floor 4, Tower 1'));
      expect(json['latitude'], equals(12.9298));
      expect(json['longitude'], equals(77.6834));
      expect(json['pincode'], equals('560103'));
      expect(json['is_default'], isFalse);
    });

    test('UserAddress.copyWith preserves and updates coordinates', () {
      const original = UserAddress(
        id: 'orig-id',
        tag: 'Home',
        recipientName: 'Original Name',
        phone: '9876543210',
        houseOrFlat: 'Old House',
        streetOrArea: 'Old Street',
        city: 'Bengaluru',
        pincode: '560038',
        latitude: null,
        longitude: null,
      );

      expect(original.isMapVerified, isFalse);

      final verified = original.copyWith(
        latitude: 12.9716,
        longitude: 77.5946,
        houseOrFlat: 'New Flat 101',
      );

      expect(verified.isMapVerified, isTrue);
      expect(verified.latitude, equals(12.9716));
      expect(verified.longitude, equals(77.5946));
      expect(verified.houseOrFlat, equals('New Flat 101'));
      expect(verified.id, equals('orig-id'));
    });
  });

  group('Phase 8 & 9: SelectedLocation & Reverse Geocode Model Parsing', () {
    test('SelectedLocation parses postal code and validates 6-digit PIN', () {
      const validLoc = SelectedLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        area: 'Indiranagar',
        city: 'Bengaluru',
        state: 'Karnataka',
        postalCode: '560038',
      );

      expect(validLoc.hasValidPostalCode, isTrue);
      expect(validLoc.isMapVerified, isTrue);
    });

    test('SelectedLocation rejects invalid or malformed postal codes', () {
      const invalidPin1 = SelectedLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        postalCode: '5600',
      );
      expect(invalidPin1.hasValidPostalCode, isFalse);

      const invalidPin2 = SelectedLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        postalCode: '5600388',
      );
      expect(invalidPin2.hasValidPostalCode, isFalse);

      const invalidPinAlpha = SelectedLocation(
        latitude: 12.9716,
        longitude: 77.5946,
        postalCode: '56003A',
      );
      expect(invalidPinAlpha.hasValidPostalCode, isFalse);
    });

    test('SelectedLocation handles missing fields gracefully', () {
      const minimalLoc = SelectedLocation(
        latitude: 12.9716,
        longitude: 77.5946,
      );

      expect(minimalLoc.street, isEmpty);
      expect(minimalLoc.area, isEmpty);
      expect(minimalLoc.city, isEmpty);
      expect(minimalLoc.postalCode, isEmpty);
      expect(minimalLoc.country, equals('India'));
      expect(minimalLoc.hasValidPostalCode, isFalse);
      expect(minimalLoc.isMapVerified, isTrue);
    });

    test('SelectedLocation copyWith preserves error message behavior', () {
      const loc = SelectedLocation(
        latitude: 12.0,
        longitude: 77.0,
        errorMessage: 'Network timeout during geocode',
      );

      expect(loc.errorMessage, isNotNull);

      final cleared = loc.copyWith(clearErrorMessage: true);
      expect(cleared.errorMessage, isNull);
    });
  });

  group('Phase 7: Location Failure Exception Types', () {
    test('LocationServiceDisabledFailure provides actionable message', () {
      const failure = LocationServiceDisabledFailure();
      expect(failure.code, equals('service_disabled'));
      expect(failure.message, contains('Location services are disabled'));
    });

    test('LocationPermissionDeniedFailure provides clear explanation', () {
      const failure = LocationPermissionDeniedFailure();
      expect(failure.code, equals('permission_denied'));
      expect(failure.message, contains('Location permission was denied'));
    });

    test('LocationPermissionDeniedForeverFailure points to App Settings', () {
      const failure = LocationPermissionDeniedForeverFailure();
      expect(failure.code, equals('permission_denied_forever'));
      expect(failure.message, contains('permanently denied'));
    });

    test('LocationTimeoutFailure provides retry guidance', () {
      const failure = LocationTimeoutFailure();
      expect(failure.code, equals('timeout'));
      expect(failure.message, contains('timed out'));
    });
  });

  group('Phase 19 & 23: Checkout Verified-Address Rules', () {
    test('Unverified address does not satisfy map verification rule', () {
      const legacyAddress = UserAddress(
        id: 'legacy-1',
        tag: 'Home',
        recipientName: 'Alice',
        phone: '9876543210',
        houseOrFlat: 'Old Flat',
        streetOrArea: 'Indiranagar',
        city: 'Bengaluru',
        pincode: '560038',
      );

      // Checkout canPlaceOrder condition requires:
      // selectedAddress.isMapVerified == true
      final canProceed = legacyAddress.isMapVerified;
      expect(canProceed, isFalse);
    });

    test(
      'Map-verified address satisfies checkout address verification rule',
      () {
        const verifiedAddress = UserAddress(
          id: 'verified-1',
          tag: 'Home',
          recipientName: 'Alice',
          phone: '9876543210',
          houseOrFlat: 'Flat 102',
          streetOrArea: 'Indiranagar',
          city: 'Bengaluru',
          pincode: '560038',
          latitude: 12.9785,
          longitude: 77.6408,
        );

        final canProceed = verifiedAddress.isMapVerified;
        expect(canProceed, isTrue);
      },
    );
  });
}
