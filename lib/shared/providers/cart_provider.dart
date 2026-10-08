import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client_provider.dart';
import '../../features/cart/data/cart_repository.dart';
import '../../features/checkout/data/coupon_repository.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/product_variant.dart';

class CartState {
  const CartState({
    this.items = const {},
    this.appliedCouponCode,
    this.couponDiscount = 0.0,
    this.useWallet = false,
    this.isLoading = false,
  });

  final Map<String, CartItem>
  items; // Keyed by cartKey = "${product.id}_${variant.id}"
  final String? appliedCouponCode;
  final double couponDiscount;
  final bool useWallet;
  final bool isLoading;

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
    bool? isLoading,
  }) {
    return CartState(
      items: items ?? this.items,
      appliedCouponCode: appliedCouponCode ?? this.appliedCouponCode,
      couponDiscount: couponDiscount ?? this.couponDiscount,
      useWallet: useWallet ?? this.useWallet,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const CartState();
    }

    Future.microtask(() => loadCart());
    return const CartState(isLoading: true);
  }

  Future<void> loadCart() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const CartState();
      return;
    }

    try {
      final repo = ref.read(cartRepositoryProvider);
      final itemList = await repo.getCartItems();
      final map = <String, CartItem>{};
      for (final item in itemList) {
        final key = '${item.product.id}_${item.selectedVariant.id}';
        map[key] = item;
      }
      state = state.copyWith(items: map, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> addItem(
    Product product,
    ProductVariant variant, {
    int qty = 1,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return false; // Authentication required
    }

    final key = '${product.id}_${variant.id}';
    final existing = state.items[key];
    final prevItems = Map<String, CartItem>.from(state.items);

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

    try {
      final repo = ref.read(cartRepositoryProvider);
      await repo.addItem(product, variant, quantity: qty);
      return true;
    } catch (e) {
      state = state.copyWith(items: prevItems); // Rollback
      return false;
    }
  }

  Future<void> updateQuantity(String cartKey, int delta) async {
    final existing = state.items[cartKey];
    if (existing == null) return;

    final prevItems = Map<String, CartItem>.from(state.items);
    final updatedItems = Map<String, CartItem>.from(state.items);
    final newQty = existing.quantity + delta;

    if (newQty <= 0) {
      updatedItems.remove(cartKey);
    } else {
      updatedItems[cartKey] = existing.copyWith(quantity: newQty);
    }
    state = state.copyWith(items: updatedItems);

    try {
      final repo = ref.read(cartRepositoryProvider);
      if (newQty <= 0) {
        await repo.removeItem(existing.selectedVariant.id);
      } else {
        await repo.updateQuantity(existing.selectedVariant.id, newQty);
      }
    } catch (e) {
      state = state.copyWith(items: prevItems); // Rollback
    }
  }

  Future<void> removeItem(String cartKey) async {
    final existing = state.items[cartKey];
    if (existing == null) return;

    final prevItems = Map<String, CartItem>.from(state.items);
    final updatedItems = Map<String, CartItem>.from(state.items);
    updatedItems.remove(cartKey);
    state = state.copyWith(items: updatedItems);

    try {
      final repo = ref.read(cartRepositoryProvider);
      await repo.removeItem(existing.selectedVariant.id);
    } catch (e) {
      state = state.copyWith(items: prevItems); // Rollback
    }
  }

  /// Validates and applies a coupon code against Supabase coupons table.
  /// Returns an error message if invalid, or null if successfully applied.
  /// NOTE: This preview discount is for UX only. Server re-validation occurs at checkout.
  Future<String?> applyCoupon(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      return 'Please enter a coupon code';
    }
    try {
      final couponRepo = ref.read(couponRepositoryProvider);
      final coupon = await couponRepo.getCouponByCode(cleanCode);
      if (coupon == null) {
        return 'Invalid or expired coupon code';
      }
      final currentSubtotal = state.subtotal;
      if (currentSubtotal < coupon.minOrderAmount) {
        return 'Minimum order amount for ${coupon.code} is ₹${coupon.minOrderAmount.toInt()}';
      }
      final discount = coupon.calculateDiscountPreview(currentSubtotal);
      if (discount <= 0) {
        return 'Coupon conditions not met for this order';
      }
      state = state.copyWith(
        appliedCouponCode: coupon.code,
        couponDiscount: discount,
      );
      return null;
    } catch (e) {
      return 'Could not validate coupon. Please try again.';
    }
  }

  void removeCoupon() {
    state = state.copyWith(appliedCouponCode: null, couponDiscount: 0.0);
  }

  void toggleWallet(bool value) {
    state = state.copyWith(useWallet: value);
  }

  Future<void> clearCart() async {
    final prevItems = Map<String, CartItem>.from(state.items);
    state = const CartState();

    try {
      final repo = ref.read(cartRepositoryProvider);
      await repo.clearCart();
    } catch (e) {
      state = state.copyWith(items: prevItems);
    }
  }

  int getItemQuantity(String productId, String variantId) {
    final key = '${productId}_$variantId';
    return state.items[key]?.quantity ?? 0;
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);
