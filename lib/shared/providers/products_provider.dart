import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/catalog/data/catalog_repository.dart';
import '../models/product.dart';

final allProductsProvider = Provider<List<Product>>((ref) {
  final asyncVal = ref.watch(catalogProductsProvider);
  return asyncVal.value ?? const [];
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

class DebouncedSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

final debouncedSearchQueryProvider =
    NotifierProvider<DebouncedSearchQueryNotifier, String>(
      DebouncedSearchQueryNotifier.new,
    );

final searchResultsFutureProvider = FutureProvider<List<Product>>((ref) async {
  final query = ref.watch(debouncedSearchQueryProvider).trim();
  if (query.isEmpty) {
    return ref.watch(allProductsProvider);
  }
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.searchProducts(query);
});

final searchResultsProvider = Provider<List<Product>>((ref) {
  final asyncResults = ref.watch(searchResultsFutureProvider);
  return asyncResults.value ?? const [];
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
