import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/core/supabase/supabase_exception_mapper.dart';
import 'package:freshmarket/features/checkout/data/checkout_quote_model.dart';
import 'package:freshmarket/features/checkout/data/checkout_repository.dart';
import 'package:freshmarket/features/payment/data/payment_verification_model.dart';
import 'package:freshmarket/features/payment/data/razorpay_order_model.dart';
import 'package:freshmarket/shared/models/address.dart';
import 'package:freshmarket/shared/models/coupon.dart';
import 'package:freshmarket/shared/models/order.dart';
import 'package:freshmarket/shared/models/product_variant.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ProductVariant Pricing & Stock Semantics', () {
    test('Calculates discount percentage and hasDiscount correctly', () {
      const variantWithDiscount = ProductVariant(
        id: 'var-1',
        sku: 'CHK-CURRY-500',
        title: '500 g',
        weightInGrams: 500,
        price: 180.0,
        originalPrice: 200.0,
        stockQuantity: 15,
        isAvailable: true,
      );

      expect(variantWithDiscount.hasDiscount, isTrue);
      expect(variantWithDiscount.discountPercentage, equals(10));
      expect(variantWithDiscount.isOutOfStock, isFalse);
      expect(variantWithDiscount.stock, equals(15));
    });

    test(
      'Identifies out-of-stock when stockQuantity is zero or not available',
      () {
        const outOfStockVariant = ProductVariant(
          id: 'var-2',
          sku: 'MUT-CURRY-500',
          title: '500 g',
          weightInGrams: 500,
          price: 450.0,
          stockQuantity: 0,
          isAvailable: true,
        );

        expect(outOfStockVariant.isOutOfStock, isTrue);
        expect(outOfStockVariant.hasDiscount, isFalse);
        expect(outOfStockVariant.discountPercentage, equals(0));
      },
    );
  });

  group('OrderStatus Legacy & Canonical Lifecycle Mapping', () {
    test('Maps legacy database status values to Flutter OrderStatus', () {
      expect(
        OrderStatus.fromDbValue('pending'),
        equals(OrderStatus.orderPlaced),
      );
      expect(
        OrderStatus.fromDbValue('placed'),
        equals(OrderStatus.orderPlaced),
      );
      expect(
        OrderStatus.fromDbValue('processing'),
        equals(OrderStatus.preparing),
      );
      expect(
        OrderStatus.fromDbValue('preparing'),
        equals(OrderStatus.preparing),
      );
      expect(OrderStatus.fromDbValue('packed'), equals(OrderStatus.packed));
      expect(
        OrderStatus.fromDbValue('out_for_delivery'),
        equals(OrderStatus.outForDelivery),
      );
      expect(
        OrderStatus.fromDbValue('confirmed'),
        equals(OrderStatus.confirmed),
      );
      expect(
        OrderStatus.fromDbValue('delivered'),
        equals(OrderStatus.delivered),
      );
      expect(
        OrderStatus.fromDbValue('cancelled'),
        equals(OrderStatus.cancelled),
      );
      expect(
        OrderStatus.fromDbValue('unknown_status'),
        equals(OrderStatus.orderPlaced),
      );
    });
  });

  group('UserAddress Formatting and Serialization', () {
    test('Formats full address correctly with landmark', () {
      const address = UserAddress(
        id: 'addr-1',
        tag: 'Home',
        recipientName: 'Aarav Patel',
        phone: '9876543210',
        houseOrFlat: 'Flat 402, Green Meadows',
        streetOrArea: '14th Cross, HSR Layout',
        city: 'Bengaluru',
        pincode: '560102',
        landmark: 'Near BDA Complex',
      );

      expect(
        address.formattedAddress,
        equals(
          'Flat 402, Green Meadows, 14th Cross, HSR Layout, Near BDA Complex, Bengaluru, Karnataka - 560102',
        ),
      );
    });

    test('toInsertJson includes all required database columns', () {
      const address = UserAddress(
        id: 'addr-2',
        tag: 'Work',
        recipientName: 'Aarav Patel',
        phone: '9876543210',
        houseOrFlat: 'Tech Park, Tower B',
        streetOrArea: 'Outer Ring Road',
        city: 'Bengaluru',
        pincode: '560103',
        isDefault: true,
      );

      final json = address.toInsertJson('user-uuid-123');
      expect(json['user_id'], equals('user-uuid-123'));
      expect(json['label'], equals('Work'));
      expect(json['is_default'], isTrue);
      expect(json['address_line1'], equals('Tech Park, Tower B'));
    });
  });

  group('Coupon Preview Discount Calculations', () {
    final now = DateTime.now();
    final validCoupon = Coupon(
      id: 'cpn-1',
      code: 'SAVE20',
      description: '20% off up to ₹100',
      discountType: 'percentage',
      discountValue: 20.0,
      minOrderAmount: 300.0,
      maxDiscountAmount: 100.0,
      startsAt: now.subtract(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 7)),
      isActive: true,
    );

    test('Applies percentage discount with max cap', () {
      // Subtotal 600 -> 20% is 120 -> capped at 100
      final discount = validCoupon.calculateDiscountPreview(600.0);
      expect(discount, equals(100.0));
    });

    test('Returns 0 if order does not meet minimum amount', () {
      final discount = validCoupon.calculateDiscountPreview(250.0);
      expect(discount, equals(0.0));
    });

    test('Applies flat discount accurately', () {
      final flatCoupon = Coupon(
        id: 'cpn-2',
        code: 'FLAT50',
        description: 'Flat ₹50 off',
        discountType: 'flat',
        discountValue: 50.0,
        minOrderAmount: 200.0,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 7)),
        isActive: true,
      );

      final discount = flatCoupon.calculateDiscountPreview(300.0);
      expect(discount, equals(50.0));
    });
  });

  group('SupabaseExceptionMapper Security & User-Friendly Messages', () {
    test('Sanitizes database duplicate key error without leaking SQL', () {
      const pgError = PostgrestException(
        message: 'duplicate key value violates unique constraint "idx_addresses_user_default"',
        code: '23505',
      );
      final mapped = SupabaseExceptionMapper.map(pgError);
      expect(mapped.message, contains('already exists'));
      expect(mapped.message.contains('idx_addresses'), isFalse);
    });

    test('Sanitizes RLS permission denied error', () {
      const pgError = PostgrestException(
        message:
            'new row violates row-level security policy for table "orders"',
        code: '42501',
      );
      final mapped = SupabaseExceptionMapper.map(pgError);
      expect(mapped.message, contains('permission'));
      expect(mapped.message.contains('row-level security'), isFalse);
    });

    test('Sanitizes auth invalid credentials', () {
      const authError = AuthException('Invalid login credentials');
      final mapped = SupabaseExceptionMapper.map(authError);
      expect(mapped.message, contains('Invalid email address or password'));
    });
  });

  group('Session 4 — Idempotency & Checkout Quote Model', () {
    test('generateUuidV4 generates valid RFC 4122 Version 4 UUIDs', () {
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );

      for (int i = 0; i < 50; i++) {
        final id = generateUuidV4();
        expect(id.length, equals(36));
        expect(
          uuidRegex.hasMatch(id),
          isTrue,
          reason: 'UUID $id should match RFC 4122 v4 specification',
        );
      }
    });

    test(
      'CheckoutQuote correctly parses server-authoritative JSON response',
      () {
        final json = {
          'cart_id': 'cart-uuid-001',
          'items': [
            {
              'variant_id': 'var-1',
              'product_name': 'Chicken Breast Fillet',
              'variant_title': '500 g',
              'unit_price': 180.0,
              'quantity': 2,
              'total_price': 360.0,
              'stock_available': 10,
            },
          ],
          'subtotal': 360.0,
          'item_discount': 20.0,
          'coupon_discount': 50.0,
          'delivery_fee': 40.0,
          'platform_fee': 5.0,
          'tax_amount': 0.0,
          'wallet_balance': 0.0,
          'grand_total': 335.0,
          'cod_payable': 335.0,
          'stock_valid': true,
          'serviceable': true,
        };

        final quote = CheckoutQuote.fromJson(json);

        expect(quote.cartId, equals('cart-uuid-001'));
        expect(quote.items.length, equals(1));
        expect(quote.items.first.productName, equals('Chicken Breast Fillet'));
        expect(quote.subtotal, equals(360.0));
        expect(quote.itemDiscount, equals(20.0));
        expect(quote.couponDiscount, equals(50.0));
        expect(quote.deliveryFee, equals(40.0));
        expect(quote.platformFee, equals(5.0));
        expect(quote.grandTotal, equals(335.0));
        expect(quote.codPayableTotal, equals(335.0));
        expect(quote.stockValid, isTrue);
        expect(quote.serviceable, isTrue);
      },
    );

    test('CustomerOrder parses payment status and cancellation fields', () {
      final orderJson = {
        'id': 'ord-12345',
        'order_number': 'FM-20261007-001',
        'subtotal': 450.0,
        'discount': 50.0,
        'delivery_fee': 0.0,
        'total': 400.0,
        'status': 'placed',
        'payment_method': 'cod',
        'created_at': '2026-10-07T03:00:00Z',
        'cancellation_reason': 'Need to change delivery address',
        'cancelled_at': '2026-10-07T03:30:00Z',
        'payments': [
          {
            'id': 'pay-001',
            'status': 'pending',
            'method': 'cod',
            'amount': 400.0,
          },
        ],
        'delivery_address_snapshot': {
          'address_line1': 'Flat 101, Palm Grove',
          'city': 'Bengaluru',
          'pincode': '560102',
        },
        'delivery_slot_snapshot': {'name': 'Morning (7 AM - 9 AM)'},
      };

      final order = CustomerOrder.fromJson(orderJson);

      expect(order.id, equals('ord-12345'));
      expect(order.orderNumber, equals('FM-20261007-001'));
      expect(order.totalAmount, equals(400.0));
      expect(order.status, equals(OrderStatus.orderPlaced));
      expect(order.paymentStatus, equals('PENDING'));
      expect(order.paymentMethod, equals('COD'));
      expect(
        order.cancellationReason,
        equals('Need to change delivery address'),
      );
      expect(order.cancelledAt, isNotNull);
      expect(order.deliveryAddress, contains('Palm Grove'));
      expect(order.deliverySlot, equals('Morning (7 AM - 9 AM)'));
    });

    test(
      'CustomerOrder parses payment_pending status and razorpay payment method',
      () {
        final orderJson = {
          'id': 'ord-rzp-001',
          'order_number': 'FM-20261007-RZP',
          'subtotal': 500.0,
          'discount': 0.0,
          'delivery_fee': 40.0,
          'total': 540.0,
          'status': 'payment_pending',
          'payment_method': 'razorpay',
          'created_at': '2026-10-07T03:00:00Z',
          'payments': [
            {
              'id': 'pay-rzp-001',
              'status': 'pending',
              'method': 'razorpay',
              'amount': 540.0,
              'gateway_order_id': 'order_QweRty12345678',
            },
          ],
        };

        final order = CustomerOrder.fromJson(orderJson);

        expect(order.status, equals(OrderStatus.paymentPending));
        expect(order.status.displayLabel, equals('Awaiting Payment'));
        expect(order.paymentMethod, equals('RAZORPAY'));
        expect(order.isPaymentPending, isTrue);
        expect(order.canCancelPayment, isTrue);
      },
    );
  });

  group('Session 5A Razorpay Models & Checkout Options', () {
    test('RazorpayOrderModel parses server response correctly', () {
      final json = {
        'success': true,
        'internal_order_id': '00000000-0000-0000-0000-000000000001',
        'internal_order_number': 'FM-20261007-001',
        'payment_id': '00000000-0000-0000-0000-000000000002',
        'razorpay_order_id': 'order_Test1234567890',
        'razorpay_key_id': 'rzp_test_FreshMarketKey',
        'amount_paise': 54000,
        'currency': 'INR',
        'prefill': {
          'name': 'Test Customer',
          'email': 'customer@freshmarket.local',
          'contact': '9876543210',
        },
        'payment_attempt_no': 1,
        'expires_at': '2026-10-07T03:15:00Z',
      };

      final model = RazorpayOrderModel.fromJson(json);

      expect(
        model.internalOrderId,
        equals('00000000-0000-0000-0000-000000000001'),
      );
      expect(model.razorpayOrderId, equals('order_Test1234567890'));
      expect(model.razorpayKeyId, equals('rzp_test_FreshMarketKey'));
      expect(model.amountPaise, equals(54000));
      expect(model.amountRupees, equals(540.0));
      expect(model.currency, equals('INR'));
      expect(model.prefillName, equals('Test Customer'));

      final options = model.toCheckoutOptions(appName: 'FreshMarket Test');
      expect(options['key'], equals('rzp_test_FreshMarketKey'));
      expect(options['amount'], equals(54000));
      expect(options['order_id'], equals('order_Test1234567890'));
      expect(options['currency'], equals('INR'));
      expect(options.containsKey('secret'), isFalse);
      expect(options.containsKey('key_secret'), isFalse);
      expect((options['prefill'] as Map)['contact'], equals('9876543210'));
    });

    test('PaymentVerificationResult handles captured and confirmed flow', () {
      final json = {
        'success': true,
        'verified': true,
        'captured': true,
        'status': 'confirmed',
        'payment_status': 'completed',
        'internal_order_id': 'ord-123',
        'order_number': 'FM-20261007-999',
        'message': 'Payment confirmed successfully',
      };

      final result = PaymentVerificationResult.fromJson(json);

      expect(result.success, isTrue);
      expect(result.verified, isTrue);
      expect(result.captured, isTrue);
      expect(result.isOrderConfirmed, isTrue);
      expect(result.orderNumber, equals('FM-20261007-999'));
    });

    test(
      'PaymentVerificationResult identifies uncaptured/unconfirmed status',
      () {
        final json = {
          'success': false,
          'verified': false,
          'captured': false,
          'status': 'payment_pending',
          'payment_status': 'failed',
          'internal_order_id': 'ord-123',
          'order_number': 'FM-20261007-999',
          'error_code': 'SIGNATURE_INVALID',
          'message': 'Signature verification failed',
        };

        final result = PaymentVerificationResult.fromJson(json);

        expect(result.success, isFalse);
        expect(result.isOrderConfirmed, isFalse);
        expect(result.errorCode, equals('SIGNATURE_INVALID'));
        expect(result.message, equals('Signature verification failed'));
      },
    );
  });
}
