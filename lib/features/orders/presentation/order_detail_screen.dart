import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../shared/data/mock_data.dart';
import '../../../shared/models/order.dart';
import 'widgets/order_status_timeline.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    CustomerOrder? order;
    try {
      order = MockData.sampleOrders.firstWhere((o) => o.id == orderId);
    } catch (_) {
      order = null;
    }

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
                      const Text(
                        'Live Order Status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (order.estimatedDeliveryTime != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: AppDimensions.roundedSm,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delivery_dining_rounded,
                            size: 18,
                            color: AppColors.primaryDark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            order.estimatedDeliveryTime!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimensions.lg),
                  OrderStatusTimeline(currentStatus: order.status),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            // Delivery Details Card
            _buildDetailCard(
              title: 'Delivery Information',
              icon: Icons.location_on_outlined,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.deliveryAddress,
                    style: const TextStyle(fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Delivery Slot: ${order.deliverySlot}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            // Ordered Items
            _buildDetailCard(
              title: 'Items in this Order (${order.items.length})',
              icon: Icons.inventory_2_outlined,
              content: Column(
                children: order.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: AppDimensions.roundedSm,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: CachedNetworkImage(
                              imageUrl: item.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (ctx, url) =>
                                  Container(color: AppColors.surfaceSubtle),
                              errorWidget: (ctx, url, err) => Container(
                                color: AppColors.surfaceSubtle,
                                child: const Icon(
                                  Icons.fastfood,
                                  size: 20,
                                  color: AppColors.textTertiary,
                                ),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${item.variantTitle} • Qty: ${item.quantity}',
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            // Payment Summary
            _buildDetailCard(
              title: 'Payment Breakdown',
              icon: Icons.receipt_outlined,
              content: Column(
                children: [
                  _buildPriceRow(
                    'Subtotal',
                    '${AppStrings.currencySymbol}${order.subtotal.toStringAsFixed(0)}',
                  ),
                  if (order.discount > 0)
                    _buildPriceRow(
                      'Discount',
                      '-${AppStrings.currencySymbol}${order.discount.toStringAsFixed(0)}',
                      color: AppColors.success,
                    ),
                  _buildPriceRow(
                    'Delivery Fee',
                    order.deliveryFee == 0
                        ? 'FREE'
                        : '${AppStrings.currencySymbol}${order.deliveryFee.toStringAsFixed(0)}',
                  ),
                  const Divider(height: 16),
                  _buildPriceRow(
                    'Total Paid (${order.paymentMethod})',
                    '${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Widget content,
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
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.md),
          content,
        ],
      ),
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
}
