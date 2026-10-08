import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../data/payment_verification_model.dart';
import '../../data/razorpay_order_model.dart';
import '../../data/razorpay_payment_repository.dart';

sealed class RazorpayCheckoutState {
  const RazorpayCheckoutState();
}

class RazorpayStateIdle extends RazorpayCheckoutState {
  const RazorpayStateIdle();
}

class RazorpayStateInitializing extends RazorpayCheckoutState {
  const RazorpayStateInitializing();
}

class RazorpayStateCheckoutOpen extends RazorpayCheckoutState {
  const RazorpayStateCheckoutOpen(this.order);
  final RazorpayOrderModel order;
}

class RazorpayStateVerifying extends RazorpayCheckoutState {
  const RazorpayStateVerifying(this.internalOrderId);
  final String internalOrderId;
}

class RazorpayStateSuccess extends RazorpayCheckoutState {
  const RazorpayStateSuccess(this.result);
  final PaymentVerificationResult result;
}

class RazorpayStateFailed extends RazorpayCheckoutState {
  const RazorpayStateFailed({
    required this.code,
    required this.message,
    this.orderId,
  });
  final String code;
  final String message;
  final String? orderId;
}

class RazorpayStateCancelled extends RazorpayCheckoutState {
  const RazorpayStateCancelled({this.orderId});
  final String? orderId;
}

class RazorpayController extends Notifier<RazorpayCheckoutState> {
  Razorpay? _razorpay;
  String? _currentInternalOrderId;
  String? _currentRazorpayOrderId;

  @override
  RazorpayCheckoutState build() {
    _initRazorpay();
    ref.onDispose(() {
      _razorpay?.clear();
      _razorpay = null;
    });
    return const RazorpayStateIdle();
  }

  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// Start Online Checkout flow from Authoritative Cart
  Future<void> startCheckout({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  }) async {
    state = const RazorpayStateInitializing();
    final repo = ref.read(razorpayPaymentRepositoryProvider);

    try {
      final orderModel = await repo.createRazorpayOrder(
        checkoutRequestId: checkoutRequestId,
        addressId: addressId,
        deliverySlotId: deliverySlotId,
        couponCode: couponCode,
        customerNotes: customerNotes,
      );

      _currentInternalOrderId = orderModel.internalOrderId;
      _currentRazorpayOrderId = orderModel.razorpayOrderId;
      state = RazorpayStateCheckoutOpen(orderModel);

      // Open Razorpay Standard Checkout SDK
      final options = orderModel.toCheckoutOptions();
      _razorpay?.open(options);
    } on PaymentException catch (e) {
      state = RazorpayStateFailed(
        code: e.code,
        message: e.message,
        orderId: _currentInternalOrderId,
      );
    } catch (e) {
      state = RazorpayStateFailed(
        code: 'INITIALIZATION_FAILED',
        message: e.toString(),
        orderId: _currentInternalOrderId,
      );
    }
  }

  /// Retry payment for an existing payment_pending order
  Future<void> retryPayment({required String orderId}) async {
    state = const RazorpayStateInitializing();
    final repo = ref.read(razorpayPaymentRepositoryProvider);

    try {
      final orderModel = await repo.retryRazorpayOrder(orderId: orderId);

      _currentInternalOrderId = orderModel.internalOrderId;
      _currentRazorpayOrderId = orderModel.razorpayOrderId;
      state = RazorpayStateCheckoutOpen(orderModel);

      final options = orderModel.toCheckoutOptions();
      _razorpay?.open(options);
    } on PaymentException catch (e) {
      state = RazorpayStateFailed(
        code: e.code,
        message: e.message,
        orderId: orderId,
      );
    } catch (e) {
      state = RazorpayStateFailed(
        code: 'RETRY_FAILED',
        message: e.toString(),
        orderId: orderId,
      );
    }
  }

  /// Reconcile payment status from backend / gateway
  Future<PaymentVerificationResult> checkStatus({
    required String orderId,
  }) async {
    final repo = ref.read(razorpayPaymentRepositoryProvider);
    final result = await repo.checkPaymentStatus(orderId: orderId);
    if (result.isOrderConfirmed) {
      state = RazorpayStateSuccess(result);
    }
    return result;
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint(
      'Razorpay payment success event received: paymentId=${response.paymentId}, orderId=${response.orderId}',
    );

    final internalOrderId = _currentInternalOrderId;
    if (internalOrderId == null) {
      state = const RazorpayStateFailed(
        code: 'MISSING_ORDER_CONTEXT',
        message: 'Order reference lost during payment transition.',
      );
      return;
    }

    // Step 10: Show "Verifying payment…" until server verification completes
    state = RazorpayStateVerifying(internalOrderId);

    final repo = ref.read(razorpayPaymentRepositoryProvider);
    try {
      final verifyResult = await repo.verifyPayment(
        internalOrderId: internalOrderId,
        razorpayPaymentId: response.paymentId ?? '',
        razorpayOrderId: response.orderId ?? _currentRazorpayOrderId ?? '',
        razorpaySignature: response.signature ?? '',
      );

      if (verifyResult.isOrderConfirmed) {
        state = RazorpayStateSuccess(verifyResult);
      } else {
        state = RazorpayStateFailed(
          code: verifyResult.errorCode ?? 'VERIFICATION_UNCONFIRMED',
          message: verifyResult.message ?? "We're confirming your payment with the bank. Do not pay again yet.",
          orderId: internalOrderId,
        );
      }
    } catch (e) {
      state = RazorpayStateFailed(
        code: 'VERIFICATION_NETWORK_ERROR',
        message: "Network error during verification. We're checking your payment. Do not pay again yet.",
        orderId: internalOrderId,
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint(
      'Razorpay payment error event received: code=${response.code}, message=${response.message}',
    );

    // Code 2 in Razorpay SDK represents user dismiss / checkout closed
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      state = RazorpayStateCancelled(orderId: _currentInternalOrderId);
    } else {
      state = RazorpayStateFailed(
        code: 'GATEWAY_ERROR_${response.code}',
        message:
            response.message ?? 'Payment failed or was declined by your bank.',
        orderId: _currentInternalOrderId,
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('Razorpay external wallet selected: ${response.walletName}');
  }

  void reset() {
    state = const RazorpayStateIdle();
  }
}

final razorpayControllerProvider =
    NotifierProvider<RazorpayController, RazorpayCheckoutState>(
      RazorpayController.new,
    );
