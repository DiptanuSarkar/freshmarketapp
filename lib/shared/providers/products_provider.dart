import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_data.dart';
import '../models/product.dart';

final allProductsProvider = Provider<List<Product>>((ref) {
  return MockData.products;
});

final dealsProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(allProductsProvider);
  return products.where((p) => p.isDailyDeal).toList();
});

final popularProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(allProductsProvider);
  return products.where((p) => p.isPopular).toList();
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final searchResultsProvider = Provider<List<Product>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final products = ref.watch(allProductsProvider);
  if (query.isEmpty) return products;
  return products.where((p) {
    return p.name.toLowerCase().contains(query) ||
        p.categorySlug.toLowerCase().contains(query) ||
        p.shortDescription.toLowerCase().contains(query);
  }).toList();
});

final categoryProductsProvider = Provider.family<List<Product>, String>((
  ref,
  categorySlug,
) {
  final products = ref.watch(allProductsProvider);
  if (categorySlug == 'all') return products;
  return products.where((p) => p.categorySlug == categorySlug).toList();
});

final productByIdProvider = Provider.family<Product?, String>((ref, productId) {
  final products = ref.watch(allProductsProvider);
  try {
    return products.firstWhere((p) => p.id == productId);
  } catch (_) {
    return null;
  }
});
