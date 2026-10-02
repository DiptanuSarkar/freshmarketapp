import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../shared/data/mock_data.dart';
import '../../../shared/providers/products_provider.dart';
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
    final products = ref.watch(categoryProductsProvider(_activeCategorySlug));

    String pageTitle = 'All Fresh Products';
    if (_activeCategorySlug != 'all') {
      try {
        final cat = MockData.categories.firstWhere(
          (c) => c.slug == _activeCategorySlug,
        );
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
                ...MockData.categories.map(
                  (c) => _buildCategoryFilterChip(c.name, c.slug),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Product Grid
          Expanded(
            child: products.isEmpty
                ? AppEmptyState(
                    title: 'No products in this category',
                    message: 'We are restocking fresh cuts soon. Check other categories!',
                    icon: Icons.inventory_2_outlined,
                    actionLabel: 'Browse All',
                    onAction: () => setState(() => _activeCategorySlug = 'all'),
                  )
                : LayoutBuilder(
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
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(String label, String slug) {
    final isSelected = _activeCategorySlug == slug;
    return Padding(
      padding: const EdgeInsets.only(right: AppDimensions.sm),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: isSelected,
          selectedColor: AppColors.primaryContainer,
          backgroundColor: AppColors.surfaceSubtle,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          ),
          side: BorderSide(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
          onSelected: (selected) {
            if (selected) {
              setState(() => _activeCategorySlug = slug);
            }
          },
        ),
      ),
    );
  }
}
