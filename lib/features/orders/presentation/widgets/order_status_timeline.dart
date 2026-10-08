import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/order.dart';

class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({super.key, required this.currentStatus});

  final OrderStatus currentStatus;

  static const List<OrderStatus> progression = [
    OrderStatus.orderPlaced,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.packed,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    if (currentStatus == OrderStatus.paymentPending) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.hourglass_top_rounded,
              color: AppColors.warning,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Awaiting Payment',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Complete payment within 15 minutes to confirm your order.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (currentStatus == OrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
            SizedBox(width: 8),
            Text(
              'This order was cancelled.',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final currentIndex = progression.indexOf(currentStatus);

    return Column(
      children: List.generate(progression.length, (index) {
        final stepStatus = progression[index];
        final isCompleted = currentIndex >= index;
        final isCurrent = currentIndex == index;
        final isLast = index == progression.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Node & Connecting Line
            Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.surfaceSubtle,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.primaryDark
                          : (isCompleted
                                ? AppColors.primary
                                : AppColors.surfaceBorder),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textTertiary,
                            ),
                          ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 28,
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.surfaceBorder,
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Right Text
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                stepStatus.displayName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent
                      ? FontWeight.w800
                      : (isCompleted ? FontWeight.w600 : FontWeight.w400),
                  color: isCurrent
                      ? AppColors.primaryDark
                      : (isCompleted
                            ? AppColors.textPrimary
                            : AppColors.textTertiary),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
