import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/features/checkout/data/checkout_quote_model.dart';
import 'package:freshmarket/features/payment/data/razorpay_order_model.dart';
import 'package:freshmarket/shared/models/order.dart';

void main() {
  group('Session 5B - CheckoutQuoteModel Wallet & Mixed Extensions', () {
    test('parses wallet-only quote correctly', () {
      final json = {
        'items': [],
        'subtotal': 450.0,
        'item_discount': 0.0,
        'coupon_discount': 0.0,
        'delivery_fee': 0.0,
        'grand_total': 450.0,
        'wallet_balance': 1000.0,
        'wallet_available': 1000.0,
        'wallet_amount_applied': 450.0,
        'gateway_payable': 0.0,
        'is_wallet_only': true,
        'stock_valid': true,
      };

      final quote = CheckoutQuote.fromJson(json);

      expect(quote.grandTotal, 450.0);
      expect(quote.walletBalance, 1000.0);
      expect(quote.walletAvailable, 1000.0);
      expect(quote.walletAmountApplied, 450.0);
      expect(quote.gatewayPayable, 0.0);
      expect(quote.isWalletOnly, true);
    });

    test('parses mixed payment quote correctly', () {
      final json = {
        'items': [],
        'subtotal': 800.0,
        'item_discount': 50.0,
        'coupon_discount': 50.0,
        'delivery_fee': 40.0,
        'grand_total': 740.0,
        'wallet_balance': 300.0,
        'wallet_available': 300.0,
        'wallet_amount_applied': 300.0,
        'gateway_payable': 440.0,
        'is_wallet_only': false,
        'stock_valid': true,
      };

      final quote = CheckoutQuote.fromJson(json);

      expect(quote.grandTotal, 740.0);
      expect(quote.walletBalance, 300.0);
      expect(quote.walletAmountApplied, 300.0);
      expect(quote.gatewayPayable, 440.0);
      expect(quote.isWalletOnly, false);
    });

    test('handles fallback when wallet fields omitted', () {
      final json = {
        'items': [],
        'subtotal': 500.0,
        'item_discount': 0.0,
        'coupon_discount': 0.0,
        'delivery_fee': 0.0,
        'grand_total': 500.0,
        'stock_valid': true,
      };

      final quote = CheckoutQuote.fromJson(json);

      expect(quote.walletBalance, 0.0);
      expect(quote.walletAmountApplied, 0.0);
      expect(quote.gatewayPayable, 500.0);
      expect(quote.isWalletOnly, false);
    });
  });

  group('Session 5B - CustomerOrder Wallet & Refund Model', () {
    test('parses wallet order with refund status from relation', () {
      final json = {
        'id': 'c8a2efc4-0000-4000-8000-000000000001',
        'order_number': 'FM-20261010-0001',
        'subtotal': 600.0,
        'discount': 0.0,
        'delivery_fee': 0.0,
        'grand_total': 600.0,
        'status': 'cancelled',
        'payment_method': 'wallet',
        'wallet_amount_used': 600.0,
        'gateway_amount': 0.0,
        'cancellation_reason': 'Customer requested cancellation',
        'created_at': '2026-10-10T08:00:00Z',
        'refunds': [
          {
            'id': 'ref-1',
            'status': 'completed',
            'amount': 600.0,
          }
        ],
      };

      final order = CustomerOrder.fromJson(json);

      expect(order.id, 'c8a2efc4-0000-4000-8000-000000000001');
      expect(order.orderNumber, 'FM-20261010-0001');
      expect(order.paymentMethod, 'WALLET');
      expect(order.walletAmountUsed, 600.0);
      expect(order.gatewayAmount, 0.0);
      expect(order.refundStatus, 'completed');
      expect(order.status, OrderStatus.cancelled);
    });

    test('parses mixed order with pending refund', () {
      final json = {
        'id': 'c8a2efc4-0000-4000-8000-000000000002',
        'order_number': 'FM-20261010-0002',
        'subtotal': 1200.0,
        'discount': 100.0,
        'delivery_fee': 0.0,
        'grand_total': 1100.0,
        'status': 'cancelled',
        'payment_method': 'mixed',
        'wallet_amount_used': 400.0,
        'gateway_amount': 700.0,
        'created_at': '2026-10-10T08:30:00Z',
        'refund_status': 'processing',
      };

      final order = CustomerOrder.fromJson(json);

      expect(order.paymentMethod, 'MIXED');
      expect(order.walletAmountUsed, 400.0);
      expect(order.gatewayAmount, 700.0);
      expect(order.refundStatus, 'processing');
    });
  });

  group('Session 5B - RazorpayOrderModel Mixed Extensions', () {
    test('parses mixed Razorpay order response correctly', () {
      final json = {
        'razorpay_order_id': 'order_QzMixed12345678',
        'key_id': 'rzp_test_12345',
        'amount': 50000,
        'currency': 'INR',
        'internal_order_id': 'ord-mixed-uuid-1',
        'internal_order_number': 'FM-20261010-0003',
        'payment_id': 'pay-mixed-uuid-1',
        'payment_method': 'mixed',
        'wallet_amount': 250.0,
        'gateway_amount': 500.0,
        'is_wallet_only': false,
      };

      final model = RazorpayOrderModel.fromJson(json);

      expect(model.razorpayOrderId, 'order_QzMixed12345678');
      expect(model.amountPaise, 50000);
      expect(model.paymentMethod, 'mixed');
      expect(model.walletAmount, 250.0);
      expect(model.gatewayAmount, 500.0);
      expect(model.isWalletOnly, false);
      expect(model.amountRupees, 500.0);
    });

    test('parses wallet-only order response correctly', () {
      final json = {
        'razorpay_order_id': 'wallet_internal_only',
        'key_id': 'none',
        'amount': 0,
        'currency': 'INR',
        'internal_order_id': 'ord-wallet-uuid-2',
        'internal_order_number': 'FM-20261010-0004',
        'payment_id': 'pay-wallet-uuid-2',
        'payment_method': 'wallet',
        'wallet_amount': 350.0,
        'gateway_amount': 0.0,
        'is_wallet_only': true,
      };

      final model = RazorpayOrderModel.fromJson(json);

      expect(model.paymentMethod, 'wallet');
      expect(model.walletAmount, 350.0);
      expect(model.gatewayAmount, 0.0);
      expect(model.isWalletOnly, true);
    });
  });
}
