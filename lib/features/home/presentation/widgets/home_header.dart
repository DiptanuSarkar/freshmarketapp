import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/widgets/buttons/app_icon_button.dart';
import '../../../../shared/providers/address_provider.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAddress = ref.watch(selectedAddressProvider);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.lg,
        vertical: AppDimensions.sm,
      ),
      color: AppColors.surface,
      child: Row(
        children: [
          // Location Pin Icon
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppDimensions.sm),

          // Address Display & Selector
          Expanded(
            child: InkWell(
              onTap: () => context.push(AppRoutes.addresses),
              borderRadius: AppDimensions.roundedSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Deliver to: ${selectedAddress.tag}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    Text(
                      selectedAddress.formattedAddress,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Wishlist Action
          AppIconButton(
            icon: Icons.favorite_border_rounded,
            onPressed: () => context.push(AppRoutes.wishlist),
            tooltip: 'Wishlist',
          ),
          const SizedBox(width: AppDimensions.xs),

          // Notifications Action
          AppIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: 2,
            onPressed: () => context.push(AppRoutes.notifications),
            tooltip: 'Notifications',
          ),
        ],
      ),
    );
  }
}
