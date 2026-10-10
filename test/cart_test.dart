import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshmarket/core/supabase/supabase_client_provider.dart';
import 'package:freshmarket/core/supabase/supabase_exception_mapper.dart';
import 'package:freshmarket/features/cart/data/cart_repository.dart';
import 'package:freshmarket/features/cart/presentation/cart_screen.dart';
import 'package:freshmarket/shared/models/cart_item.dart';
import 'package:freshmarket/shared/models/product.dart';
import 'package:freshmarket/shared/models/product_variant.dart';
import 'package:freshmarket/shared/providers/cart_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeCartRepository implements ICartRepository {
  FakeCartRepository({
    List<CartItem>? initialItems,
    this.shouldThrow = false,
    this.errorMessage = 'Database connection failed',
  }) : _items = List.of(initialItems ?? []);

  final List<CartItem> _items;
  bool shouldThrow;
  String errorMessage;
  int getItemsCallCount = 0;

  @override
  Future<List<CartItem>> getCartItems() async {
    getItemsCallCount++;
    if (shouldThrow) {
      throw AppException(errorMessage);
    }
    return List.unmodifiable(_items);
  }

  @override
  Future<void> addItem(
    Product product,
    ProductVariant variant, {
    int quantity = 1,
  }) async {
    if (shouldThrow) throw AppException(errorMessage);
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
    if (shouldThrow) throw AppException(errorMessage);
    if (newQuantity <= 0) {
      _items.removeWhere((i) => i.selectedVariant.id == variantId);
    } else {
      final idx = _items.indexWhere((i) => i.selectedVariant.id == variantId);
      if (idx != -1) {
        _items[idx] = _items[idx].copyWith(quantity: newQuantity);
      }
    }
  }

  @override
  Future<void> removeItem(String variantId) async {
    if (shouldThrow) throw AppException(errorMessage);
    _items.removeWhere((i) => i.selectedVariant.id == variantId);
  }

  @override
  Future<void> clearCart() async {
    if (shouldThrow) throw AppException(errorMessage);
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
  String id = 'var-1',
  String title = '500g Pack',
  double price = 180.0,
  double? originalPrice,
  int stock = 20,
  bool isAvailable = true,
}) {
  return ProductVariant(
    id: id,
    sku: 'SKU-$id',
    title: title,
    weightInGrams: 500,
    price: price,
    originalPrice: originalPrice,
    stockQuantity: stock,
    isAvailable: isAvailable,
  );
}

Product createProduct({
  String id = 'prod-1',
  String name = 'Fresh Farm Chicken Curry Cut',
  List<String> images = const [
    'https://images.unsplash.com/photo-1587593810167-a84920ea0781',
  ],
  List<ProductVariant>? variants,
}) {
  final vars = variants ?? [createVariant()];
  return Product(
    id: id,
    name: name,
    categorySlug: 'chicken',
    shortDescription: 'Fresh bone-in chicken curry cut',
    description: 'Antibiotic-free tender chicken.',
    images: images,
    variants: vars,
  );
}

