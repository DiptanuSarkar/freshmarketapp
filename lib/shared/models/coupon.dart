/// Coupon representation for client-side preview.
/// NOTE: Authoritative discount redemption is enforced server-side.
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    this.maxDiscountAmount,
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String description;
  final String discountType; // 'flat' or 'percentage'
  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscountAmount;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: json['id'] as String,
      code: json['code'] as String,
      description: json['description'] as String? ?? '',
      discountType: json['discount_type'] as String,
      discountValue: (json['discount_value'] as num).toDouble(),
      minOrderAmount: (json['min_order_amount'] as num?)?.toDouble() ?? 0.0,
      maxDiscountAmount: (json['max_discount_amount'] as num?)?.toDouble(),
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Calculates preview discount for UX guidance only.
  /// Server revalidation is mandatory during checkout.
  double calculateDiscountPreview(double subtotal) {
    if (subtotal < minOrderAmount) return 0.0;
    final now = DateTime.now();
    if (now.isBefore(startsAt) || now.isAfter(endsAt) || !isActive) return 0.0;

    double calculated;
    if (discountType == 'percentage') {
      calculated = (subtotal * discountValue) / 100.0;
    } else {
      calculated = discountValue;
    }

    if (maxDiscountAmount != null && calculated > maxDiscountAmount!) {
      calculated = maxDiscountAmount!;
    }
    return calculated > subtotal ? subtotal : calculated;
  }
}
