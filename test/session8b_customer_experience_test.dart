import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/features/orders/data/orders_repository.dart';
import 'package:freshmarket/shared/models/app_support_config.dart';
import 'package:freshmarket/shared/models/product_rating_summary.dart';
import 'package:freshmarket/shared/models/product_review.dart';

void main() {
  group('Session 8B: Support Configuration & WhatsApp Click-to-Chat', () {
    test('Parses AppSupportConfig from remote app_settings JSON', () {
      final json = {
        'whatsapp_number': '+91 8787630683',
        'support_phone': '+91-381-2300000',
        'support_email': 'care@freshmarket.in',
        'business_hours': '6:00 AM - 10:00 PM IST (Daily)',
        'help_desk_title': 'FreshMarket Butchery Care',
      };

      final config = AppSupportConfig.fromJson(json);
      expect(config.whatsappNumber, equals('+91 8787630683'));
      expect(config.supportPhone, equals('+91-381-2300000'));
      expect(config.supportEmail, equals('care@freshmarket.in'));
      expect(config.businessHours, equals('6:00 AM - 10:00 PM IST (Daily)'));
      expect(config.helpDeskTitle, equals('FreshMarket Butchery Care'));
    });

    test('Formats WhatsApp Click-to-Chat URL with clean digits and encoded message', () {
      const config = AppSupportConfig(
        whatsappNumber: '+91 (878) 763-0683',
        supportPhone: '1800-FRESH',
        supportEmail: 'support@freshmarket.in',
        businessHours: '8:00 AM - 9:00 PM',
        helpDeskTitle: 'FreshMarket Support',
      );

      final uri = config.buildWhatsAppUri(
        'Hello FreshMarket Support, I need help with order FM-12345.',
      );

      expect(uri.scheme, equals('https'));
      expect(uri.host, equals('wa.me'));
      expect(uri.path, equals('/918787630683'));
      expect(
        uri.queryParameters['text'],
        equals('Hello FreshMarket Support, I need help with order FM-12345.'),
      );
    });

    test('Generates safe WhatsApp order inquiry text without leaking tokens or DB IDs', () {
      final config = AppSupportConfig.defaults;
      final uri = config.buildWhatsAppUri(
        'Hello FreshMarket Support, I need help with order FM-8899.',
      );

      expect(uri.toString(), contains('FM-8899'));
      expect(uri.toString(), isNot(contains('token')));
      expect(uri.toString(), isNot(contains('auth')));
    });

    test(
      'Provides valid tel: and mailto: URIs for fallback support channels',
      () {
        final config = AppSupportConfig.defaults;

        final telUri = config.phoneUri;
        expect(telUri.scheme, equals('tel'));
        expect(telUri.path, contains('8787630683'));

        final mailUri = config.emailUri;
        expect(mailUri.scheme, equals('mailto'));
        expect(mailUri.path, equals('care@freshmarket.in'));
      },
    );
  });

  group('Session 8B: Verified-Purchase Reviews & Rating Summary Models', () {
    test('Parses ProductRatingSummary from authoritative RPC response', () {
      final json = {
        'average_rating': 4.67,
        'review_count': 15,
        'breakdown': {'1': 0, '2': 1, '3': 1, '4': 3, '5': 10},
      };

      final summary = ProductRatingSummary.fromJson(json);
      expect(summary.averageRating, equals(4.67));
      expect(summary.reviewCount, equals(15));
      expect(summary.breakdown[5], equals(10));
      expect(summary.breakdown[4], equals(3));
      expect(summary.breakdown[1], equals(0));
      expect(summary.starPercentage(5), closeTo(0.666, 0.01));
    });

    test('Handles empty/zero ProductRatingSummary gracefully', () {
      final summary = ProductRatingSummary.empty;
      expect(summary.averageRating, equals(0.0));
      expect(summary.reviewCount, equals(0));
      expect(summary.starPercentage(5), equals(0.0));
    });

    test('Parses ProductReview with title and verified purchase flag', () {
      final json = {
        'id': 'rev-001',
        'product_id': 'prod-001',
        'user_id': 'usr-001',
        'rating': 5,
        'title': 'Exceptional Freshness',
        'review_text':
            'Delivered ice-cold in Agartala within slot. Very tender.',
        'is_verified_purchase': true,
        'created_at': '2026-11-02T10:00:00.000Z',
      };

      final review = ProductReview.fromJson(json);
      expect(review.id, equals('rev-001'));
      expect(review.rating, equals(5));
      expect(review.title, equals('Exceptional Freshness'));
      expect(review.reviewText, contains('ice-cold'));
      expect(review.isVerifiedPurchase, isTrue);
    });

    test('ProductReview copyWith updates fields correctly', () {
      final review = ProductReview(
        id: 'rev-002',
        productId: 'prod-002',
        userId: 'usr-002',
        rating: 4,
        title: 'Good Quality',
        reviewText: 'Nice cut.',
        isVerifiedPurchase: true,
        createdAt: DateTime.now(),
      );

      final updated = review.copyWith(rating: 5, title: 'Updated Title');
      expect(updated.rating, equals(5));
      expect(updated.title, equals('Updated Title'));
      expect(updated.isVerifiedPurchase, isTrue);
      expect(updated.id, equals(review.id));
    });
  });

  group('Session 8B: Repeat Order Flow & Inventory Validation', () {
    test('RepeatOrderResult correctly tracks added and unavailable items', () {
      const result = RepeatOrderResult(
        addedCount: 2,
        unavailableCount: 1,
        unavailableItems: ['Fresh Mutton Curry Cut (Out of stock)'],
      );

      expect(result.hasItemsAdded, isTrue);
      expect(result.hasUnavailable, isTrue);
      expect(result.summaryMessage, contains('Added 2 item(s)'));
      expect(
        result.summaryMessage,
        contains('Unavailable: Fresh Mutton Curry Cut (Out of stock)'),
      );
    });

    test('RepeatOrderResult communicates 100% available order', () {
      const result = RepeatOrderResult(
        addedCount: 3,
        unavailableCount: 0,
        unavailableItems: [],
      );
      expect(result.hasItemsAdded, isTrue);
      expect(result.hasUnavailable, isFalse);
      expect(result.summaryMessage, equals('Added 3 item(s) to your cart.'));
    });

    test(
      'RepeatOrderResult communicates complete catalog deprecation/exhaustion',
      () {
        const result = RepeatOrderResult(
          addedCount: 0,
          unavailableCount: 1,
          unavailableItems: ['Seasonal Mango Pickle (Discontinued)'],
        );
        expect(result.hasItemsAdded, isFalse);
        expect(result.hasUnavailable, isTrue);
        expect(
          result.summaryMessage,
          contains('None of the items from this order are currently available'),
        );
      },
    );
  });
}
