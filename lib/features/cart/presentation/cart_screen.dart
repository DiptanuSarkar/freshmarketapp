import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../shared/providers/address_provider.dart';
import '../../../shared/providers/cart_provider.dart';
import 'widgets/cart_bill_summary.dart';
import 'widgets/cart_item_tile.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _couponController = TextEditingController();

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final selectedAddress = ref.watch(selectedAddressProvider);

    if (cartState.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('My Cart')),
        body: AppEmptyState(
          title: 'Your Fresh Cart is Empty',
          message: 'Add antibiotic-free chicken, fresh mutton, coastal seafood, or daily groceries.',
          icon: Icons.shopping_bag_outlined,
          actionLabel: 'Browse Fresh Meat',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Cart (${cartState.totalItemCount} items)'),
        actions: [
          TextButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear Cart?'),
                  content: const Text(
                    'Are you sure you want to remove all items from your basket?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        cartNotifier.clearCart();
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'Clear',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: const Text(
              'Clear All',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.lg),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivering to header banner
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppDimensions.roundedMd,
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppDimensions.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivering to ${selectedAddress.tag}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                selectedAddress.formattedAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => context.push(AppRoutes.addresses),
                          child: const Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Cart Item List
                  ...cartState.items.values.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppDimensions.sm),
                      child: CartItemTile(item: item),
                    );
                  }),
                  const SizedBox(height: AppDimensions.sm),

                  // Coupon Section
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppDimensions.roundedMd,
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_offer_outlined,
                              color: AppColors.accent,
                              size: 18,
                            ),
                            const SizedBox(width: AppDimensions.sm),
                            const Text(
                              'Coupons & Offers',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.sm),
                        if (cartState.appliedCouponCode != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successContainer,
                              borderRadius: AppDimensions.roundedSm,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.success,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Code "${cartState.appliedCouponCode}" Applied (₹${cartState.couponDiscount.toStringAsFixed(0)} off)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: () => cartNotifier.removeCoupon(),
                                  child: const Text(
                                    'Remove',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _couponController,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Enter coupon code (try FRESH50)',
                                      hintStyle: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: AppDimensions.roundedSm,
                                        borderSide: const BorderSide(
                                          color: AppColors.surfaceBorder,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppDimensions.sm),
                              SizedBox(
                                height: 38,
                                child: ElevatedButton(
                                  onPressed: () {
                                    final code = _couponController.text.trim();
                                    if (code.isNotEmpty) {
                                      cartNotifier.applyCoupon(code);
                                      if (cartState.appliedCouponCode == null &&
                                          code.toUpperCase() != 'FRESH50') {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Invalid coupon code',
                                                ),
                                              ),
                                            );
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: AppDimensions.roundedSm,
                                    ),
                                  ),
                                  child: const Text(
                                    AppStrings.apply,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Bill Summary Card
                  CartBillSummary(cartState: cartState),
                  const SizedBox(height: AppDimensions.md),

                  // Safety & Temperature Guarantee
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: AppDimensions.roundedMd,
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: AppDimensions.sm),
                        Expanded(
                          child: Text(
                            'Hygienic Temperature-Controlled Delivery • Freshness 100% Guaranteed',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
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

          // Bottom Checkout CTA Bar
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total Payable',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '${AppStrings.currencySymbol}${cartState.totalPayable.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppDimensions.xl),
                  Expanded(
                    child: AppButton(
                      label: AppStrings.checkout,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () => context.push(AppRoutes.checkout),
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
}
