import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_review.dart';
import '../../../shared/models/product_variant.dart';

abstract interface class ICatalogRepository {
  Future<List<Category>> getCategories();
  Future<List<Product>> getProducts({
    String? categorySlug,
    String? categoryId,
    bool? onlyDeals,
    bool? onlyPopular,
  });
  Future<Product?> getProductById(String id);
  Future<List<Product>> searchProducts(String query);
  Future<List<ProductReview>> getProductReviews(String productId);
  Future<List<Product>> getActiveProducts({String? categorySlug});
}

class SupabaseCatalogRepository implements ICatalogRepository {
  SupabaseCatalogRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  static const String _productSelectQuery = '''
    id,
    category_id,
    name,
    slug,
    short_description,
    description,
    storage_instructions,
    cooking_suggestions,
    is_halal,
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
    ),
    product_variants (
      id,
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
      )
    )
  ''';

  @override
  Future<List<Category>> getCategories() async {
    try {
      final response = await _supabase
          .from(SupabaseTables.categories)
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final List<dynamic> list = response;
      return list
          .map((item) => Category.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<List<Product>> getProducts({
    String? categorySlug,
    String? categoryId,
    bool? onlyDeals,
    bool? onlyPopular,
  }) async {
    try {
      var query = _supabase
          .from(SupabaseTables.products)
          .select(_productSelectQuery)
          .eq('is_active', true);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }

      final response = await query;
      final List<dynamic> list = response;
      var products = list
          .map((item) => _mapProduct(item as Map<String, dynamic>))
          .toList();

      if (categorySlug != null &&
          categorySlug != 'all' &&
          categorySlug.isNotEmpty) {
        products = products
            .where((p) => p.categorySlug == categorySlug)
            .toList();
      }

      if (onlyDeals == true) {
        products = products.where((p) => p.isDailyDeal).toList();
      }

      if (onlyPopular == true) {
        products = products.where((p) => p.isPopular).toList();
      }

      return products;
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<Product?> getProductById(String id) async {
    try {
      final response = await _supabase
          .from(SupabaseTables.products)
          .select(_productSelectQuery)
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return _mapProduct(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final response = await _supabase
          .from(SupabaseTables.products)
          .select(_productSelectQuery)
          .eq('is_active', true)
          .ilike('name', '%$trimmed%')
          .limit(25);

      final List<dynamic> list = response;
      return list
          .map((item) => _mapProduct(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<List<ProductReview>> getProductReviews(String productId) async {
    try {
      final response = await _supabase
          .from(SupabaseTables.productReviews)
          .select('''
            id,
            product_id,
            user_id,
            rating,
            review_text,
            is_verified_purchase,
            created_at,
            profiles:user_id (
              full_name
            )
          ''')
          .eq('product_id', productId)
          .eq('is_approved', true)
          .order('created_at', ascending: false);

      final List<dynamic> list = response;
      return list
          .map((item) => ProductReview.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  Product _mapProduct(Map<String, dynamic> json) {
    final isProductActive = json['is_active'] as bool? ?? true;

    // Category slug
    String catSlug = '';
    if (json['categories'] != null && json['categories'] is Map) {
      catSlug = json['categories']['slug'] as String? ?? '';
    }

    // Images sorted by display_order
    final imagesList = <String>[];
    if (json['product_images'] != null && json['product_images'] is List) {
      final rawImgs = List<Map<String, dynamic>>.from(
        json['product_images'] as List,
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

    // Variants sorted: is_default first
    final variantsList = <ProductVariant>[];
    if (json['product_variants'] != null && json['product_variants'] is List) {
      final rawVariants = List<Map<String, dynamic>>.from(
        json['product_variants'] as List,
      );
      rawVariants.sort((a, b) {
        final aDef = a['is_default'] as bool? ?? false;
        final bDef = b['is_default'] as bool? ?? false;
        if (aDef && !bDef) return -1;
        if (!aDef && bDef) return 1;
        return 0;
      });
      for (final v in rawVariants) {
        variantsList.add(_mapVariant(v, isProductActive));
      }
    }

    String pieces = '8-12 Pieces';
    String servings = 'Serves 2-3';
    if (variantsList.isNotEmpty) {
      final firstRaw =
          (json['product_variants'] as List).first as Map<String, dynamic>;
      if (firstRaw['pieces_count'] != null) {
        pieces = firstRaw['pieces_count'] as String;
      }
      if (firstRaw['serves'] != null) {
        servings = firstRaw['serves'] as String;
      }
    }

    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categorySlug: catSlug,
      shortDescription: json['short_description'] as String? ?? '',
      description: json['description'] as String? ?? '',
      images: imagesList.isNotEmpty
          ? imagesList
          : [
              'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80',
            ],
      variants: variantsList,
      storageInstructions: json['storage_instructions'] as String?,
      cookingSuggestions: json['cooking_suggestions'] as String?,
      isFeatured: true,
      isDailyDeal: true,
      isPopular: true,
      rating: 4.8,
      reviewCount: 32,
      pieces: pieces,
      servings: servings,
    );
  }

  ProductVariant _mapVariant(Map<String, dynamic> json, bool isProductActive) {
    final price = (json['price'] as num).toDouble();
    final discountedPrice = (json['discounted_price'] as num?)?.toDouble();

    // Selling price: discounted_price ?? price
    final sellingPrice = discountedPrice ?? price;

    // Original price: price when discounted_price != null, otherwise null
    final originalPrice = discountedPrice != null ? price : null;

    // Stock calculation: quantity_available - reserved_quantity
    int stock = 0;
    if (json['inventory'] != null) {
      if (json['inventory'] is List && (json['inventory'] as List).isNotEmpty) {
        final inv = (json['inventory'] as List).first as Map<String, dynamic>;
        final qtyAvail = inv['quantity_available'] as int? ?? 0;
        final reserved = inv['reserved_quantity'] as int? ?? 0;
        stock = qtyAvail - reserved;
      } else if (json['inventory'] is Map) {
        final inv = json['inventory'] as Map<String, dynamic>;
        final qtyAvail = inv['quantity_available'] as int? ?? 0;
        final reserved = inv['reserved_quantity'] as int? ?? 0;
        stock = qtyAvail - reserved;
      }
    }
    if (stock < 0) stock = 0;

    final isVariantActive = json['is_active'] as bool? ?? true;
    final available = isVariantActive && isProductActive && stock > 0;

    final gross = json['gross_weight'] as String?;
    final net = json['net_weight'] as String?;
    String? netWeightDisplay;
    if (gross != null && net != null) {
      netWeightDisplay = 'Net wt: $net | Gross: $gross';
    } else if (net != null) {
      netWeightDisplay = 'Net wt: $net';
    }

    double weightInGrams = 500;
    final weightStr = (json['weight'] as String? ?? '').toLowerCase();
    if (weightStr.contains('kg')) {
      final numVal =
          double.tryParse(weightStr.replaceAll('kg', '').trim()) ?? 1.0;
      weightInGrams = numVal * 1000;
    } else if (weightStr.contains('g')) {
      weightInGrams =
          double.tryParse(weightStr.replaceAll('g', '').trim()) ?? 500;
    }

    final pieces = json['pieces_count']?.toString();
    final serves = json['serves']?.toString();

    return ProductVariant(
      id: json['id'] as String,
      sku: json['sku'] as String? ?? 'SKU-${json['id']}',
      title: json['name'] as String? ?? 'Standard',
      weightInGrams: weightInGrams,
      price: sellingPrice,
      originalPrice: originalPrice,
      stockQuantity: stock,
      isAvailable: available,
      netWeightDisplay: netWeightDisplay,
      grossWeightDisplay: gross != null ? 'Gross wt: $gross' : null,
      piecesCount: pieces != null ? '$pieces Pieces' : null,
      serves: serves != null ? 'Serves $serves' : null,
    );
  }

  @override
  Future<List<Product>> getActiveProducts({String? categorySlug}) {
    return getProducts(categorySlug: categorySlug);
  }
}

final catalogRepositoryProvider = Provider<ICatalogRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseCatalogRepository(supabaseClient: supabase);
});

final catalogCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.getCategories();
});

final categoriesProvider = catalogCategoriesProvider;

final catalogProductsProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.getActiveProducts();
});

final catalogCategoryProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, categorySlug) async {
      final repo = ref.watch(catalogRepositoryProvider);
      return repo.getActiveProducts(categorySlug: categorySlug);
    });

final catalogProductByIdProvider = FutureProvider.family<Product?, String>((
  ref,
  productId,
) async {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.getProductById(productId);
});
