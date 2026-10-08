class RazorpayOrderModel {
  const RazorpayOrderModel({
    required this.internalOrderId,
    required this.internalOrderNumber,
    required this.paymentId,
    required this.razorpayOrderId,
    required this.razorpayKeyId,
    required this.amountPaise,
    this.currency = 'INR',
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
    this.isIdempotentRetry = false,
  });

  final String internalOrderId;
  final String internalOrderNumber;
  final String paymentId;
  final String razorpayOrderId;
  final String razorpayKeyId;
  final int amountPaise;
  final String currency;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;
  final bool isIdempotentRetry;

  double get amountRupees => amountPaise / 100.0;

  factory RazorpayOrderModel.fromJson(Map<String, dynamic> json) {
    final prefill = json['prefill'] as Map<String, dynamic>?;
    return RazorpayOrderModel(
      internalOrderId: json['internal_order_id'] as String,
      internalOrderNumber:
          json['internal_order_number'] as String? ?? 'FM-ORDER',
      paymentId: json['payment_id'] as String,
      razorpayOrderId: json['razorpay_order_id'] as String,
      razorpayKeyId: json['razorpay_key_id'] as String,
      amountPaise: (json['amount_paise'] as num).toInt(),
      currency: json['currency'] as String? ?? 'INR',
      prefillName: prefill?['name'] as String?,
      prefillEmail: prefill?['email'] as String?,
      prefillContact: prefill?['contact'] as String?,
      isIdempotentRetry: json['is_idempotent_retry'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCheckoutOptions({String appName = 'FreshMarket'}) {
    return {
      'key': razorpayKeyId,
      'amount': amountPaise,
      'name': appName,
      'description': 'Order #$internalOrderNumber',
      'order_id': razorpayOrderId,
      'currency': currency,
      'timeout': 300, // 5 minute gateway checkout sheet timeout
      'prefill': {
        if (prefillContact != null && prefillContact!.isNotEmpty)
          'contact': prefillContact,
        if (prefillEmail != null && prefillEmail!.isNotEmpty)
          'email': prefillEmail,
        if (prefillName != null && prefillName!.isNotEmpty) 'name': prefillName,
      },
      'send_sms_hash': false,
      'theme': {
        'color': '#00875A', // FreshMarket primary green
      },
      'retry': {'enabled': true, 'max_count': 3},
    };
  }
}
