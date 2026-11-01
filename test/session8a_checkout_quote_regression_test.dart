import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/core/supabase/supabase_client_provider.dart';
import 'package:freshmarket/features/cart/data/cart_repository.dart';
import 'package:freshmarket/features/checkout/data/checkout_quote_model.dart';
import 'package:freshmarket/features/checkout/data/checkout_repository.dart';
import 'package:freshmarket/shared/models/cart_item.dart';
import 'package:freshmarket/shared/models/order.dart';
import 'package:freshmarket/shared/models/product.dart';
import 'package:freshmarket/shared/models/product_variant.dart';
import 'package:freshmarket/shared/providers/cart_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DynamicQuoteFakeCheckoutRepository implements ICheckoutRepository {
  DynamicQuoteFakeCheckoutRepository(this.ref);

  final Ref ref;

  @override
  Future<CheckoutQuote> getCheckoutQuote({
    String? addressId,
    String? deliverySlotId,
    String? couponCode,
    bool? useWallet,
  }) async {
    final cartState = ref.read(cartProvider);
    final items = cartState.items.values.toList();

    double subtotal = 0.0;
    final quoteItems = <CheckoutQuoteItem>[];

    for (final item in items) {
      final lineTotal = item.selectedVariant.price * item.quantity;
      subtotal += lineTotal;
      quoteItems.add(
        CheckoutQuoteItem(
          cartItemId: item.id ?? '',
          variantId: item.selectedVariant.id,
          productId: item.product.id,
          productName: item.product.name,
          variantTitle: item.selectedVariant.title,
          sku: item.selectedVariant.sku,
          weight: '${item.selectedVariant.weightInGrams}g',
          unitPrice: item.selectedVariant.price,
          originalPrice:
              item.selectedVariant.originalPrice ?? item.selectedVariant.price,
          quantity: item.quantity,
          totalPrice: lineTotal,
          imageUrl: '',
          availableStock: 50,
          isStockAvailable: true,
        ),
      );
    }

    final deliveryFee = subtotal >= 499.0 ? 0.0 : 30.0;
    final grandTotal = subtotal + deliveryFee;

    return CheckoutQuote(
      cartId: 'test-cart-id',
      items: quoteItems,
      itemCount: quoteItems.length,
      subtotal: subtotal,
      itemDiscount: 0.0,
      couponDiscount: 0.0,
      couponApplied: false,
      deliveryFee: deliveryFee,
      platformFee: 0.0,
      taxAmount: 0.0,
      walletAmount: 0.0,
      grandTotal: grandTotal,
      codPayableTotal: grandTotal,
      gatewayPayable: grandTotal,
      stockValid: true,
      serviceable: true,
      minOrderForFreeDelivery: 499.0,
      slotValid: true,
      addressId: addressId,
      deliverySlotId: deliverySlotId,
    );
  }

  @override
  Future<CustomerOrder> createCodOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CustomerOrder> createWalletPaymentOrder({
    required String checkoutRequestId,
    required String addressId,
    required String deliverySlotId,
    String? couponCode,
    String? customerNotes,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> cancelOrder({
    required String orderId,
    String? reason,
  }) async {
    throw UnimplementedError();
  }
}

class InMemoryCartRepository implements ICartRepository {
  final List<CartItem> _items = [];

  @override
  Future<List<CartItem>> getCartItems() async => List.unmodifiable(_items);

  @override
  Future<void> addItem(
    Product product,
    ProductVariant variant, {
    int quantity = 1,
  }) async {
    final idx = _items.indexWhere((i) => i.selectedVariant.id == variant.id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(
        quantity: _items[idx].quantity + quantity,
      );
    } else {
      _items.add(
        CartItem(
          id: 'cart-item-${variant.id}',
          product: product,
          selectedVariant: variant,
          quantity: quantity,
        ),
      );
    }
  }

  @override
  Future<void> updateQuantity(String variantId, int newQuantity) async {
    final idx = _items.indexWhere((i) => i.selectedVariant.id == variantId);
    if (idx != -1) {
      if (newQuantity <= 0) {
        _items.removeAt(idx);
      } else {
        _items[idx] = _items[idx].copyWith(quantity: newQuantity);
      }
    }
  }

  @override
  Future<void> removeItem(String variantId) async {
    _items.removeWhere((i) => i.selectedVariant.id == variantId);
  }

  @override
  Future<void> clearCart() async {
    _items.clear();
  }
}

User createTestUser() {
  return const User(
    id: 'test-user-uuid-1234',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
}

ProductVariant createVariant({
  required String id,
  required String title,
  required double price,
  double? originalPrice,
  int stock = 20,
}) {
  return ProductVariant(
    id: id,
    sku: 'SKU-$id',
    title: title,
    weightInGrams: 500,
    price: price,
    originalPrice: originalPrice,
    stockQuantity: stock,
    isAvailable: true,
  );
}

Product createProduct({
  required String id,
  required String name,
  required ProductVariant variant,
}) {
  return Product(
    id: id,
    name: name,
    categorySlug: 'chicken',
    shortDescription: 'Fresh cut meat',
    description: 'Antibiotic-free meat.',
    images: const ['https://example.com/img.jpg'],
    variants: [variant],
  );
}

void main() {
  group(
    'Session 8A — Checkout Quote Dynamic Invalidation Regression Tests',
    () {
      final variantChickenCut = createVariant(
        id: 'var-chicken-155',
        title: '500g Pack',
        price: 155.0,
        originalPrice: 180.0,
      );
      final productChicken = createProduct(
        id: 'prod-chicken',
        name: 'Fresh Farm Chicken Curry Cut',
        variant: variantChickenCut,
      );

      final variantChickenBreast = createVariant(
        id: 'var-breast-210',
        title: '500g Fillet',
        price: 210.0,
        originalPrice: 240.0,
      );
      final productBreast = createProduct(
        id: 'prod-breast',
        name: 'Premium Chicken Breast Boneless',
        variant: variantChickenBreast,
      );

      final variantGoat = createVariant(
        id: 'var-goat-460',
        title: '500g Curry Cut',
        price: 460.0,
        originalPrice: 490.0,
      );
      final productGoat = createProduct(
        id: 'prod-goat',
        name: 'Rich Goat Curry Cut',
        variant: variantGoat,
      );

      test('checkoutQuoteProvider dynamically recalculates when cart contents change, preventing stale ₹185 quote bug', () async {
        final cartRepo = InMemoryCartRepository();
        final testUser = createTestUser();

        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            cartRepositoryProvider.overrideWithValue(cartRepo),
            checkoutRepositoryProvider.overrideWith(
              (ref) => DynamicQuoteFakeCheckoutRepository(ref),
            ),
          ],
        );
        addTearDown(container.dispose);

        // 1. Initial Cart: 1x Fresh Farm Chicken Curry Cut (₹155 + ₹30 = ₹185)
        await container
            .read(cartProvider.notifier)
            .addItem(productChicken, variantChickenCut, qty: 1);

        const quoteParams = CheckoutQuoteParams(
          addressId: 'addr-agartala-1',
          deliverySlotId: 'slot-morning',
        );

        final quoteSub = container.listen(
          checkoutQuoteProvider(quoteParams),
          (_, _) {},
        );
        addTearDown(quoteSub.close);

        final initialQuote = await container.read(
          checkoutQuoteProvider(quoteParams).future,
        );
        expect(initialQuote.subtotal, equals(155.0));
        expect(initialQuote.deliveryFee, equals(30.0));
        expect(initialQuote.grandTotal, equals(185.0));

        // 2. Change Cart: Clear and add ₹210 Premium Chicken Breast
        await container.read(cartProvider.notifier).clearCart();
        await container
            .read(cartProvider.notifier)
            .addItem(productBreast, variantChickenBreast, qty: 1);

        // Quote MUST automatically recalculate to ₹210 + ₹30 = ₹240
        // It must NOT return the stale cached ₹185 value
        final updatedQuote = await container.read(
          checkoutQuoteProvider(quoteParams).future,
        );
        expect(
          updatedQuote.subtotal,
          equals(210.0),
          reason:
              'Subtotal must match new product price (₹210), not stale ₹155',
        );
        expect(
          updatedQuote.grandTotal,
          equals(240.0),
          reason: 'Grand total must be ₹240, not stale ₹185',
        );

        // 3. Quantity Change: Increase quantity from 1 to 2 (+1 delta)
        final cartKey = '${productBreast.id}_${variantChickenBreast.id}';
        await container.read(cartProvider.notifier).updateQuantity(cartKey, 1);

        final qtyUpdatedQuote = await container.read(
          checkoutQuoteProvider(quoteParams).future,
        );
        expect(
          qtyUpdatedQuote.subtotal,
          equals(420.0),
          reason: 'Subtotal must update to 2 * ₹210 = ₹420',
        );
        expect(
          qtyUpdatedQuote.grandTotal,
          equals(450.0),
          reason: 'Grand total must update to ₹420 + ₹30 = ₹450',
        );

        // 4. Multi-Item Cart: Add 1x Rich Goat Curry Cut (₹460)
        // Subtotal = ₹420 + ₹460 = ₹880 (>= ₹499 -> FREE delivery!)
        await container
            .read(cartProvider.notifier)
            .addItem(productGoat, variantGoat, qty: 1);

        final multiItemQuote = await container.read(
          checkoutQuoteProvider(quoteParams).future,
        );
        expect(multiItemQuote.subtotal, equals(880.0));
        expect(
          multiItemQuote.deliveryFee,
          equals(0.0),
          reason: 'Orders >= ₹499 receive free delivery in Agartala',
        );
        expect(multiItemQuote.grandTotal, equals(880.0));
      });
    },
  );
}
