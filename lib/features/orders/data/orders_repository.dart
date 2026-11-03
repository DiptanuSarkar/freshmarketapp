import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_variant.dart';
import '../../cart/data/cart_repository.dart';

class RepeatOrderResult {
  const RepeatOrderResult({
    required this.addedCount,
    required this.unavailableCount,
    required this.unavailableItems,
  });

  final int addedCount;
  final int unavailableCount;
  final List<String> unavailableItems;

  bool get hasItemsAdded => addedCount > 0;
  bool get hasUnavailable => unavailableCount > 0;
  String get summaryMessage {
    if (addedCount == 0 && unavailableCount > 0) {
      return 'None of the items from this order are currently available in the active butchery catalog.';
    }
    final buffer = StringBuffer('Added $addedCount item(s) to your cart.');
    if (unavailableCount > 0) {
      buffer.write(' Unavailable: ${unavailableItems.join(', ')}');
    }
    return buffer.toString();
  }
}

abstract class IOrdersRepository {
  Future<List<CustomerOrder>> getOrders();
  Future<CustomerOrder?> getOrderById(String orderId);
  Future<RepeatOrderResult> repeatOrder(CustomerOrder order);
}

class SupabaseOrdersRepository implements IOrdersRepository {
  SupabaseOrdersRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<CustomerOrder>> getOrders() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from(SupabaseTables.orders)
          .select('''
            *,
            order_items (
              *,
              variant:product_variants (
                product_id,
                products (
                  product_images (
                    image_url,
                    display_order
                  )
                )
              )
            ),
            order_status_history (*),
            payments (*),
            refunds (*, refund_components (*))
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = data as List<dynamic>;
      return list
          .map((json) => CustomerOrder.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<CustomerOrder?> getOrderById(String orderId) async {
    try {
      final data = await _supabase
          .from(SupabaseTables.orders)
          .select('''
            *,
            order_items (
              *,
              variant:product_variants (
                product_id,
                products (
                  product_images (
                    image_url,
                    display_order
                  )
                )
              )
            ),
            order_status_history (*),
            payments (*),
            refunds (*, refund_components (*))
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (data == null) return null;
      return CustomerOrder.fromJson(data);
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<RepeatOrderResult> repeatOrder(CustomerOrder order) async {
    int addedCount = 0;
    int unavailableCount = 0;
    final List<String> unavailableItems = [];

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Please sign in to reorder items.');
    }

    final cartRepo = SupabaseCartRepository(supabaseClient: _supabase);
    final currentCart = await cartRepo.getCartItems();
    final currentCartQtyByVariant = <String, int>{};
    for (final ci in currentCart) {
      currentCartQtyByVariant[ci.selectedVariant.id] = ci.quantity;
    }

    for (final item in order.items) {
      try {
        final variantData = await _supabase
            .from(SupabaseTables.productVariants)
            .select('''
              id,
              product_id,
              sku,
              name,
              weight,
              price,
              discounted_price,
              gross_weight,
              net_weight,
              pieces_count,
              serves,
              is_default,
              is_active,
              inventory (
                quantity_available,
                reserved_quantity
              ),
              products:product_id (
                id,
                category_id,
                name,
                slug,
                short_description,
                description,
                is_active,
                categories:category_id (
                  id,
                  slug,
                  name
                ),
                product_images (
                  id,
                  image_url,
                  display_order,
                  is_primary
                )
              )
            ''')
            .eq('id', item.variantId)
            .maybeSingle();

        if (variantData == null) {
          unavailableCount++;
          unavailableItems.add('${item.productName} (${item.variantTitle})');
          continue;
        }

        final isVariantActive = variantData['is_active'] as bool? ?? false;
        final productMap = variantData['products'] as Map<String, dynamic>?;
        final isProductActive = productMap?['is_active'] as bool? ?? false;

        if (!isVariantActive || !isProductActive || productMap == null) {
          unavailableCount++;
          unavailableItems.add('${item.productName} (${item.variantTitle})');
          continue;
        }

        // Live Inventory Check
        final invList = variantData['inventory'] as List<dynamic>?;
        int qtyAvailable = 0;
        int reserved = 0;
        if (invList != null && invList.isNotEmpty) {
          qtyAvailable = invList.first['quantity_available'] as int? ?? 0;
          reserved = invList.first['reserved_quantity'] as int? ?? 0;
        }
        final effectiveStock = (qtyAvailable - reserved).clamp(0, 999999);

        final existingInCart = currentCartQtyByVariant[item.variantId] ?? 0;
        final remainingStock = effectiveStock - existingInCart;

        if (remainingStock <= 0) {
          unavailableCount++;
          unavailableItems.add('${item.productName} (Out of Stock)');
          continue;
        }

        final qtyToAdd = item.quantity.clamp(1, remainingStock);

        // Images for live product
        final images = <String>[];
        if (productMap['product_images'] != null &&
            productMap['product_images'] is List) {
          final rawImgs = List<Map<String, dynamic>>.from(
            productMap['product_images'] as List,
          );
          rawImgs.sort(
            (a, b) => (a['display_order'] as int? ?? 0).compareTo(
              b['display_order'] as int? ?? 0,
            ),
          );
          for (final img in rawImgs) {
            final url = img['image_url'] as String?;
            if (url != null && url.isNotEmpty) images.add(url);
          }
        }

        final categorySlug =
            productMap['categories']?['slug'] as String? ?? 'cuts';

        // Current price from catalog (never old historical price)
        final sellingPrice =
            (variantData['discounted_price'] as num?)?.toDouble() ??
            (variantData['price'] as num?)?.toDouble() ??
            0.0;
        final originalPrice = (variantData['price'] as num?)?.toDouble();

        final liveVariant = ProductVariant(
          id: variantData['id'] as String,
          sku: variantData['sku'] as String? ?? 'SKU-${variantData['id']}',
          title: variantData['name'] as String? ?? 'Standard',
          weightInGrams: (variantData['weight'] as num?)?.toDouble() ?? 500.0,
          price: sellingPrice,
          originalPrice: (originalPrice != null && originalPrice > sellingPrice)
              ? originalPrice
              : null,
          stockQuantity: effectiveStock,
          isAvailable: effectiveStock > 0,
          netWeightDisplay: variantData['net_weight'] != null
              ? 'Net wt: ${variantData['net_weight']}'
              : null,
          grossWeightDisplay: variantData['gross_weight'] != null
              ? 'Gross wt: ${variantData['gross_weight']}'
              : null,
          piecesCount: variantData['pieces_count'] != null
              ? '${variantData['pieces_count']} Pieces'
              : null,
          serves: variantData['serves'] != null
              ? 'Serves ${variantData['serves']}'
              : null,
        );

        final liveProduct = Product(
          id: productMap['id'] as String,
          name: productMap['name'] as String? ?? item.productName,
          categorySlug: categorySlug,
          shortDescription: productMap['short_description'] as String? ?? '',
          description: productMap['description'] as String? ?? '',
          images: images,
          variants: [liveVariant],
        );

        await cartRepo.addItem(liveProduct, liveVariant, quantity: qtyToAdd);
        addedCount += qtyToAdd;
        currentCartQtyByVariant[item.variantId] = existingInCart + qtyToAdd;

        if (qtyToAdd < item.quantity) {
          unavailableItems.add(
            '${item.productName} (Partially added: $qtyToAdd/${item.quantity})',
          );
        }
      } catch (e) {
        unavailableCount++;
        unavailableItems.add(item.productName);
      }
    }

    return RepeatOrderResult(
      addedCount: addedCount,
      unavailableCount: unavailableCount,
      unavailableItems: unavailableItems,
    );
  }
}

final ordersRepositoryProvider = Provider<IOrdersRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseOrdersRepository(supabase);
});

final customerOrdersProvider = FutureProvider<List<CustomerOrder>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(ordersRepositoryProvider);
  return repo.getOrders();
});

final orderDetailProvider = FutureProvider.family<CustomerOrder?, String>((
  ref,
  id,
) async {
  final repo = ref.watch(ordersRepositoryProvider);
  return repo.getOrderById(id);
});
