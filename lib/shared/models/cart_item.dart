import 'product.dart';
import 'product_variant.dart';

class CartItem {
  const CartItem({
    this.id,
    required this.product,
    required this.selectedVariant,
    this.quantity = 1,
  });

  final String? id;
  final Product product;
  final ProductVariant selectedVariant;
  final int quantity;

  String get cartKey => '${product.id}_${selectedVariant.id}';

  double get totalPrice => selectedVariant.price * quantity;

  double get totalOriginalPrice =>
      (selectedVariant.originalPrice ?? selectedVariant.price) * quantity;

  double get totalSavings => totalOriginalPrice - totalPrice;

  CartItem copyWith({
    String? id,
    Product? product,
    ProductVariant? selectedVariant,
    int? quantity,
  }) {
    return CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      selectedVariant: selectedVariant ?? this.selectedVariant,
      quantity: quantity ?? this.quantity,
    );
  }
}
