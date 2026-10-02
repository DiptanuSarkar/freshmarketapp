import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/badges/status_badge.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_variant.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/providers/products_provider.dart';
import '../../../shared/providers/wishlist_provider.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _selectedImageIndex = 0;
  ProductVariant? _selectedVariant;
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productByIdProvider(widget.productId));

    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product Details')),
        body: AppErrorWidget(
          title: 'Product not found',
          message: 'The requested product could not be located in our catalog.',
          retryLabel: 'Go to Catalog',
          onRetry: () => context.go(AppRoutes.categories),
        ),
      );
    }

    _selectedVariant ??= product.defaultVariant;
    final isFav = ref.watch(wishlistProvider).contains(product.id);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppColors.accent : AppColors.textPrimary,
            ),
            onPressed: () =>
                ref.read(wishlistProvider.notifier).toggle(product.id),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: () => context.push(AppRoutes.cart),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Gallery & Carousel Area
                  _buildImageGallery(product),

                  // Content Container
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(AppDimensions.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category & Rating Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              product.categorySlug.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: AppColors.warningContainer,
                                borderRadius: AppDimensions.roundedPill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: AppColors.warning,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${product.rating} (${product.reviewCount})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.xs),

                        // Title
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: AppDimensions.xs),

                        // Short description
                        Text(
                          product.shortDescription,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppDimensions.md),

                        // Price & Discount Row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${AppStrings.currencySymbol}${_selectedVariant!.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (_selectedVariant!.hasDiscount) ...[
                              const SizedBox(width: AppDimensions.sm),
                              Text(
                                '${AppStrings.currencySymbol}${_selectedVariant!.originalPrice!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  decoration: TextDecoration.lineThrough,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: AppDimensions.sm),
                              StatusBadge(
                                label:
                                    '${_selectedVariant!.discountPercentage}% OFF',
                                variant: BadgeVariant.accent,
                              ),
                            ],
                            const Spacer(),
                            StatusBadge(
                              label: _selectedVariant!.isOutOfStock
                                  ? 'Out of Stock'
                                  : 'In Stock',
                              variant: _selectedVariant!.isOutOfStock
                                  ? BadgeVariant.error
                                  : BadgeVariant.success,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // Variant Selection Area
                  Container(
                    width: double.infinity,
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(AppDimensions.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Weight / Variant',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.md),
                        Wrap(
                          spacing: AppDimensions.sm,
                          runSpacing: AppDimensions.sm,
                          children: product.variants.map((v) {
                            final isSelected = v.id == _selectedVariant!.id;
                            return ChoiceChip(
                              label: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.title),
                                  Text(
                                    '${AppStrings.currencySymbol}${v.price.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppColors.primaryDark
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primaryContainer,
                              backgroundColor: AppColors.surfaceSubtle,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.surfaceBorder,
                                width: 1.5,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedVariant = v);
                                }
                              },
                            );
                          }).toList(),
                        ),
                        if (_selectedVariant?.netWeightDisplay != null) ...[
                          const SizedBox(height: AppDimensions.sm),
                          Text(
                            _selectedVariant!.netWeightDisplay!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // Highlights / Cuts Info
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(AppDimensions.lg),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildHighlightItem(
                          Icons.pie_chart_outline_rounded,
                          product.pieces,
                          'Pieces',
                        ),
                        _buildHighlightItem(
                          Icons.groups_outlined,
                          product.servings,
                          'Portion',
                        ),
                        _buildHighlightItem(
                          Icons.ac_unit_rounded,
                          '0-4° C',
                          'Chilled Fresh',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),

                  // Detailed Description
                  Container(
                    width: double.infinity,
                    color: AppColors.surface,
                    padding: const EdgeInsets.all(AppDimensions.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Product Details & Source',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.sm),
                        Text(
                          product.description,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xxxl),
                ],
              ),
            ),
          ),

          // Bottom Action Bar (Quantity controls + Add to Cart + Buy Now)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.lg,
              vertical: AppDimensions.md,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.surfaceBorder, width: 1),
              ),
              boxShadow: AppDimensions.cardShadow,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Quantity Stepper
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: AppDimensions.roundedMd,
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 16),
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                        ),
                        Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          onPressed: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimensions.md),

                  // Add to Cart Button
                  Expanded(
                    child: AppButton(
                      label: AppStrings.addToCart,
                      variant: AppButtonVariant.outline,
                      height: 44,
                      onPressed: _selectedVariant!.isOutOfStock
                          ? null
                          : () {
                              cartNotifier.addItem(
                                product,
                                _selectedVariant!,
                                qty: _quantity,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Added $_quantity x ${product.name} to cart',
                                  ),
                                  backgroundColor: AppColors.primary,
                                  duration: const Duration(seconds: 2),
                                  action: SnackBarAction(
                                    label: 'View Cart',
                                    textColor: Colors.white,
                                    onPressed: () =>
                                        context.push(AppRoutes.cart),
                                  ),
                                ),
                              );
                            },
                    ),
                  ),
                  const SizedBox(width: AppDimensions.sm),

                  // Buy Now Button
                  Expanded(
                    child: AppButton(
                      label: AppStrings.buyNow,
                      variant: AppButtonVariant.primary,
                      height: 44,
                      onPressed: _selectedVariant!.isOutOfStock
                          ? null
                          : () {
                              cartNotifier.addItem(
                                product,
                                _selectedVariant!,
                                qty: _quantity,
                              );
                              context.push(AppRoutes.cart);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery(Product product) {
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            itemCount: product.images.length,
            onPageChanged: (idx) => setState(() => _selectedImageIndex = idx),
            itemBuilder: (context, index) {
              return CachedNetworkImage(
                imageUrl: product.images[index],
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: AppColors.surfaceSubtle),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceSubtle,
                  child: const Center(
                    child: Icon(
                      Icons.image,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (product.images.length > 1) ...[
          const SizedBox(height: AppDimensions.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(product.images.length, (idx) {
              final isCurrent = idx == _selectedImageIndex;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isCurrent ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.primary
                      : AppColors.surfaceBorder,
                  borderRadius: AppDimensions.roundedPill,
                ),
              );
            }),
          ),
          const SizedBox(height: AppDimensions.sm),
        ],
      ],
    );
  }

  Widget _buildHighlightItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
