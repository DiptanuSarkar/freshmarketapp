class PaymentVerificationResult {
  const PaymentVerificationResult({
    required this.success,
    this.verified = false,
    this.captured = false,
    required this.internalOrderId,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    this.errorCode,
    this.message,
    this.reconciled = false,
  });

  final bool success;
  final bool verified;
  final bool captured;
  final String internalOrderId;
  final String orderNumber;
  final String status;
  final String paymentStatus;
  final String? errorCode;
  final String? message;
  final bool reconciled;

  bool get isOrderConfirmed =>
      status.toLowerCase() == 'confirmed' &&
      paymentStatus.toLowerCase() == 'completed';

  factory PaymentVerificationResult.fromJson(Map<String, dynamic> json) {
    return PaymentVerificationResult(
      success: json['success'] as bool? ?? false,
      verified: json['verified'] as bool? ?? false,
      captured: json['captured'] as bool? ?? false,
      internalOrderId: json['internal_order_id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      status: json['status'] as String? ?? 'payment_pending',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
      reconciled: json['reconciled'] as bool? ?? false,
    );
  }

  factory PaymentVerificationResult.failure({
    required String internalOrderId,
    required String orderNumber,
    required String errorCode,
    required String message,
  }) {
    return PaymentVerificationResult(
      success: false,
      verified: false,
      captured: false,
      internalOrderId: internalOrderId,
      orderNumber: orderNumber,
      status: 'payment_pending',
      paymentStatus: 'failed',
      errorCode: errorCode,
      message: message,
    );
  }
}
