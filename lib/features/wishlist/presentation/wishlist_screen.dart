import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../shared/providers/products_provider.dart';
import '../../../shared/providers/wishlist_provider.dart';
import '../../product/presentation/widgets/product_card.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIds = ref.watch(wishlistProvider);
    final allProducts = ref.watch(allProductsProvider);
    final favProducts = allProducts
        .where((p) => favIds.contains(p.id))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('My Wishlist (${favProducts.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: () => context.push(AppRoutes.cart),
          ),
        ],
      ),
      body: favProducts.isEmpty
          ? AppEmptyState(
              title: 'Your Wishlist is Empty',
              message: 'Save your favorite chicken cuts, fresh fish, or spices for rapid 1-click re-ordering.',
              icon: Icons.favorite_border_rounded,
              actionLabel: 'Explore Cuts',
              onAction: () => context.go(AppRoutes.home),
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
                  itemCount: favProducts.length,
                  itemBuilder: (context, index) {
                    final product = favProducts[index];
                    return ProductCard(
                      product: product,
                      width: double.infinity,
                    );
                  },
                );
              },
            ),
    );
  }
}
