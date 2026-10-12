/// Typed Refund Status and normalized components for FreshMarket
enum RefundStatus {
  initiated,
  processing,
  processed,
  failed;

  static RefundStatus fromString(String? value) {
    if (value == null) return RefundStatus.initiated;
    final lower = value.toLowerCase().trim();
    switch (lower) {
      case 'processed':
      case 'completed': // historical alias
      case 'success':
        return RefundStatus.processed;
      case 'processing':
      case 'pending':
        return RefundStatus.processing;
      case 'failed':
      case 'error':
        return RefundStatus.failed;
      case 'initiated':
      default:
        return RefundStatus.initiated;
    }
  }

  bool get isProcessed => this == RefundStatus.processed;
  bool get isProcessing => this == RefundStatus.processing;
  bool get isFailed => this == RefundStatus.failed;
  bool get isInitiated => this == RefundStatus.initiated;

  String get label {
    switch (this) {
      case RefundStatus.processed:
        return 'Processed';
      case RefundStatus.processing:
        return 'Processing';
      case RefundStatus.failed:
        return 'Failed';
      case RefundStatus.initiated:
        return 'Initiated';
    }
  }
}

class RefundComponent {
  const RefundComponent({
    required this.id,
    required this.refundId,
    required this.method,
    required this.amount,
    required this.status,
    this.gatewayRefundId,
    this.providerStatus,
    this.processedAt,
    this.failedAt,
  });

  final String id;
  final String refundId;
  final String method; // 'wallet' or 'razorpay'
  final double amount;
  final RefundStatus status;
  final String? gatewayRefundId;
  final String? providerStatus;
  final DateTime? processedAt;
  final DateTime? failedAt;

  bool get isWallet => method.toLowerCase() == 'wallet';
  bool get isRazorpay => method.toLowerCase() == 'razorpay';

  factory RefundComponent.fromJson(Map<String, dynamic> json) {
    return RefundComponent(
      id: json['id'] as String? ?? '',
      refundId: json['refund_id'] as String? ?? '',
      method: json['method'] as String? ?? 'wallet',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: RefundStatus.fromString(json['status'] as String?),
      gatewayRefundId: json['gateway_refund_id'] as String?,
      providerStatus: json['provider_status'] as String?,
      processedAt: json['processed_at'] != null
          ? DateTime.tryParse(json['processed_at'] as String)
          : null,
      failedAt: json['failed_at'] != null
          ? DateTime.tryParse(json['failed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'refund_id': refundId,
    'method': method,
    'amount': amount,
    'status': status.name,
    'gateway_refund_id': gatewayRefundId,
    'provider_status': providerStatus,
    'processed_at': processedAt?.toIso8601String(),
    'failed_at': failedAt?.toIso8601String(),
  };
}

class RefundModel {
  const RefundModel({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.status,
    required this.walletAmount,
    required this.gatewayAmount,
    this.reason,
    this.components = const [],
    this.requestedAt,
    this.processedAt,
    this.failedAt,
    this.errorMessage,
  });

  final String id;
  final String orderId;
  final double amount;
  final RefundStatus status;
  final double walletAmount;
  final double gatewayAmount;
  final String? reason;
  final List<RefundComponent> components;
  final DateTime? requestedAt;
  final DateTime? processedAt;
  final DateTime? failedAt;
  final String? errorMessage;

  factory RefundModel.fromJson(Map<String, dynamic> json) {
    final rawComponents = json['refund_components'] as List<dynamic>? ?? [];
    final comps = rawComponents
        .whereType<Map<String, dynamic>>()
        .map(RefundComponent.fromJson)
        .toList();

    return RefundModel(
      id: json['id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      status: RefundStatus.fromString(json['status'] as String?),
      walletAmount: (json['wallet_amount'] as num?)?.toDouble() ?? 0.0,
      gatewayAmount: (json['gateway_amount'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String?,
      components: comps,
      requestedAt: json['requested_at'] != null
          ? DateTime.tryParse(json['requested_at'] as String)
          : null,
      processedAt: json['processed_at'] != null
          ? DateTime.tryParse(json['processed_at'] as String)
          : null,
      failedAt: json['failed_at'] != null
          ? DateTime.tryParse(json['failed_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'amount': amount,
    'status': status.name,
    'wallet_amount': walletAmount,
    'gateway_amount': gatewayAmount,
    'reason': reason,
    'components': components.map((c) => c.toJson()).toList(),
    'requested_at': requestedAt?.toIso8601String(),
    'processed_at': processedAt?.toIso8601String(),
    'failed_at': failedAt?.toIso8601String(),
    'error_message': errorMessage,
  };
}
