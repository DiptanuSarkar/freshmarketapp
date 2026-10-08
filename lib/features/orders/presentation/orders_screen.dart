import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/badges/status_badge.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/order.dart';
import '../data/orders_repository.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        loading: () => const Center(
          child: AppLoadingIndicator(message: 'Loading your orders...'),
        ),
        error: (err, stack) => AppErrorWidget(
          title: "Couldn't load orders",
          message: 'Please check your connection and try again.',
          onRetry: () => ref.refresh(customerOrdersProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return AppEmptyState(
              title: 'No Orders Yet',
              message: 'When you place an order for fresh meats, you can track butchery preparation and delivery here.',
              icon: Icons.receipt_long_outlined,
              actionLabel: 'Order Fresh Meat',
              onAction: () => context.go(AppRoutes.home),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customerOrdersProvider);
              await ref.read(customerOrdersProvider.future);
            },
            child: ListView.separated(
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
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, CustomerOrder order) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a')
        .format(order.createdAt);

    BadgeVariant badgeVariant;
    switch (order.status) {
      case OrderStatus.paymentPending:
        badgeVariant = BadgeVariant.warning;
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
          border: Border.all(color: AppColors.surfaceBorder),
          boxShadow: AppDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Order ID & Status Badge
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
                    const SizedBox(height: 2),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
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
            const SizedBox(height: AppDimensions.md),
            const Divider(height: 1),
            const SizedBox(height: AppDimensions.sm),

            // Items Summary
            Text(
              order.items
                  .map((item) => '${item.quantity}x ${item.productName}')
                  .join(', '),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppDimensions.md),

            // Bottom Row: Total & Action CTA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Total: ',
                      style: TextStyle(
                        fontSize: 12,
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
                const Row(
                  children: [
                    Text(
                      'Track Order',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
