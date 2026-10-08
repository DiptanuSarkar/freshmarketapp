import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/notification_item.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all as read',
            onPressed: () async {
              try {
                await ref.read(notificationsRepositoryProvider).markAllAsRead();
                ref.invalidate(notificationsListProvider);
                ref.invalidate(unreadNotificationsCountProvider);
              } catch (_) {}
            },
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(
          child: AppLoadingIndicator(message: 'Loading notifications...'),
        ),
        error: (err, stack) => AppErrorWidget(
          title: "Couldn't load notifications",
          message: 'Please check your connection and try again.',
          onRetry: () => ref.refresh(notificationsListProvider),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const AppEmptyState(
              title: 'No Notifications Yet',
              message: 'We will update you here about butchery status, live delivery updates, and exclusive fresh offers.',
              icon: Icons.notifications_none_rounded,
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsListProvider);
              ref.invalidate(unreadNotificationsCountProvider);
              await ref.read(notificationsListProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(AppDimensions.lg),
              itemCount: notifications.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppDimensions.sm),
              itemBuilder: (context, index) {
                final notif = notifications[index];
                return _buildNotificationCard(context, ref, notif);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    WidgetRef ref,
    NotificationItem notif,
  ) {
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
      onTap: () async {
        if (!notif.isRead) {
          try {
            await ref
                .read(notificationsRepositoryProvider)
                .markAsRead(notif.id);
            ref.invalidate(notificationsListProvider);
            ref.invalidate(unreadNotificationsCountProvider);
          } catch (_) {}
        }
        if (notif.actionRoute != null && context.mounted) {
          context.push(notif.actionRoute!);
        }
      },
      borderRadius: AppDimensions.roundedMd,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.md),
        decoration: BoxDecoration(
          color: notif.isRead
              ? AppColors.surface
              : AppColors.primaryLight.withValues(alpha: 0.06),
          borderRadius: AppDimensions.roundedMd,
          border: Border.all(
            color: notif.isRead
                ? AppColors.surfaceBorder
                : AppColors.primary.withValues(alpha: 0.3),
          ),
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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: notif.isRead
                                ? FontWeight.w600
                                : FontWeight.w800,
                            color: AppColors.textPrimary,
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
