import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/order.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../payment/presentation/providers/razorpay_controller.dart';
import '../data/orders_repository.dart';
import 'widgets/order_status_timeline.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));

    return orderAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: const Center(
          child: AppLoadingIndicator(message: 'Loading order details...'),
        ),
      ),
      error: (err, stack) => Scaffold(
        appBar: AppBar(title: const Text('Order Details')),
        body: AppErrorWidget(
          title: "Couldn't load order",
          message: 'Please check your connection and try again.',
          onRetry: () => ref.refresh(orderDetailProvider(orderId)),
        ),
      ),
      data: (order) {
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Details')),
            body: AppErrorWidget(
              title: 'Order not found',
              message: 'Could not find details for order #$orderId.',
              retryLabel: 'Go Back',
              onRetry: () => Navigator.pop(context),
            ),
          );
        }

        final formattedDate = DateFormat('dd MMM yyyy, hh:mm a')
            .format(order.createdAt);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: Text(order.orderNumber)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.lg),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.status == OrderStatus.cancelled) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDimensions.md),
                    margin: const EdgeInsets.only(bottom: AppDimensions.md),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: AppDimensions.roundedMd,
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.cancel_outlined,
                          color: AppColors.error,
                          size: 22,
                        ),
                        const SizedBox(width: AppDimensions.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Order Cancelled',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.error,
                                ),
                              ),
                              if (order.cancellationReason != null &&
                                  order.cancellationReason!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Reason: ${order.cancellationReason}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Status & Live ETA Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDimensions.lg),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.status.displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: AppDimensions.roundedPill,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: AppColors.primaryDark,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  order.deliverySlot,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Placed on $formattedDate',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.lg),

                // Butchery & Delivery Timeline
                Container(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDimensions.roundedMd,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preparation & Delivery Timeline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),
                      OrderStatusTimeline(currentStatus: order.status),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.lg),

                // Order Items List
                Container(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDimensions.roundedMd,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cuts Ordered (${order.items.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: order.items.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: AppDimensions.lg),
                        itemBuilder: (context, index) {
                          final item = order.items[index];
                          return Row(
                            children: [
                              ClipRRect(
                                borderRadius: AppDimensions.roundedSm,
                                child: CachedNetworkImage(
                                  imageUrl: item.imageUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(
                                        width: 48,
                                        height: 48,
                                        color: AppColors.surfaceSubtle,
                                        child: const Icon(
                                          Icons.restaurant,
                                          size: 20,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: AppDimensions.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.variantTitle} x ${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${AppStrings.currencySymbol}${item.totalPrice.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.lg),

                // Delivery Details Card
                Container(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDimensions.roundedMd,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delivery Details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: AppDimensions.xs),
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
                      const SizedBox(height: AppDimensions.sm),
                      Row(
                        children: [
                          const Icon(
                            Icons.payment_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: AppDimensions.xs),
                          Text(
                            'Payment: ${order.paymentMethod} (${order.paymentStatus})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.lg),

                // Bill Summary
                Container(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDimensions.roundedMd,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bill Summary',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      _buildPriceRow(
                        'Item Total',
                        '${AppStrings.currencySymbol}${order.subtotal.toStringAsFixed(0)}',
                      ),
                      if (order.discount > 0)
                        _buildPriceRow(
                          'Promo Discount',
                          '-${AppStrings.currencySymbol}${order.discount.toStringAsFixed(0)}',
                          color: AppColors.accent,
                        ),
                      _buildPriceRow(
                        'Delivery Fee',
                        order.deliveryFee == 0
                            ? 'FREE'
                            : '${AppStrings.currencySymbol}${order.deliveryFee.toStringAsFixed(0)}',
                        color: order.deliveryFee == 0
                            ? AppColors.success
                            : null,
                      ),
                      const Divider(height: AppDimensions.md),
                      _buildPriceRow(
                        'Grand Total',
                        '${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.lg),

                // Payment Details
                Container(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDimensions.roundedMd,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment Details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      _buildPriceRow(
                        'Payment Method',
                        order.paymentMethod == 'RAZORPAY' ||
                                order.paymentMethod == 'ONLINE'
                            ? 'Online Payment (Razorpay)'
                            : order.paymentMethod,
                      ),
                      _buildPriceRow(
                        'Payment Status',
                        order.paymentStatus,
                        color: order.paymentStatus.toUpperCase() == 'COMPLETED'
                            ? AppColors.success
                            : (order.paymentStatus.toUpperCase() == 'FAILED'
                                  ? AppColors.error
                                  : AppColors.warning),
                        isBold: true,
                      ),
                    ],
                  ),
                ),

                // Actions for Awaiting Payment (Online Retry & Reconciliation)
                if (order.status == OrderStatus.paymentPending) ...[
                  const SizedBox(height: AppDimensions.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDimensions.roundedMd,
                        ),
                      ),
                      onPressed: () async {
                        ref
                            .read(razorpayControllerProvider.notifier)
                            .retryPayment(orderId: order.id);
                      },
                      icon: const Icon(Icons.payment_rounded, size: 18),
                      label: const Text(
                        'Pay Now / Retry Payment',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDimensions.roundedMd,
                        ),
                      ),
                      onPressed: () async {
                        final res = await ref
                            .read(razorpayControllerProvider.notifier)
                            .checkStatus(orderId: order.id);
                        ref.invalidate(orderDetailProvider(order.id));
                        ref.invalidate(customerOrdersProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res.isOrderConfirmed
                                    ? 'Payment confirmed! Order is now Confirmed.'
                                    : (res.message ?? 'Status: ${res.status}'),
                              ),
                              backgroundColor: res.isOrderConfirmed
                                  ? AppColors.success
                                  : AppColors.primary,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text(
                        'Check Payment Status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],

                // Cancellation Action for eligible orders
                if (order.status == OrderStatus.paymentPending ||
                    order.status == OrderStatus.orderPlaced ||
                    order.status == OrderStatus.confirmed) ...[
                  const SizedBox(height: AppDimensions.lg),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDimensions.roundedMd,
                        ),
                      ),
                      onPressed: () =>
                          _showCancelOrderDialog(context, ref, order),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text(
                        'Cancel Order',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppDimensions.xl),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPriceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelOrderDialog(
    BuildContext context,
    WidgetRef ref,
    CustomerOrder order,
  ) async {
    final reasons = [
      'Placed order by mistake',
      'Need to change delivery address',
      'Delivery time is not suitable',
      'Found a better price or deal',
      'Other reason',
    ];

    String selectedReason = reasons.first;
    final noteController = TextEditingController();
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: AppDimensions.roundedLg,
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  SizedBox(width: 8),
                  Text(
                    'Cancel Order',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Are you sure you want to cancel this order? Any reserved inventory will be immediately released.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Please select a reason:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...reasons.map((r) {
                      final isSelected = selectedReason == r;
                      return InkWell(
                        onTap: isSubmitting
                            ? null
                            : () => setState(() => selectedReason = r),
                        borderRadius: AppDimensions.roundedSm,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (selectedReason == 'Other reason') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(
                          hintText: 'Enter reason details...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Keep Order'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setState(() => isSubmitting = true);
                          try {
                            final finalReason =
                                selectedReason == 'Other reason' &&
                                    noteController.text.trim().isNotEmpty
                                ? noteController.text.trim()
                                : selectedReason;

                            await ref
                                .read(checkoutRepositoryProvider)
                                .cancelOrder(
                                  orderId: order.id,
                                  reason: finalReason,
                                );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            ref.invalidate(orderDetailProvider(order.id));
                            ref.invalidate(customerOrdersProvider);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Order cancelled successfully'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setState(() => isSubmitting = false);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
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
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Confirm Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
