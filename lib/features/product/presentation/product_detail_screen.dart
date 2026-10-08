import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_variant.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/providers/wishlist_provider.dart';
import '../../catalog/data/catalog_repository.dart';

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

  void _showLoginRequired(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign In Required'),
        content: const Text(
          'Please sign in or create an account to save favorite cuts and add items to your cart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push(AppRoutes.login);
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(
      catalogProductByIdProvider(widget.productId),
    );

    return productAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Fresh Cut')),
        body: const Center(
          child: AppLoadingIndicator(
            message: 'Loading fresh product details...',
          ),
        ),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: const Text('Product Details')),
        body: AppErrorWidget(
          title: "Couldn't load product",
          message: 'Please check your connection and try again.',
          onRetry: () =>
              ref.refresh(catalogProductByIdProvider(widget.productId)),
        ),
      ),
      data: (product) {
        if (product == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Product Details')),
            body: AppErrorWidget(
              title: 'Product not found',
              message:
                  'The requested product could not be located in our catalog.',
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
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFav ? AppColors.accent : AppColors.textPrimary,
                ),
                onPressed: () async {
                  final ok = await ref
                      .read(wishlistProvider.notifier)
                      .toggle(product.id);
                  if (!ok && context.mounted) {
                    _showLoginRequired(context);
                  }
                },
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
                                        product.rating.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                      Text(
                                        ' (${product.reviewCount})',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.xs),

                            // Product Name
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.xs),

                            // Short description
                            Text(
                              product.shortDescription,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.md),

                            // Price Container
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '${AppStrings.currencySymbol}${_selectedVariant!.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (_selectedVariant!.hasDiscount) ...[
                                  const SizedBox(width: AppDimensions.sm),
                                  Text(
                                    '${AppStrings.currencySymbol}${_selectedVariant!.originalPrice!.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      decoration: TextDecoration.lineThrough,
                                      color: AppColors.textTertiary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: AppDimensions.sm),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentContainer,
                                      borderRadius: AppDimensions.roundedPill,
                                    ),
                                    child: Text(
                                      '${_selectedVariant!.discountPercentage}% OFF',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppDimensions.sm),

                            // Stock status
                            Row(
                              children: [
                                Icon(
                                  _selectedVariant!.isOutOfStock
                                      ? Icons.cancel_outlined
                                      : Icons.check_circle_outline_rounded,
                                  size: 14,
                                  color: _selectedVariant!.isOutOfStock
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedVariant!.isOutOfStock
                                      ? 'Out of Stock'
                                      : 'Fresh Stock Available (${_selectedVariant!.stock} in butchery)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _selectedVariant!.isOutOfStock
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Variant Selector Section
                      Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.all(AppDimensions.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Portion Size & Cut',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        v.title,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: isSelected
                                              ? AppColors.primaryDark
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '${AppStrings.currencySymbol}${v.price.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? AppColors.primary
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
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setState(() => _selectedVariant = v);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Butchery & Product Highlights
                      Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.all(AppDimensions.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Butchery Specification',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                if (_selectedVariant!.netWeightDisplay != null)
                                  _buildHighlightItem(
                                    Icons.scale_outlined,
                                    _selectedVariant!.netWeightDisplay!,
                                    'Net Weight',
                                  ),
                                if (_selectedVariant!.grossWeightDisplay !=
                                    null)
                                  _buildHighlightItem(
                                    Icons.kitchen_outlined,
                                    _selectedVariant!.grossWeightDisplay!,
                                    'Gross Weight',
                                  ),
                                if (_selectedVariant!.piecesCount != null)
                                  _buildHighlightItem(
                                    Icons.grid_view_rounded,
                                    _selectedVariant!.piecesCount!,
                                    'Portions',
                                  ),
                                if (_selectedVariant!.serves != null)
                                  _buildHighlightItem(
                                    Icons.people_outline_rounded,
                                    _selectedVariant!.serves!,
                                    'Serves',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Description & Butchery Process
                      if (product.description.isNotEmpty)
                        Container(
                          color: AppColors.surface,
                          padding: const EdgeInsets.all(AppDimensions.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'About this Cut',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppDimensions.sm),
                              Text(
                                product.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppDimensions.md),

                      // Storage & Freshness Instructions
                      if (product.storageInstructions != null)
                        Container(
                          color: AppColors.surface,
                          padding: const EdgeInsets.all(AppDimensions.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.ac_unit_rounded,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Cold-Chain & Storage Instructions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppDimensions.sm),
                              Text(
                                product.storageInstructions!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppDimensions.md),

                      // Cooking Suggestions
                      if (product.cookingSuggestions != null)
                        Container(
                          color: AppColors.surface,
                          padding: const EdgeInsets.all(AppDimensions.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.soup_kitchen_rounded,
                                    size: 16,
                                    color: AppColors.accent,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Chef Cooking Suggestions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppDimensions.sm),
                              Text(
                                product.cookingSuggestions!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppDimensions.xxxl),
                    ],
                  ),
                ),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(AppDimensions.lg),
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
                        decoration: BoxDecoration(
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
                              : () async {
                                  final ok = await cartNotifier.addItem(
                                    product,
                                    _selectedVariant!,
                                    qty: _quantity,
                                  );
                                  if (!ok && context.mounted) {
                                    _showLoginRequired(context);
                                  } else if (context.mounted) {
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
                                  }
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
                              : () async {
                                  final ok = await cartNotifier.addItem(
                                    product,
                                    _selectedVariant!,
                                    qty: _quantity,
                                  );
                                  if (!ok && context.mounted) {
                                    _showLoginRequired(context);
                                  } else if (context.mounted) {
                                    context.push(AppRoutes.cart);
                                  }
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
      },
    );
  }

  Widget _buildImageGallery(Product product) {
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: PageView.builder(
            itemCount: product.images.length,
            onPageChanged: (idx) => setState(() => _selectedImageIndex = idx),
            itemBuilder: (context, idx) {
              return CachedNetworkImage(
                imageUrl: product.images[idx],
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
