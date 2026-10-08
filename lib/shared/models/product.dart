import 'product_variant.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.categorySlug,
    required this.shortDescription,
    required this.description,
    required this.images,
    required this.variants,
    this.storageInstructions,
    this.cookingSuggestions,
    this.isFeatured = false,
    this.isDailyDeal = false,
    this.isPopular = false,
    this.rating = 4.8,
    this.reviewCount = 120,
    this.pieces = '8-12 Pieces',
    this.servings = 'Serves 2-3',
  });

  final String id;
  final String name;
  final String categorySlug;
  final String shortDescription;
  final String description;
  final List<String> images;
  final List<ProductVariant> variants;
  final String? storageInstructions;
  final String? cookingSuggestions;
  final bool isFeatured;
  final bool isDailyDeal;
  final bool isPopular;
  final double rating;
  final int reviewCount;
  final String pieces;
  final String servings;

  String get mainImage => images.isNotEmpty ? images.first : '';

  bool get isVariableProduct => variants.length > 1;

  ProductVariant get defaultVariant {
    if (variants.isEmpty) {
      return const ProductVariant(
        id: 'fallback',
        sku: 'DEFAULT',
        title: 'Standard',
        weightInGrams: 500,
        price: 0,
      );
    }
    // Return first in-stock variant or simply first variant
    return variants.firstWhere(
      (v) => !v.isOutOfStock,
      orElse: () => variants.first,
    );
  }

  double get startingPrice => defaultVariant.price;
}
