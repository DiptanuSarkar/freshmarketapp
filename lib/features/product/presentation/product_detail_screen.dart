import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_rating_summary.dart';
import '../../../shared/models/product_review.dart';
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
        final ratingSummary =
            ref.watch(productRatingSummaryProvider(widget.productId)).value ??
            ProductRatingSummary.empty;
        final avgRating = ratingSummary.reviewCount > 0
            ? ratingSummary.averageRating
            : product.rating;
        final totalReviews = ratingSummary.reviewCount > 0
            ? ratingSummary.reviewCount
            : product.reviewCount;
        final eligibilityAsync = ref.watch(
          productReviewEligibilityProvider(widget.productId),
        );
        final reviewsAsync = ref.watch(
          productReviewsProvider(widget.productId),
        );
        final currentUser = ref.watch(currentUserProvider);

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
                onPressed: () => context.go(AppRoutes.cart),
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
                                        avgRating.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                      Text(
                                        ' ($totalReviews)',
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
                                    (_selectedVariant!.netWeightDisplay!.split(
                                      '|',
                                    )[0]).replaceAll('Net wt:', '').trim(),
                                    'Net Weight',
                                  ),
                                if (_selectedVariant!.grossWeightDisplay !=
                                    null)
                                  _buildHighlightItem(
                                    Icons.kitchen_outlined,
                                    (_selectedVariant!.grossWeightDisplay!
                                        .replaceAll('Gross wt:', '')
                                        .replaceAll('Gross:', '')
                                        .trim()),
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
                      const SizedBox(height: AppDimensions.md),

                      // Customer Reviews Section
                      _buildReviewsSection(
                        context,
                        product,
                        ratingSummary,
                        avgRating,
                        totalReviews,
                        eligibilityAsync,
                        reviewsAsync,
                        currentUser,
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
                                              context.go(AppRoutes.cart),
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
                                    context.go(AppRoutes.cart);
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
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection(
    BuildContext context,
    Product product,
    ProductRatingSummary ratingSummary,
    double avgRating,
    int totalReviews,
    AsyncValue<Map<String, dynamic>> eligibilityAsync,
    AsyncValue<List<ProductReview>> reviewsAsync,
    dynamic currentUser,
  ) {
    final eligibility = eligibilityAsync.value;
    final isEligible = eligibility?['is_eligible'] == true;
    final existingReview =
        eligibility?['existing_review'] as Map<String, dynamic>?;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppDimensions.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.rate_review_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Customer Reviews & Ratings',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (isEligible)
                TextButton.icon(
                  onPressed: () =>
                      _showReviewBottomSheet(context, existingReview),
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: Text(
                    existingReview != null ? 'Edit Review' : 'Write Review',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimensions.md),

          // Rating Score & Distribution Card
          Container(
            padding: const EdgeInsets.all(AppDimensions.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: AppDimensions.roundedMd,
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < avgRating.round()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 16,
                          color: AppColors.warning,
                        );
                      }),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalReviews verified ratings',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDimensions.lg),
                Expanded(
                  child: Column(
                    children: [5, 4, 3, 2, 1].map((star) {
                      final count = ratingSummary.breakdown[star] ?? 0;
                      final ratio = totalReviews > 0
                          ? (count / totalReviews)
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Row(
                          children: [
                            Text(
                              '$star★',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 4,
                                  backgroundColor: AppColors.surfaceBorder,
                                  valueColor: const AlwaysStoppedAnimation(
                                    AppColors.warning,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 20,
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.md),

          // Eligibility Banner for non-eligible users
          if (!isEligible) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.md,
                vertical: AppDimensions.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: AppDimensions.roundedSm,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Verified Purchase Reviews are enabled automatically after your order has been delivered fresh.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),
          ],

          // Reviews List
          reviewsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppDimensions.md),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(AppDimensions.md),
              child: Text(
                'Could not load reviews: $err',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
            data: (reviews) {
              if (reviews.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: AppDimensions.roundedSm,
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 28,
                        color: AppColors.textTertiary,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'No customer reviews yet.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Order this fresh cut to be the first verified reviewer!',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: AppDimensions.lg),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  final formattedDate = DateFormat('dd MMM yyyy')
                      .format(review.createdAt);
                  final isOwnReview =
                      currentUser != null && review.userId == currentUser.id;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Row(
                                children: List.generate(5, (i) {
                                  return Icon(
                                    i < review.rating
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    size: 14,
                                    color: AppColors.warning,
                                  );
                                }),
                              ),
                              const SizedBox(width: 8),
                              if (review.isVerifiedPurchase)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFC8E6C9),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 11,
                                        color: Color(0xFF2E7D32),
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Verified Purchase',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1B5E20),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (isOwnReview)
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                size: 16,
                                color: AppColors.textTertiary,
                              ),
                              onSelected: (val) async {
                                if (val == 'edit') {
                                  _showReviewBottomSheet(context, {
                                    'id': review.id,
                                    'rating': review.rating,
                                    'title': review.title,
                                    'review_text': review.reviewText,
                                  });
                                } else if (val == 'delete') {
                                  await _handleDeleteReview(context, review.id);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16),
                                      SizedBox(width: 8),
                                      Text('Edit Review'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 16,
                                        color: AppColors.error,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Delete Review',
                                        style: TextStyle(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (review.title != null && review.title!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          review.title!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                      if (review.reviewText != null &&
                          review.reviewText!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          review.reviewText!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${review.authorName} • $formattedDate',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteReview(
    BuildContext context,
    String reviewId,
  ) async {
    try {
      await ref.read(catalogRepositoryProvider).deleteProductReview(reviewId);
      ref.invalidate(productRatingSummaryProvider(widget.productId));
      ref.invalidate(productReviewsProvider(widget.productId));
      ref.invalidate(productReviewEligibilityProvider(widget.productId));
      ref.invalidate(catalogProductByIdProvider(widget.productId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review deleted.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete review: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showReviewBottomSheet(
    BuildContext context,
    Map<String, dynamic>? existingReview,
  ) {
    int selectedRating = existingReview?['rating'] as int? ?? 5;
    final titleController = TextEditingController(
      text: existingReview?['title'] as String? ?? '',
    );
    final textController = TextEditingController(
      text: existingReview?['review_text'] as String? ?? '',
    );
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppDimensions.lg,
                right: AppDimensions.lg,
                top: AppDimensions.lg,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppDimensions.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          existingReview != null
                              ? 'Edit Your Review'
                              : 'Write a Product Review',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.xs),
                    const Text(
                      'Rate this fresh cut based on freshness, taste, and butchery quality.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.md),

                    // Star Rating Picker
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (idx) {
                          final star = idx + 1;
                          final isFilled = star <= selectedRating;
                          return InkWell(
                            onTap: isSubmitting
                                ? null
                                : () => setSheetState(
                                    () => selectedRating = star,
                                  ),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Icon(
                                isFilled
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 36,
                                color: isFilled
                                    ? AppColors.warning
                                    : AppColors.textTertiary,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Center(
                      child: Text(
                        _getRatingLabel(selectedRating),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.md),

                    // Review Title
                    TextField(
                      controller: titleController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Headline / Title (Optional)',
                        hintText: 'e.g. Incredibly tender & fresh!',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    // Review Text
                    TextField(
                      controller: textController,
                      enabled: !isSubmitting,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Review Details (Optional)',
                        hintText: 'Share details about freshness, cut precision, or your recipe experience...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.lg),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppDimensions.roundedMd,
                          ),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setSheetState(() => isSubmitting = true);
                                try {
                                  await ref
                                      .read(catalogRepositoryProvider)
                                      .submitProductReview(
                                        productId: widget.productId,
                                        rating: selectedRating,
                                        title:
                                            titleController.text
                                                .trim()
                                                .isNotEmpty
                                            ? titleController.text.trim()
                                            : null,
                                        reviewText:
                                            textController.text
                                                .trim()
                                                .isNotEmpty
                                            ? textController.text.trim()
                                            : null,
                                      );

                                  ref.invalidate(
                                    productRatingSummaryProvider(
                                      widget.productId,
                                    ),
                                  );
                                  ref.invalidate(
                                    productReviewsProvider(widget.productId),
                                  );
                                  ref.invalidate(
                                    productReviewEligibilityProvider(
                                      widget.productId,
                                    ),
                                  );
                                  ref.invalidate(
                                    catalogProductByIdProvider(
                                      widget.productId,
                                    ),
                                  );

                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          existingReview != null
                                              ? 'Review updated successfully!'
                                              : 'Thank you! Your verified review has been posted.',
                                        ),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    setSheetState(() => isSubmitting = false);
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to submit review: $e',
                                        ),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                existingReview != null
                                    ? 'Update Review'
                                    : 'Submit Review',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getRatingLabel(int rating) {
    switch (rating) {
      case 5:
        return '5 Stars — Outstanding Freshness';
      case 4:
        return '4 Stars — Very Good Quality';
      case 3:
        return '3 Stars — Average Butchery';
      case 2:
        return '2 Stars — Below Expectations';
      case 1:
        return '1 Star — Unsatisfactory';
      default:
        return '$rating Stars';
    }
  }
}
