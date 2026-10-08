import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../shared/models/order.dart';
import '../../orders/data/orders_repository.dart';
import 'checkout_quote_model.dart';

class CheckoutException implements Exception {
  const CheckoutException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}

String generateUuidV4() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40; // RFC 4122 Version 4
  values[8] = (values[8] & 0x3f) | 0x80; // Variant 10
  final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

abstract interface class ICheckoutRepository {
  Future<CheckoutQuote> getCheckoutQuote({
    String? addressId,
    String? deliverySlotId,
    String? couponCode,
  });

  Future<CustomerOrder> createCodOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  });

  Future<void> cancelOrder({required String orderId, String? reason});
}

class SupabaseCheckoutRepository implements ICheckoutRepository {
  SupabaseCheckoutRepository({
    required SupabaseClient supabaseClient,
    required this.ordersRepository,
  }) : _supabase = supabaseClient;

  final SupabaseClient _supabase;
  final IOrdersRepository ordersRepository;

  @override
  Future<CheckoutQuote> getCheckoutQuote({
    String? addressId,
    String? deliverySlotId,
    String? couponCode,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'checkout-quote',
        body: {
          'address_id': ?addressId,
          'delivery_slot_id': ?deliverySlotId,
          if (couponCode != null && couponCode.isNotEmpty)
            'coupon_code': couponCode,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['success'] == false) {
          throw CheckoutException(
            code: data['error_code'] as String? ?? 'CHECKOUT_FAILED',
            message: data['message'] as String? ?? 'Unable to compute quote',
          );
        }
        return CheckoutQuote.fromJson(data);
      }

      throw const CheckoutException(
        code: 'CHECKOUT_FAILED',
        message: 'Invalid response from checkout quote service.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        throw CheckoutException(
          code: details['error_code'] as String? ?? 'CHECKOUT_FAILED',
          message: details['message'] as String? ?? e.toString(),
        );
      }
      throw CheckoutException(
        code: 'CHECKOUT_FAILED',
        message: details?.toString() ?? e.toString(),
      );
    } catch (e) {
      if (e is CheckoutException) rethrow;
      throw const CheckoutException(
        code: 'NETWORK_ERROR',
        message:
            'Could not connect to checkout service. Please check your network.',
      );
    }
  }

  @override
  Future<CustomerOrder> createCodOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-cod-order',
        body: {
          'checkout_request_id': checkoutRequestId,
          'address_id': addressId,
          'delivery_slot_id': deliverySlotId,
          if (couponCode != null && couponCode.isNotEmpty)
            'coupon_code': couponCode,
          if (customerNotes != null && customerNotes.isNotEmpty)
            'customer_notes': customerNotes,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['success'] == false) {
          throw CheckoutException(
            code: data['error_code'] as String? ?? 'CHECKOUT_FAILED',
            message: data['message'] as String? ?? 'Failed to place order.',
          );
        }

        final orderId = data['id'] as String?;
        if (orderId != null) {
          // Fetch full relational order details from orders repository
          final fullOrder = await ordersRepository.getOrderById(orderId);
          if (fullOrder != null) {
            return fullOrder;
          }
        }
        return CustomerOrder.fromJson(data);
      }

      throw const CheckoutException(
        code: 'CHECKOUT_FAILED',
        message: 'Invalid response from order creation service.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        throw CheckoutException(
          code: details['error_code'] as String? ?? 'CHECKOUT_FAILED',
          message: details['message'] as String? ?? e.toString(),
        );
      }
      throw CheckoutException(
        code: 'CHECKOUT_FAILED',
        message: details?.toString() ?? e.toString(),
      );
    } catch (e) {
      if (e is CheckoutException) rethrow;
      throw const CheckoutException(
        code: 'NETWORK_ERROR',
        message:
            'Order submission failed. Please check your connection and retry.',
      );
    }
  }

  @override
  Future<void> cancelOrder({required String orderId, String? reason}) async {
    try {
      final response = await _supabase.functions.invoke(
        'cancel-order',
        body: {
          'order_id': orderId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['success'] == false) {
        throw CheckoutException(
          code: data['error_code'] as String? ?? 'CANCELLATION_FAILED',
          message: data['message'] as String? ?? 'Failed to cancel order.',
        );
      }
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        throw CheckoutException(
          code: details['error_code'] as String? ?? 'CANCELLATION_FAILED',
          message: details['message'] as String? ?? e.toString(),
        );
      }
      throw CheckoutException(
        code: 'CANCELLATION_FAILED',
        message: details?.toString() ?? e.toString(),
      );
    } catch (e) {
      if (e is CheckoutException) rethrow;
      throw const CheckoutException(
        code: 'NETWORK_ERROR',
        message:
            'Cancellation failed. Please check your connection and try again.',
      );
    }
  }
}

final checkoutRepositoryProvider = Provider<ICheckoutRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final ordersRepo = ref.watch(ordersRepositoryProvider);
  return SupabaseCheckoutRepository(
    supabaseClient: supabase,
    ordersRepository: ordersRepo,
  );
});

class CheckoutQuoteParams {
  const CheckoutQuoteParams({
    this.addressId,
    this.deliverySlotId,
    this.couponCode,
  });

  final String? addressId;
  final String? deliverySlotId;
  final String? couponCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckoutQuoteParams &&
          runtimeType == other.runtimeType &&
          addressId == other.addressId &&
          deliverySlotId == other.deliverySlotId &&
          couponCode == other.couponCode;

  @override
  int get hashCode =>
      addressId.hashCode ^ deliverySlotId.hashCode ^ couponCode.hashCode;
}

final checkoutQuoteProvider =
    FutureProvider.family<CheckoutQuote, CheckoutQuoteParams>((
      ref,
      params,
    ) async {
      final repo = ref.watch(checkoutRepositoryProvider);
      return repo.getCheckoutQuote(
        addressId: params.addressId,
        deliverySlotId: params.deliverySlotId,
        couponCode: params.couponCode,
      );
    });
