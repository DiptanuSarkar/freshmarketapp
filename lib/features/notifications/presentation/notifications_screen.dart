import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../shared/data/mock_data.dart';
import '../../../shared/models/notification_item.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = MockData.notifications;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppDimensions.lg),
        itemCount: notifications.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppDimensions.sm),
        itemBuilder: (context, index) {
          final notif = notifications[index];
          return _buildNotificationCard(context, notif);
        },
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, NotificationItem notif) {
    final timeStr = DateFormat('dd MMM, hh:mm a').format(notif.createdAt);

    IconData iconData;
    Color iconColor;
    Color bgColor;

    switch (notif.type) {
      case NotificationType.order:
        iconData = Icons.local_shipping_outlined;
        iconColor = AppColors.primary;
        bgColor = AppColors.primaryContainer;
      case NotificationType.offer:
        iconData = Icons.local_offer_outlined;
        iconColor = AppColors.accent;
        bgColor = AppColors.accentContainer;
      case NotificationType.wallet:
        iconData = Icons.account_balance_wallet_outlined;
        iconColor = AppColors.success;
        bgColor = AppColors.successContainer;
      case NotificationType.system:
        iconData = Icons.info_outline;
        iconColor = AppColors.info;
        bgColor = AppColors.infoContainer;
    }

    return InkWell(
      onTap: () {
        if (notif.actionRoute != null) {
          context.push(notif.actionRoute!);
        }
      },
      borderRadius: AppDimensions.roundedMd,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.roundedMd,
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: AppDimensions.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notif.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notif.body,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
