import 'product.dart';
import 'product_variant.dart';

class CartItem {
  const CartItem({
    required this.product,
    required this.selectedVariant,
    this.quantity = 1,
  });

  final Product product;
  final ProductVariant selectedVariant;
  final int quantity;

  String get cartKey => '${product.id}_${selectedVariant.id}';

  double get totalPrice => selectedVariant.price * quantity;

  double get totalOriginalPrice =>
      (selectedVariant.originalPrice ?? selectedVariant.price) * quantity;

  double get totalSavings => totalOriginalPrice - totalPrice;

  CartItem copyWith({
    Product? product,
    ProductVariant? selectedVariant,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      selectedVariant: selectedVariant ?? this.selectedVariant,
      quantity: quantity ?? this.quantity,
    );
  }
}
