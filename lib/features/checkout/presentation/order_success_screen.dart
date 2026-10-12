import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../orders/data/orders_repository.dart';

class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order Confirmed'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Home',
            onPressed: () => context.go(AppRoutes.home),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: AppLoadingIndicator(message: 'Loading order confirmation...'),
        ),
        error: (_, _) => _buildFallbackView(context),
        data: (order) {
          if (order == null) return _buildFallbackView(context);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.lg),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: AppDimensions.lg),

                // Success Icon Animation / Container
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.successContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 52,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.md),

                // Congratulations Title
                const Text(
                  'Order Placed Successfully!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Order Number: ${order.orderNumber}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppDimensions.xl),

                // Payment Instructions Card
                _buildPaymentInfoCard(order),
                const SizedBox(height: AppDimensions.md),

                // Delivery Information Card
                Container(
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
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Slot: ${order.deliverySlot}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.deliveryAddress,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.md),

                // Items summary snippet
                Container(
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
                      Text(
                        'Items Ordered (${order.items.length})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.xs),
                      ...order.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.quantity}x ${item.productName} (${item.variantTitle})',
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
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Grand Total',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.xl),

                // Actions
                AppButton(
                  label: 'View Order Details',
                  icon: Icons.receipt_long_rounded,
                  onPressed: () =>
                      context.go('${AppRoutes.orderDetailPrefix}/$orderId'),
                ),
                const SizedBox(height: AppDimensions.sm),
                AppButton(
                  label: 'Continue Shopping',
                  variant: AppButtonVariant.outline,
                  onPressed: () => context.go(AppRoutes.home),
                ),
                const SizedBox(height: AppDimensions.xl),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentInfoCard(dynamic order) {
    final method = (order.paymentMethod as String? ?? 'COD').toUpperCase();
    final isWallet = method == 'WALLET';
    final isMixed = method == 'MIXED';
    final isOnline = method == 'RAZORPAY' || method == 'ONLINE';

    String title;
    IconData icon;
    String badgeText;
    Color badgeColor;
    Color badgeBg;
    String description;

    if (isWallet) {
      title = 'FreshMarket Wallet';
      icon = Icons.account_balance_wallet_rounded;
      badgeText = 'Paid / Confirmed';
      badgeColor = AppColors.success;
      badgeBg = AppColors.successContainer;
      description =
          '${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)} was paid instantly from your FreshMarket Wallet. No cash or payment required at delivery.';
    } else if (isMixed) {
      title = 'Wallet + Online Payment';
      icon = Icons.payment_rounded;
      badgeText = 'Paid / Confirmed';
      badgeColor = AppColors.success;
      badgeBg = AppColors.successContainer;
      description =
          'Paid via ${AppStrings.currencySymbol}${order.walletAmountUsed.toStringAsFixed(0)} from Wallet and ${AppStrings.currencySymbol}${order.gatewayAmount.toStringAsFixed(0)} via Razorpay online payment.';
    } else if (isOnline) {
      title = 'Online Payment (Razorpay)';
      icon = Icons.credit_card_rounded;
      badgeText = 'Paid / Confirmed';
      badgeColor = AppColors.success;
      badgeBg = AppColors.successContainer;
      description =
          'Payment of ${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)} verified and captured securely via Razorpay.';
    } else {
      title = 'Cash on Delivery (COD)';
      icon = Icons.payments_outlined;
      badgeText = 'Payment Pending';
      badgeColor = AppColors.warning;
      badgeBg = AppColors.warningContainer;
      description =
          'Please keep ${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)} ready in cash or pay via UPI QR code to our delivery executive when your cuts arrive.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: AppDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: AppDimensions.roundedPill,
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: AppColors.success,
            ),
            const SizedBox(height: AppDimensions.md),
            const Text(
              'Order Placed!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppDimensions.xs),
            const Text(
              'Your cash on delivery order has been received.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.xl),
            AppButton(
              label: 'Go to My Orders',
              onPressed: () => context.go(AppRoutes.orders),
            ),
          ],
        ),
      ),
    );
  }
}
