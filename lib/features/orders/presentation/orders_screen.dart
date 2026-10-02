import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/badges/status_badge.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../shared/data/mock_data.dart';
import '../../../shared/models/order.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = MockData.sampleOrders;

    if (orders.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('My Orders')),
        body: AppEmptyState(
          title: 'No Orders Yet',
          message: 'When you place an order for fresh meats, you can track butchery preparation and delivery here.',
          icon: Icons.receipt_long_outlined,
          actionLabel: 'Order Fresh Meat',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Orders')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppDimensions.lg),
        itemCount: orders.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppDimensions.md),
        itemBuilder: (context, index) {
          final order = orders[index];
          return _buildOrderCard(context, order);
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, CustomerOrder order) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a')
        .format(order.createdAt);

    BadgeVariant badgeVariant;
    switch (order.status) {
      case OrderStatus.delivered:
        badgeVariant = BadgeVariant.success;
      case OrderStatus.outForDelivery:
        badgeVariant = BadgeVariant.accent;
      case OrderStatus.cancelled:
        badgeVariant = BadgeVariant.error;
      default:
        badgeVariant = BadgeVariant.info;
    }

    return InkWell(
      onTap: () => context.push('${AppRoutes.orderDetailPrefix}/${order.id}'),
      borderRadius: AppDimensions.roundedMd,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.roundedMd,
          border: Border.all(color: AppColors.surfaceBorder, width: 1),
          boxShadow: AppDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order number & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
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
                StatusBadge(
                  label: order.status.displayName,
                  variant: badgeVariant,
                ),
              ],
            ),
            const Divider(height: 20),

            // Items summary
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: order.items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.quantity} x ${item.productName} (${item.variantTitle})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),

            // Total amount & Action button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${AppStrings.currencySymbol}${order.totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () => context.push(
                    '${AppRoutes.orderDetailPrefix}/${order.id}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.2,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppDimensions.roundedSm,
                    ),
                  ),
                  child: const Text(
                    'Track Order',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
