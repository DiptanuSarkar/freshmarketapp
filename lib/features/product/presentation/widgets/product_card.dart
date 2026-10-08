import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/models/product.dart';
import '../../../../shared/models/product_variant.dart';
import '../../../../shared/providers/cart_provider.dart';
import '../../../../shared/providers/wishlist_provider.dart';

class ProductCard extends ConsumerStatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.width = AppDimensions.productCardWidth,
  });

  final Product product;
  final double width;

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  late ProductVariant _selectedVariant;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.product.defaultVariant;
  }

  @override
  void didUpdateWidget(covariant ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _selectedVariant = widget.product.defaultVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final isFav = ref.watch(wishlistProvider).contains(widget.product.id);

    final cartKey = '${widget.product.id}_${_selectedVariant.id}';
    final currentQty = cartState.items[cartKey]?.quantity ?? 0;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(color: AppColors.surfaceBorder, width: 1),
        boxShadow: AppDimensions.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          context.push('${AppRoutes.productDetailPrefix}/${widget.product.id}');
        },
        borderRadius: AppDimensions.roundedMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Stack
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppDimensions.radiusMd),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.25,
                    child: CachedNetworkImage(
                      imageUrl: widget.product.mainImage,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppColors.surfaceSubtle,
                        child: const Center(
                          child: Icon(
                            Icons.fastfood_outlined,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppColors.surfaceSubtle,
                        child: const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Discount Badge
                if (_selectedVariant.hasDiscount)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: AppDimensions.roundedXs,
                      ),
                      child: Text(
                        '${_selectedVariant.discountPercentage}% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),

                // Favorite Toggle
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final ok = await ref
                            .read(wishlistProvider.notifier)
                            .toggle(widget.product.id);
                        if (!ok && context.mounted) {
                          _showLoginRequired(context);
                        }
                      },
                      borderRadius: AppDimensions.roundedPill,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x1A000000), blurRadius: 4),
                          ],
                        ),
                        child: Icon(
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFav
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        Text(
                          widget.product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Variant / Weight Display
                        if (widget.product.isVariableProduct)
                          InkWell(
                            onTap: () => _showVariantBottomSheet(context),
                            borderRadius: AppDimensions.roundedXs,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: AppDimensions.roundedXs,
                                border: Border.all(
                                  color: AppColors.surfaceBorder,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedVariant.title,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            _selectedVariant.title,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),

                    // Price & Add to Cart Action Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Price column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${AppStrings.currencySymbol}${_selectedVariant.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (_selectedVariant.hasDiscount)
                                Text(
                                  '${AppStrings.currencySymbol}${_selectedVariant.originalPrice!.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textTertiary,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Action Button or Stepper
                        if (_selectedVariant.isOutOfStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: AppDimensions.roundedSm,
                            ),
                            child: const Text(
                              'Out of Stock',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (currentQty > 0)
                          Container(
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: AppDimensions.roundedSm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () =>
                                      cartNotifier.updateQuantity(cartKey, -1),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Icon(
                                      Icons.remove,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$currentQty',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                InkWell(
                                  onTap: () =>
                                      cartNotifier.updateQuantity(cartKey, 1),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            height: 28,
                            child: OutlinedButton(
                              onPressed: () async {
                                final ok = await cartNotifier.addItem(
                                  widget.product,
                                  _selectedVariant,
                                );
                                if (!ok && context.mounted) {
                                  _showLoginRequired(context);
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                side: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.2,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: AppDimensions.roundedSm,
                                ),
                                minimumSize: Size.zero,
                              ),
                              child: const Text(
                                AppStrings.add,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  void _showVariantBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Variant for ${widget.product.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppDimensions.md),
                ...widget.product.variants.map((v) {
                  final isSelected = v.id == _selectedVariant.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      v.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: v.netWeightDisplay != null
                        ? Text(v.netWeightDisplay!)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${AppStrings.currencySymbol}${v.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (v.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${AppStrings.currencySymbol}${v.originalPrice!.toStringAsFixed(0)}',
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textTertiary,
                      size: 22,
                    ),
                    selected: isSelected,
                    onTap: () {
                      setState(() => _selectedVariant = v);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
