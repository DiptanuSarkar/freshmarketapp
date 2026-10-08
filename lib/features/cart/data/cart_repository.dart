import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_variant.dart';

abstract interface class ICartRepository {
  Future<List<CartItem>> getCartItems();
  Future<void> addItem(
    Product product,
    ProductVariant variant, {
    int quantity = 1,
  });
  Future<void> updateQuantity(String variantId, int newQuantity);
  Future<void> removeItem(String variantId);
  Future<void> clearCart();
}

class SupabaseCartRepository implements ICartRepository {
  SupabaseCartRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  Future<String?> _getOrCreateCartId() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    final existing = await _supabase
        .from(SupabaseTables.carts)
        .select('id')
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    final created = await _supabase
        .from(SupabaseTables.carts)
        .insert({'user_id': uid})
        .select('id')
        .single();

    return created['id'] as String;
  }

  @override
  Future<List<CartItem>> getCartItems() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final cartId = await _getOrCreateCartId();
      if (cartId == null) return [];

      final response = await _supabase
          .from(SupabaseTables.cartItems)
          .select('''
            id,
            cart_id,
            variant_id,
            quantity,
            product_variants:variant_id (
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
            )
          ''')
          .eq('cart_id', cartId)
          .order('created_at', ascending: true);

      final List<dynamic> list = response;
      final result = <CartItem>[];

      for (final raw in list) {
        final itemMap = raw as Map<String, dynamic>;
        final variantMap = itemMap['product_variants'] as Map<String, dynamic>?;
        if (variantMap == null) continue;

        final productMap = variantMap['products'] as Map<String, dynamic>?;
        if (productMap == null) continue;

        final isProductActive = productMap['is_active'] as bool? ?? true;

        // Inventory & stock
        int stock = 0;
        if (variantMap['inventory'] != null) {
          if (variantMap['inventory'] is List &&
              (variantMap['inventory'] as List).isNotEmpty) {
            final inv =
                (variantMap['inventory'] as List).first as Map<String, dynamic>;
            stock =
                (inv['quantity_available'] as int? ?? 0) -
                (inv['reserved_quantity'] as int? ?? 0);
          } else if (variantMap['inventory'] is Map) {
            final inv = variantMap['inventory'] as Map<String, dynamic>;
            stock =
                (inv['quantity_available'] as int? ?? 0) -
                (inv['reserved_quantity'] as int? ?? 0);
          }
        }
        if (stock < 0) stock = 0;

        final isVariantActive = variantMap['is_active'] as bool? ?? true;
        final isAvailable = isVariantActive && isProductActive && stock > 0;

        final price = (variantMap['price'] as num).toDouble();
        final discountedPrice = (variantMap['discounted_price'] as num?)
            ?.toDouble();
        final sellingPrice = discountedPrice ?? price;
        final originalPrice = discountedPrice != null ? price : null;

        // Weight parsing
        double weightInGrams = 500;
        final weightStr = (variantMap['weight'] as String? ?? '').toLowerCase();
        if (weightStr.contains('kg')) {
          final numVal =
              double.tryParse(weightStr.replaceAll('kg', '').trim()) ?? 1.0;
          weightInGrams = numVal * 1000;
        } else if (weightStr.contains('g')) {
          weightInGrams =
              double.tryParse(weightStr.replaceAll('g', '').trim()) ?? 500;
        }

        final gross = variantMap['gross_weight'] as String?;
        final net = variantMap['net_weight'] as String?;
        String? netWeightDisplay;
        if (gross != null && net != null) {
          netWeightDisplay = 'Net wt: $net | Gross: $gross';
        } else if (net != null) {
          netWeightDisplay = 'Net wt: $net';
        }

        final variant = ProductVariant(
          id: variantMap['id'] as String,
          sku: variantMap['sku'] as String? ?? 'SKU-${variantMap['id']}',
          title: variantMap['name'] as String? ?? 'Standard',
          weightInGrams: weightInGrams,
          price: sellingPrice,
          originalPrice: originalPrice,
          stockQuantity: stock,
          isAvailable: isAvailable,
          netWeightDisplay: netWeightDisplay,
        );

        // Images
        final imagesList = <String>[];
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
            if (url != null && url.isNotEmpty) imagesList.add(url);
          }
        }

        String catSlug = '';
        if (productMap['categories'] != null &&
            productMap['categories'] is Map) {
          catSlug = productMap['categories']['slug'] as String? ?? '';
        }

        final product = Product(
          id: productMap['id'] as String,
          name: productMap['name'] as String,
          categorySlug: catSlug,
          shortDescription: productMap['short_description'] as String? ?? '',
          description: productMap['description'] as String? ?? '',
          images: imagesList.isNotEmpty
              ? imagesList
              : [
                  'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80',
                ],
          variants: [variant],
        );

        result.add(
          CartItem(
            id: itemMap['id'] as String,
            product: product,
            selectedVariant: variant,
            quantity: itemMap['quantity'] as int? ?? 1,
          ),
        );
      }

      return result;
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> addItem(
    Product product,
    ProductVariant variant, {
    int quantity = 1,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Please sign in to add items to your cart.');
    }

    try {
      final cartId = await _getOrCreateCartId();
      if (cartId == null) {
        throw const AppException('Could not initialize shopping cart.');
      }

      // Check if item already exists in cart
      final existing = await _supabase
          .from(SupabaseTables.cartItems)
          .select('id, quantity')
          .eq('cart_id', cartId)
          .eq('variant_id', variant.id)
          .maybeSingle();

      if (existing != null) {
        final currentQty = existing['quantity'] as int? ?? 0;
        final newQty = currentQty + quantity;
        await _supabase
            .from(SupabaseTables.cartItems)
            .update({
              'quantity': newQty,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existing['id'] as String);
      } else {
        await _supabase.from(SupabaseTables.cartItems).insert({
          'cart_id': cartId,
          'variant_id': variant.id,
          'quantity': quantity,
        });
      }
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> updateQuantity(String variantId, int newQuantity) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final cartId = await _getOrCreateCartId();
      if (cartId == null) return;

      if (newQuantity <= 0) {
        await _supabase
            .from(SupabaseTables.cartItems)
            .delete()
            .eq('cart_id', cartId)
            .eq('variant_id', variantId);
      } else {
        await _supabase
            .from(SupabaseTables.cartItems)
            .update({
              'quantity': newQuantity,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('cart_id', cartId)
            .eq('variant_id', variantId);
      }
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> removeItem(String variantId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final cartId = await _getOrCreateCartId();
      if (cartId == null) return;

      await _supabase
          .from(SupabaseTables.cartItems)
          .delete()
          .eq('cart_id', cartId)
          .eq('variant_id', variantId);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> clearCart() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final cartId = await _getOrCreateCartId();
      if (cartId == null) return;

      await _supabase
          .from(SupabaseTables.cartItems)
          .delete()
          .eq('cart_id', cartId);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final cartRepositoryProvider = Provider<ICartRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseCartRepository(supabaseClient: supabase);
});
