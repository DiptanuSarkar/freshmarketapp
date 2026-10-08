import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import 'payment_verification_model.dart';
import 'razorpay_order_model.dart';

class PaymentException implements Exception {
  const PaymentException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class IRazorpayPaymentRepository {
  Future<RazorpayOrderModel> createRazorpayOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  });

  Future<RazorpayOrderModel> retryRazorpayOrder({required String orderId});

  Future<PaymentVerificationResult> verifyPayment({
    required String internalOrderId,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  });

  Future<PaymentVerificationResult> checkPaymentStatus({
    required String orderId,
  });
}

class SupabaseRazorpayPaymentRepository implements IRazorpayPaymentRepository {
  SupabaseRazorpayPaymentRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<RazorpayOrderModel> createRazorpayOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-razorpay-order',
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
          throw PaymentException(
            code: data['error_code'] as String? ?? 'PAYMENT_INIT_FAILED',
            message:
                data['message'] as String? ??
                'Unable to initialize online payment',
          );
        }
        return RazorpayOrderModel.fromJson(data);
      }

      throw const PaymentException(
        code: 'PAYMENT_INIT_FAILED',
        message: 'Invalid response from payment creation service.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        throw PaymentException(
          code: details['error_code'] as String? ?? 'PAYMENT_INIT_FAILED',
          message: details['message'] as String? ?? e.toString(),
        );
      }
      throw PaymentException(
        code: 'PAYMENT_INIT_FAILED',
        message: details?.toString() ?? e.toString(),
      );
    }
  }

  @override
  Future<RazorpayOrderModel> retryRazorpayOrder({
    required String orderId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-razorpay-order',
        body: {'order_id': orderId},
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['success'] == false) {
          throw PaymentException(
            code: data['error_code'] as String? ?? 'PAYMENT_RETRY_FAILED',
            message: data['message'] as String? ?? 'Unable to retry payment',
          );
        }
        return RazorpayOrderModel.fromJson(data);
      }

      throw const PaymentException(
        code: 'PAYMENT_RETRY_FAILED',
        message: 'Invalid response from payment retry service.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        throw PaymentException(
          code: details['error_code'] as String? ?? 'PAYMENT_RETRY_FAILED',
          message: details['message'] as String? ?? e.toString(),
        );
      }
      throw PaymentException(
        code: 'PAYMENT_RETRY_FAILED',
        message: details?.toString() ?? e.toString(),
      );
    }
  }

  @override
  Future<PaymentVerificationResult> verifyPayment({
    required String internalOrderId,
    required String razorpayPaymentId,
    required String razorpayOrderId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'internal_order_id': internalOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_signature': razorpaySignature,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return PaymentVerificationResult.fromJson(data);
      }

      return PaymentVerificationResult.failure(
        internalOrderId: internalOrderId,
        orderNumber: '',
        errorCode: 'VERIFICATION_PARSE_ERROR',
        message: 'Invalid response format from payment verification.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        return PaymentVerificationResult.fromJson(details);
      }
      return PaymentVerificationResult.failure(
        internalOrderId: internalOrderId,
        orderNumber: '',
        errorCode: 'VERIFICATION_SERVICE_ERROR',
        message: details?.toString() ?? e.toString(),
      );
    }
  }

  @override
  Future<PaymentVerificationResult> checkPaymentStatus({
    required String orderId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'check-payment-status',
        body: {'order_id': orderId},
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return PaymentVerificationResult.fromJson(data);
      }

      return PaymentVerificationResult.failure(
        internalOrderId: orderId,
        orderNumber: '',
        errorCode: 'STATUS_PARSE_ERROR',
        message: 'Invalid response format from status check.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic>) {
        return PaymentVerificationResult.fromJson(details);
      }
      return PaymentVerificationResult.failure(
        internalOrderId: orderId,
        orderNumber: '',
        errorCode: 'STATUS_SERVICE_ERROR',
        message: details?.toString() ?? e.toString(),
      );
    }
  }
}

final razorpayPaymentRepositoryProvider = Provider<IRazorpayPaymentRepository>((
  ref,
) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseRazorpayPaymentRepository(supabase);
});
