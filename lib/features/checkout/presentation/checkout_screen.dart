import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../shared/providers/address_provider.dart';
import '../../../shared/providers/cart_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _selectedSlot = 'Today, 5:00 PM - 7:00 PM';
  String _selectedPaymentMethod = 'razorpay';
  bool _isProcessing = false;

  static const List<String> availableSlots = [
    'Today, 5:00 PM - 7:00 PM',
    'Tomorrow, 7:00 AM - 9:00 AM',
    'Tomorrow, 10:00 AM - 12:00 PM',
    'Tomorrow, 4:00 PM - 6:00 PM',
  ];

  void _handlePlaceOrder() {
    setState(() => _isProcessing = true);

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Clear cart
      ref.read(cartProvider.notifier).clearCart();

      // Show Success Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: AppDimensions.roundedLg,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppDimensions.md),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.successContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 40,
                ),
              ),
              const SizedBox(height: AppDimensions.lg),
              const Text(
                'Order Placed Successfully! 🎉',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.xs),
              const Text(
                'Your order has been received by our butchery. We will prepare and chill your cuts immediately.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.xl),
              AppButton(
                label: 'View Orders',
                width: double.infinity,
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go(AppRoutes.orders);
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.lg),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 1: Delivery Address
                  _buildSectionCard(
                    title: '1. Delivery Address',
                    actionLabel: 'Change',
                    onAction: () => context.push(AppRoutes.addresses),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: AppDimensions.roundedPill,
                              ),
                              child: Text(
                                selectedAddress.tag,
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppDimensions.sm),
                            Text(
                              selectedAddress.recipientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              ' • ${selectedAddress.phone}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedAddress.formattedAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Step 2: Delivery Slot Picker
                  _buildSectionCard(
                    title: '2. Select Delivery Slot',
                    content: Column(
                      children: availableSlots.map((slot) {
                        final isSelected = slot == _selectedSlot;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            size: 20,
                          ),
                          title: Text(
                            slot,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          onTap: () {
                            setState(() => _selectedSlot = slot);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Step 3: Payment Method
                  _buildSectionCard(
                    title: '3. Payment Method',
                    content: Column(
                      children: [
                        // Razorpay Online
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            _selectedPaymentMethod == 'razorpay'
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: _selectedPaymentMethod == 'razorpay'
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            size: 20,
                          ),
                          title: const Row(
                            children: [
                              Icon(
                                Icons.payment_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Online Payment (UPI, Cards, Netbanking)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          subtitle: const Text(
                            'Secured by Razorpay • Instant confirmation',
                            style: TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            setState(() => _selectedPaymentMethod = 'razorpay');
                          },
                        ),
                        const Divider(height: 1),

                        // Cash on Delivery
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            _selectedPaymentMethod == 'cod'
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: _selectedPaymentMethod == 'cod'
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            size: 20,
                          ),
                          title: const Row(
                            children: [
                              Icon(
                                Icons.payments_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Cash on Delivery (COD)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          subtitle: const Text(
                            'Pay with cash or UPI at your doorstep',
                            style: TextStyle(fontSize: 11),
                          ),
                          onTap: () {
                            setState(() => _selectedPaymentMethod = 'cod');
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),

                  // Order items preview summary
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
                        Text(
                          'Order Items (${cartState.totalItemCount})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.sm),
                        ...cartState.items.values.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity} x ${item.product.name} (${item.selectedVariant.title})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${AppStrings.currencySymbol}${item.totalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xxxl),
                ],
              ),
            ),
          ),

          // Bottom Place Order Bar
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
                        'Total Amount',
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
                      label: 'Place Order',
                      icon: Icons.check_circle_outline_rounded,
                      isLoading: _isProcessing,
                      onPressed: cartState.isEmpty ? null : _handlePlaceOrder,
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

  Widget _buildSectionCard({
    required String title,
    required Widget content,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (actionLabel != null && onAction != null)
                InkWell(
                  onTap: onAction,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),
          content,
        ],
      ),
    );
  }
}