void main() {
  group('Cart Architectural & Coverage Suite (13 Specific Requirements)', () {
    // 1. cart loading state
    test('1. cart loading state initializes with isLoading: true', () {
      final testUser = createTestUser();
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(cartProvider);
      expect(state.isLoading, isTrue);
      expect(state.items, isEmpty);
      expect(state.hasError, isFalse);
    });

    // 2. cart loaded with one item
    test(
      '2. cart loaded with one item populates items and calculates totals',
      () async {
        final testUser = createTestUser();
        final variant = createVariant(id: 'var-1', price: 150.0);
        final product = createProduct(id: 'prod-1', variants: [variant]);
        final repo = FakeCartRepository(
          initialItems: [
            CartItem(
              id: 'item-1',
              product: product,
              selectedVariant: variant,
              quantity: 2,
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            cartRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(cartProvider.notifier).loadCart();
        final state = container.read(cartProvider);

        expect(state.isLoading, isFalse);
        expect(state.hasError, isFalse);
        expect(state.items.length, equals(1));
        expect(state.totalItemCount, equals(2));
        expect(state.subtotal, equals(300.0));
      },
    );

    // 3. empty cart
    test('3. empty cart state represents genuine empty basket', () async {
      final testUser = createTestUser();
      final repo = FakeCartRepository(initialItems: []);

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      final state = container.read(cartProvider);

      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      expect(state.isEmpty, isTrue);
      expect(state.isEmptyLoaded, isTrue);
      expect(state.totalItemCount, equals(0));
      expect(state.subtotal, equals(0.0));
      expect(state.deliveryFee, equals(0.0));
    });

    // 4. repository error does NOT silently become empty cart
    test(
      '4. repository error captures errorMessage and preserves hasError state',
      () async {
        final testUser = createTestUser();
        final repo = FakeCartRepository(
          shouldThrow: true,
          errorMessage: 'Network timeout to Supabase PostgREST',
        );

        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            cartRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(cartProvider.notifier).loadCart();
        final state = container.read(cartProvider);

        expect(state.isLoading, isFalse);
        expect(state.hasError, isTrue);
        expect(state.errorMessage, isNotNull);
        expect(
          state.errorMessage,
          contains('Network timeout to Supabase PostgREST'),
        );
        expect(state.isLoaded, isFalse);
      },
    );

    // 5. discounted item
    test('5. discounted item correctly calculates product savings and original total', () async {
      final testUser = createTestUser();
      final variant = createVariant(
        id: 'var-disc',
        price: 155.0,
        originalPrice: 180.0,
      );
      final product = createProduct(id: 'prod-disc', variants: [variant]);
      final repo = FakeCartRepository(
        initialItems: [
          CartItem(
            id: 'item-disc',
            product: product,
            selectedVariant: variant,
            quantity: 2,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      final state = container.read(cartProvider);

      expect(variant.hasDiscount, isTrue);
      expect(state.subtotal, equals(310.0));
      expect(state.originalTotal, equals(360.0));
      expect(state.productSavings, equals(50.0));
    });

    // 6. non-discounted item
    test('6. non-discounted item has zero savings and originalTotal equals subtotal', () async {
      final testUser = createTestUser();
      final variant = createVariant(
        id: 'var-nodisc',
        price: 200.0,
        originalPrice: null,
      );
      final product = createProduct(id: 'prod-nodisc', variants: [variant]);
      final repo = FakeCartRepository(
        initialItems: [
          CartItem(
            id: 'item-nodisc',
            product: product,
            selectedVariant: variant,
            quantity: 1,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      final state = container.read(cartProvider);

      expect(variant.hasDiscount, isFalse);
      expect(state.subtotal, equals(200.0));
      expect(state.originalTotal, equals(200.0));
      expect(state.productSavings, equals(0.0));
    });

    // 7. quantity increase
    test(
      '7. quantity increase increments item count and updates subtotal',
      () async {
        final testUser = createTestUser();
        final variant = createVariant(id: 'var-1', price: 100.0);
        final product = createProduct(id: 'prod-1', variants: [variant]);
        final repo = FakeCartRepository(
          initialItems: [
            CartItem(
              id: 'item-1',
              product: product,
              selectedVariant: variant,
              quantity: 1,
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            cartRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(cartProvider.notifier).loadCart();
        final key = '${product.id}_${variant.id}';
        await container.read(cartProvider.notifier).updateQuantity(key, 1);

        final state = container.read(cartProvider);
        expect(state.items[key]?.quantity, equals(2));
        expect(state.subtotal, equals(200.0));
      },
    );

    // 8. quantity decrease
    test('8. quantity decrease decrements item count correctly', () async {
      final testUser = createTestUser();
      final variant = createVariant(id: 'var-1', price: 100.0);
      final product = createProduct(id: 'prod-1', variants: [variant]);
      final repo = FakeCartRepository(
        initialItems: [
          CartItem(
            id: 'item-1',
            product: product,
            selectedVariant: variant,
            quantity: 3,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      final key = '${product.id}_${variant.id}';
      await container.read(cartProvider.notifier).updateQuantity(key, -1);

      final state = container.read(cartProvider);
      expect(state.items[key]?.quantity, equals(2));
      expect(state.subtotal, equals(200.0));
    });

    // 9. remove final item
    test('9. removing final item transitions cart to empty state', () async {
      final testUser = createTestUser();
      final variant = createVariant(id: 'var-1', price: 100.0);
      final product = createProduct(id: 'prod-1', variants: [variant]);
      final repo = FakeCartRepository(
        initialItems: [
          CartItem(
            id: 'item-1',
            product: product,
            selectedVariant: variant,
            quantity: 1,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      final key = '${product.id}_${variant.id}';
      await container.read(cartProvider.notifier).updateQuantity(key, -1);

      final state = container.read(cartProvider);
      expect(state.items, isEmpty);
      expect(state.isEmpty, isTrue);
      expect(state.totalItemCount, equals(0));
    });

    // 10. clear cart
    test('10. clear cart wipes all items and resets totals', () async {
      final testUser = createTestUser();
      final var1 = createVariant(id: 'var-1', price: 100.0);
      final var2 = createVariant(id: 'var-2', price: 200.0);
      final product = createProduct(id: 'prod-1', variants: [var1, var2]);
      final repo = FakeCartRepository(
        initialItems: [
          CartItem(
            id: 'item-1',
            product: product,
            selectedVariant: var1,
            quantity: 1,
          ),
          CartItem(
            id: 'item-2',
            product: product,
            selectedVariant: var2,
            quantity: 2,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cartProvider.notifier).loadCart();
      expect(container.read(cartProvider).items.length, equals(2));

      await container.read(cartProvider.notifier).clearCart();
      final state = container.read(cartProvider);
      expect(state.items, isEmpty);
      expect(state.subtotal, equals(0.0));
      expect(state.totalPayable, equals(0.0));
    });

    // 11. retry after load error
    test(
      '11. retry after load error clears previous error and loads successfully',
      () async {
        final testUser = createTestUser();
        final variant = createVariant(id: 'var-1', price: 180.0);
        final product = createProduct(id: 'prod-1', variants: [variant]);
        final repo = FakeCartRepository(
          initialItems: [
            CartItem(
              id: 'item-1',
              product: product,
              selectedVariant: variant,
              quantity: 1,
            ),
          ],
          shouldThrow: true,
        );

        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWithValue(testUser),
            cartRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);

        // Initial failing load
        await container.read(cartProvider.notifier).loadCart();
        expect(container.read(cartProvider).hasError, isTrue);
        expect(container.read(cartProvider).items, isEmpty);

        // Server recovers, customer retries
        repo.shouldThrow = false;
        await container.read(cartProvider.notifier).loadCart();

        final state = container.read(cartProvider);
        expect(state.hasError, isFalse);
        expect(state.errorMessage, isNull);
        expect(state.items.length, equals(1));
        expect(state.subtotal, equals(180.0));
        expect(repo.getItemsCallCount, equals(2));
      },
    );

    // 12. product with missing image
    test(
      '12. product with missing image uses resilient fallback mainImage',
      () {
        final productWithoutImages = createProduct(
          id: 'prod-noimg',
          name: 'Product with Empty Images List',
          images: [],
        );

        expect(productWithoutImages.images, isEmpty);
        expect(productWithoutImages.mainImage, equals(''));
      },
    );

    // 13. inventory unavailable
    test('13. variant with zero stock or unavailable is properly flagged', () {
      final outOfStockVariant = createVariant(
        id: 'var-zero-stock',
        stock: 0,
        isAvailable: true,
      );
      final inactiveVariant = createVariant(
        id: 'var-inactive',
        stock: 50,
        isAvailable: false,
      );
      final availableVariant = createVariant(
        id: 'var-avail',
        stock: 10,
        isAvailable: true,
      );

      expect(outOfStockVariant.isOutOfStock, isTrue);
      expect(inactiveVariant.isOutOfStock, isTrue);
      expect(availableVariant.isOutOfStock, isFalse);
    });
  });

  group('CartScreen UI States Verification', () {
    testWidgets('Renders professional loading state when cart is loading', (
      tester,
    ) async {
      final testUser = createTestUser();
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CartScreen()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading your fresh cart...'), findsOneWidget);
    });

    testWidgets('Renders professional error state with retry UI on failure', (
      tester,
    ) async {
      final testUser = createTestUser();
      final repo = FakeCartRepository(
        shouldThrow: true,
        errorMessage: 'Network connection failed',
      );
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await container.read(cartProvider.notifier).loadCart();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CartScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could Not Load Cart'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Network connection failed'), findsOneWidget);

      // Verify tapping Retry triggers loadCart
      repo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Your Fresh Cart is Empty'), findsOneWidget);
    });

    testWidgets('Renders genuine empty cart state when loaded with 0 items', (
      tester,
    ) async {
      final testUser = createTestUser();
      final repo = FakeCartRepository(initialItems: []);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(testUser),
          cartRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await container.read(cartProvider.notifier).loadCart();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CartScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your Fresh Cart is Empty'), findsOneWidget);
      expect(find.text('Browse Fresh Meat'), findsOneWidget);
    });
  });
}
