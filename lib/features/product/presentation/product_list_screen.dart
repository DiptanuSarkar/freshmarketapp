import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../catalog/data/catalog_repository.dart';
import 'widgets/product_card.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key, required this.categorySlug});

  final String categorySlug;

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  late String _activeCategorySlug;

  @override
  void initState() {
    super.initState();
    _activeCategorySlug = widget.categorySlug;
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(catalogCategoriesProvider);
    final categories = categoriesAsync.value ?? const [];

    final productsAsync = ref.watch(
      catalogCategoryProductsProvider(_activeCategorySlug),
    );

    String pageTitle = 'All Fresh Products';
    if (_activeCategorySlug != 'all') {
      try {
        final cat = categories.firstWhere((c) => c.slug == _activeCategorySlug);
        pageTitle = cat.name;
      } catch (_) {
        pageTitle = _activeCategorySlug.toUpperCase();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push(AppRoutes.search),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: () => context.push(AppRoutes.cart),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            height: 48,
            color: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg),
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryFilterChip('All Products', 'all'),
                ...categories.map(
                  (c) => _buildCategoryFilterChip(c.name, c.slug),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Product Grid
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(
                child: AppLoadingIndicator(
                  message: 'Loading fresh products...',
                ),
              ),
              error: (err, stack) => AppErrorWidget(
                title: "Couldn't load products",
                message: 'Please check your connection and try again.',
                onRetry: () => ref.refresh(
                  catalogCategoryProductsProvider(_activeCategorySlug),
                ),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return AppEmptyState(
                    title: 'No products in this category',
                    message: 'Fresh stock is sourced and cut daily. Check other categories!',
                    icon: Icons.inventory_2_outlined,
                    actionLabel: 'View All Cuts',
                    onAction: () => setState(() => _activeCategorySlug = 'all'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(
                      catalogCategoryProductsProvider(_activeCategorySlug),
                    );
                    await ref.read(
                      catalogCategoryProductsProvider(_activeCategorySlug)
                          .future,
                    );
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(AppDimensions.lg),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: AppDimensions.md,
                          mainAxisSpacing: AppDimensions.md,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return ProductCard(
                            product: product,
                            width: double.infinity,
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(String label, String slug) {
    final isSelected = _activeCategorySlug == slug;
    return Padding(
      padding: const EdgeInsets.only(right: AppDimensions.sm),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: AppColors.primaryContainer,
        backgroundColor: AppColors.surfaceSubtle,
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent,
          width: 1,
        ),
        onSelected: (_) {
          setState(() => _activeCategorySlug = slug);
        },
      ),
    );
  }
}
