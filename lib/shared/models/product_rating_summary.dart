class ProductRatingSummary {
  const ProductRatingSummary({
    required this.averageRating,
    required this.reviewCount,
    required this.breakdown,
  });

  final double averageRating;
  final int reviewCount;
  final Map<int, int> breakdown;

  factory ProductRatingSummary.fromJson(Map<String, dynamic> json) {
    final breakdownMap = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    if (json['breakdown'] != null && json['breakdown'] is Map) {
      final raw = json['breakdown'] as Map;
      for (int i = 1; i <= 5; i++) {
        final val = raw[i.toString()] ?? raw[i];
        if (val is num) {
          breakdownMap[i] = val.toInt();
        }
      }
    }
    return ProductRatingSummary(
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: json['review_count'] as int? ?? 0,
      breakdown: breakdownMap,
    );
  }

  static const ProductRatingSummary empty = ProductRatingSummary(
    averageRating: 0.0,
    reviewCount: 0,
    breakdown: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
  );

  double starPercentage(int star) {
    if (reviewCount <= 0) return 0.0;
    final count = breakdown[star] ?? 0;
    return count / reviewCount;
  }
}
