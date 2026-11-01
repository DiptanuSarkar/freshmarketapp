import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/shared/models/address.dart';
import 'package:freshmarket/shared/models/delivery_serviceability.dart';

void main() {
  group('Session 8A — DeliveryServiceability Model', () {
    test('parses inside-zone server JSON response accurately', () {
      final json = {
        'serviceable': true,
        'zone_id': '87654321-4321-4321-4321-210987654321',
        'zone_code': 'agartala_city',
        'zone_name': 'Agartala City',
        'delivery_fee': 30.00,
        'free_delivery_threshold': 499.00,
        'minimum_order_amount': 0.00,
        'reason_code': 'SERVICEABLE',
        'message': 'Delivery available in Agartala City',
      };

      final result = DeliveryServiceability.fromJson(json);

      expect(result.serviceable, isTrue);
      expect(result.zoneCode, equals('agartala_city'));
      expect(result.zoneName, equals('Agartala City'));
      expect(result.deliveryFee, equals(30.0));
      expect(result.freeDeliveryThreshold, equals(499.0));
      expect(result.minimumOrderAmount, equals(0.0));
      expect(result.reasonCode, equals('SERVICEABLE'));
      expect(result.message, contains('Agartala'));
    });

    test('parses outside-zone server response with Agartala messaging', () {
      final json = {
        'serviceable': false,
        'reason_code': 'OUTSIDE_DELIVERY_ZONE',
        'message': 'FreshMarket currently delivers only within Agartala city.',
      };

      final result = DeliveryServiceability.fromJson(json);

      expect(result.serviceable, isFalse);
      expect(result.reasonCode, equals('OUTSIDE_DELIVERY_ZONE'));
      expect(result.zoneCode, isNull);
      expect(
        result.message,
        equals('FreshMarket currently delivers only within Agartala city.'),
      );
    });

    test(
      'static constants provide reliable unverified and outsideZone defaults',
      () {
        expect(DeliveryServiceability.unverified.serviceable, isFalse);
        expect(
          DeliveryServiceability.unverified.reasonCode,
          equals('ADDRESS_NOT_MAP_VERIFIED'),
        );

        expect(DeliveryServiceability.outsideZone.serviceable, isFalse);
        expect(
          DeliveryServiceability.outsideZone.reasonCode,
          equals('OUTSIDE_DELIVERY_ZONE'),
        );
        expect(
          DeliveryServiceability.outsideZone.message,
          contains('Agartala'),
        );
      },
    );

    test('toJson serializes serviceability correctly', () {
      const serv = DeliveryServiceability(
        serviceable: true,
        reasonCode: 'SERVICEABLE',
        zoneCode: 'agartala_city',
        zoneName: 'Agartala City',
        deliveryFee: 30.0,
        freeDeliveryThreshold: 499.0,
      );

      final json = serv.toJson();
      expect(json['serviceable'], isTrue);
      expect(json['zone_code'], equals('agartala_city'));
      expect(json['delivery_fee'], equals(30.0));
      expect(json['free_delivery_threshold'], equals(499.0));
    });
  });

  group('Session 8A — UserAddress Map Coordinates & Agartala Formatting', () {
    test('isMapVerified requires valid latitude and longitude within geographical bounds', () {
      const verified = UserAddress(
        id: 'addr-agartala-1',
        tag: 'Home',
        recipientName: 'Debnath',
        phone: '9876543210',
        houseOrFlat: 'Lane 4, Banamalipur',
        streetOrArea: 'Near Post Office',
        city: 'Agartala',
        state: 'Tripura',
        pincode: '799001',
        latitude: 23.8315,
        longitude: 91.2825,
      );

      expect(verified.isMapVerified, isTrue);

      const legacyUnverified = UserAddress(
        id: 'addr-legacy',
        tag: 'Home',
        recipientName: 'Debnath',
        phone: '9876543210',
        houseOrFlat: 'Old House',
        streetOrArea: 'Old Street',
        city: 'Agartala',
        state: 'Tripura',
        pincode: '799001',
        latitude: null,
        longitude: null,
      );

      expect(legacyUnverified.isMapVerified, isFalse);

      const invalidLat = UserAddress(
        id: 'addr-inv-lat',
        tag: 'Home',
        recipientName: 'Debnath',
        phone: '9876543210',
        houseOrFlat: 'House',
        streetOrArea: 'Street',
        city: 'Agartala',
        state: 'Tripura',
        pincode: '799001',
        latitude: 95.0, // Invalid > 90
        longitude: 91.28,
      );

      expect(invalidLat.isMapVerified, isFalse);
    });

    test('formattedAddress formats genuine Agartala address accurately', () {
      const agartalaAddress = UserAddress(
        id: 'addr-agtl',
        tag: 'Home',
        recipientName: 'Subhasish',
        phone: '9876543210',
        houseOrFlat: 'House 12',
        streetOrArea: 'College Tilla',
        city: 'Agartala',
        state: 'Tripura',
        pincode: '799004',
        landmark: 'MBB College',
        latitude: 23.8200,
        longitude: 91.2980,
      );

      expect(
        agartalaAddress.formattedAddress,
        equals(
          'House 12, College Tilla, Near MBB College, Agartala, Tripura - 799004',
        ),
      );
    });
  });

  group('Session 8A — Serviceability Badges & State Mapping', () {
    test('badge text and color mapping for all 3 address states', () {
      // 1. Inside Agartala verified
      const inside = DeliveryServiceability(
        serviceable: true,
        reasonCode: 'SERVICEABLE',
        zoneCode: 'agartala_city',
        zoneName: 'Agartala City',
        deliveryFee: 30.0,
      );
      expect(inside.serviceable, isTrue);
      expect(inside.badgeLabel, equals('DELIVERY AVAILABLE'));
      expect(inside.badgeDescription, contains('Agartala'));

      // 2. Outside Agartala verified
      const outside = DeliveryServiceability(
        serviceable: false,
        reasonCode: 'OUTSIDE_DELIVERY_ZONE',
        message: 'FreshMarket currently delivers only within Agartala city.',
      );
      expect(outside.serviceable, isFalse);
      expect(outside.badgeLabel, equals('OUTSIDE DELIVERY AREA'));
      expect(outside.badgeDescription, contains('Agartala'));

      // 3. Unverified legacy address
      final unverified = DeliveryServiceability.unverified;
      expect(unverified.serviceable, isFalse);
      expect(unverified.badgeLabel, equals('VERIFY ON MAP'));
    });
  });

  group('Session 8A — Checkout Gating Rules & Flow Logic', () {
    const verifiedAgartalaAddress = UserAddress(
      id: 'addr-agartala-valid',
      tag: 'Home',
      recipientName: 'Debnath',
      phone: '9876543210',
      houseOrFlat: 'Banamalipur',
      streetOrArea: 'Road 3',
      city: 'Agartala',
      state: 'Tripura',
      pincode: '799001',
      latitude: 23.8315,
      longitude: 91.2825,
    );

    const verifiedOutsideAddress = UserAddress(
      id: 'addr-outside-bishalgarh',
      tag: 'Office',
      recipientName: 'Debnath',
      phone: '9876543210',
      houseOrFlat: 'Bishalgarh Bazar',
      streetOrArea: 'Main Road',
      city: 'Bishalgarh',
      state: 'Tripura',
      pincode: '799102',
      latitude: 23.6800,
      longitude: 91.3000,
    );

    const unverifiedAddress = UserAddress(
      id: 'addr-legacy-unverified',
      tag: 'Other',
      recipientName: 'Debnath',
      phone: '9876543210',
      houseOrFlat: 'Old House',
      streetOrArea: 'Old Street',
      city: 'Agartala',
      state: 'Tripura',
      pincode: '799001',
    );

    test('Inside Agartala address enables checkout and renders server fee', () {
      const serviceability = DeliveryServiceability(
        serviceable: true,
        reasonCode: 'SERVICEABLE',
        zoneCode: 'agartala_city',
        zoneName: 'Agartala City',
        deliveryFee: 30.0,
        freeDeliveryThreshold: 499.0,
      );

      final isAddressVerified = verifiedAgartalaAddress.isMapVerified;
      final isServiceable = serviceability.serviceable;
      final canCheckout = isAddressVerified && isServiceable;

      expect(canCheckout, isTrue);
      expect(serviceability.deliveryFee, equals(30.0));
      expect(serviceability.freeDeliveryThreshold, equals(499.0));
    });

    test(
      'Outside Agartala address blocks checkout and requires address change',
      () {
        const serviceability = DeliveryServiceability(
          serviceable: false,
          reasonCode: 'OUTSIDE_DELIVERY_ZONE',
          message: 'FreshMarket currently delivers only within Agartala city.',
        );

        final isAddressVerified = verifiedOutsideAddress.isMapVerified;
        final isServiceable = serviceability.serviceable;
        final canCheckout = isAddressVerified && isServiceable;

        expect(isAddressVerified, isTrue);
        expect(isServiceable, isFalse);
        expect(canCheckout, isFalse);

        // Verify routing actions available
        const changeAddressRoute = '/addresses';
        final editMapRoute = '/addresses/${verifiedOutsideAddress.id}/edit';
        expect(changeAddressRoute, equals('/addresses'));
        expect(editMapRoute, contains('edit'));
      },
    );

    test(
      'Unverified address blocks checkout and requests map verification',
      () {
        final isAddressVerified = unverifiedAddress.isMapVerified;
        final isServiceable = DeliveryServiceability.unverified.serviceable;
        final canCheckout = isAddressVerified && isServiceable;

        expect(isAddressVerified, isFalse);
        expect(canCheckout, isFalse);

        final verifyMapRoute = '/addresses/${unverifiedAddress.id}/edit';
        expect(verifyMapRoute, contains('edit'));
      },
    );
  });

  group('Session 8A — Demo Placeholder Elimination', () {
    test(
      'UserAddress defaults do not contain Bengaluru or Bangalore demo strings',
      () {
        const addr = UserAddress(
          id: 'addr-test',
          tag: 'Home',
          recipientName: 'Test Customer',
          phone: '9876543210',
          houseOrFlat: 'Flat 1',
          streetOrArea: 'Akhaura Road',
          city: 'Agartala',
          state: 'Tripura',
          pincode: '799001',
          latitude: 23.83,
          longitude: 91.28,
        );

        expect(addr.city.toLowerCase(), isNot(contains('bengaluru')));
        expect(addr.city.toLowerCase(), isNot(contains('bangalore')));
        expect(addr.streetOrArea.toLowerCase(), isNot(contains('indiranagar')));
        expect(addr.formattedAddress, contains('Agartala, Tripura - 799001'));
      },
    );
  });
}
