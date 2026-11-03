class ProductReview {
  const ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    this.authorName = 'Verified Buyer',
    required this.rating,
    this.title,
    this.reviewText,
    this.isVerifiedPurchase = false,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String userId;
  final String authorName;
  final int rating;
  final String? title;
  final String? reviewText;
  final bool isVerifiedPurchase;
  final DateTime createdAt;

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    String author = 'Verified Customer';
    if (json['profiles'] != null && json['profiles'] is Map) {
      author = json['profiles']['full_name'] as String? ?? 'Verified Customer';
    }
    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      userId: json['user_id'] as String,
      authorName: author,
      rating: json['rating'] as int? ?? 5,
      title: json['title'] as String?,
      reviewText: json['review_text'] as String?,
      isVerifiedPurchase: json['is_verified_purchase'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  ProductReview copyWith({
    String? id,
    String? productId,
    String? userId,
    String? authorName,
    int? rating,
    String? title,
    String? reviewText,
    bool? isVerifiedPurchase,
    DateTime? createdAt,
  }) {
    return ProductReview(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      rating: rating ?? this.rating,
      title: title ?? this.title,
      reviewText: reviewText ?? this.reviewText,
      isVerifiedPurchase: isVerifiedPurchase ?? this.isVerifiedPurchase,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
