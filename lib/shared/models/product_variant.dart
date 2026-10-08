/// Unified SKU/variant model.
/// Every purchasable item maps to a [ProductVariant].
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.sku,
    required this.title,
    required this.weightInGrams,
    required this.price,
    this.originalPrice,
    this.stockQuantity = 50,
    this.isAvailable = true,
    this.netWeightDisplay,
    this.grossWeightDisplay,
    this.piecesCount,
    this.serves,
  });

  final String id;
  final String sku;
  final String title; // e.g. "500 g", "1 kg", "2 kg", "1 pack"
  final double weightInGrams;
  final double price;
  final double? originalPrice;
  final int stockQuantity;
  final bool isAvailable;
  final String? netWeightDisplay; // e.g. "Net wt: 450g | Gross: 500g"
  final String? grossWeightDisplay;
  final String? piecesCount;
  final String? serves;

  int get stock => stockQuantity;

  bool get hasDiscount => originalPrice != null && originalPrice! > price;

  int get discountPercentage {
    if (!hasDiscount) return 0;
    return (((originalPrice! - price) / originalPrice!) * 100).round();
  }

  bool get isOutOfStock => stockQuantity <= 0 || !isAvailable;
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= 5;
}
