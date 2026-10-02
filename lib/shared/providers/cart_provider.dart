import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class CartState {
  const CartState({
    this.items = const {},
    this.appliedCouponCode,
    this.couponDiscount = 0.0,
    this.useWallet = false,
  });

  final Map<String, CartItem>
  items; // Keyed by cartKey = "${product.id}_${variant.id}"
  final String? appliedCouponCode;
  final double couponDiscount;
  final bool useWallet;

  int get totalItemCount =>
      items.values.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      items.values.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get originalTotal =>
      items.values.fold(0.0, (sum, item) => sum + item.totalOriginalPrice);

  double get productSavings => originalTotal - subtotal;

  double get deliveryFee => (subtotal == 0 || subtotal >= 499.0) ? 0.0 : 39.0;

  double get totalPayable {
    final raw = subtotal - couponDiscount + deliveryFee;
    return raw > 0 ? raw : 0.0;
  }

  bool get isEmpty => items.isEmpty;

  CartState copyWith({
    Map<String, CartItem>? items,
    String? appliedCouponCode,
    double? couponDiscount,
    bool? useWallet,
  }) {
    return CartState(
      items: items ?? this.items,
      appliedCouponCode: appliedCouponCode ?? this.appliedCouponCode,
      couponDiscount: couponDiscount ?? this.couponDiscount,
      useWallet: useWallet ?? this.useWallet,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    return const CartState();
  }

  void addItem(Product product, ProductVariant variant, {int qty = 1}) {
    final key = '${product.id}_${variant.id}';
    final existing = state.items[key];

    final updatedItems = Map<String, CartItem>.from(state.items);
    if (existing != null) {
      updatedItems[key] = existing.copyWith(quantity: existing.quantity + qty);
    } else {
      updatedItems[key] = CartItem(
        product: product,
        selectedVariant: variant,
        quantity: qty,
      );
    }
    state = state.copyWith(items: updatedItems);
  }

  void updateQuantity(String cartKey, int delta) {
    final existing = state.items[cartKey];
    if (existing == null) return;

    final updatedItems = Map<String, CartItem>.from(state.items);
    final newQty = existing.quantity + delta;

    if (newQty <= 0) {
      updatedItems.remove(cartKey);
    } else {
      updatedItems[cartKey] = existing.copyWith(quantity: newQty);
    }
    state = state.copyWith(items: updatedItems);
  }

  void removeItem(String cartKey) {
    final updatedItems = Map<String, CartItem>.from(state.items);
    updatedItems.remove(cartKey);
    state = state.copyWith(items: updatedItems);
  }

  void applyCoupon(String code) {
    if (code.toUpperCase() == 'FRESH50' && state.subtotal >= 299) {
      state = state.copyWith(
        appliedCouponCode: 'FRESH50',
        couponDiscount: 50.0,
      );
    }
  }

  void removeCoupon() {
    state = state.copyWith(appliedCouponCode: null, couponDiscount: 0.0);
  }

  void toggleWallet(bool value) {
    state = state.copyWith(useWallet: value);
  }

  void clearCart() {
    state = const CartState();
  }

  int getItemQuantity(String productId, String variantId) {
    final key = '${productId}_$variantId';
    return state.items[key]?.quantity ?? 0;
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);
