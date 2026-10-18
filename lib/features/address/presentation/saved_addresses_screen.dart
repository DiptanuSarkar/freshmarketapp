import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/models/address.dart';
import '../../../shared/providers/address_provider.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressProvider);
    final fetchState = ref.watch(addressFetchStateProvider);
    final addressNotifier = ref.read(addressProvider.notifier);

    Widget content;

    if (fetchState.isLoading && addresses.isEmpty) {
      content = const Center(
        child: AppLoadingIndicator(message: 'Loading saved addresses...'),
      );
    } else if (fetchState.hasError && addresses.isEmpty) {
      content = AppEmptyState(
        title: 'Could Not Load Addresses',
        message:
            fetchState.errorMessage ??
            'Please check your connection and retry.',
        icon: Icons.cloud_off_rounded,
        actionLabel: 'Retry',
        onAction: () => addressNotifier.loadAddresses(),
      );
    } else if (addresses.isEmpty) {
      content = AppEmptyState(
        title: 'No Saved Addresses',
        message: 'Pin your exact location on the map for fast, reliable delivery of fresh cuts.',
        icon: Icons.location_off_outlined,
        actionLabel: 'Add Delivery Address',
        onAction: () => context.push(AppRoutes.addAddress),
      );
    } else {
      content = RefreshIndicator(
        onRefresh: () => addressNotifier.loadAddresses(),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppDimensions.lg),
          itemCount: addresses.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppDimensions.md),
          itemBuilder: (context, index) {
            final address = addresses[index];
            return _buildAddressCard(context, address, addressNotifier);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => addressNotifier.loadAddresses(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: content),
          Container(
            padding: const EdgeInsets.all(AppDimensions.lg),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: SafeArea(
              top: false,
              child: AppButton(
                label: 'Add New Address on Map',
                icon: Icons.add_location_alt_outlined,
                onPressed: () => context.push(AppRoutes.addAddress),
                width: double.infinity,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(
    BuildContext context,
    UserAddress address,
    AddressNotifier notifier,
  ) {
    IconData tagIcon;
    final lowerTag = address.tag.toLowerCase();
    if (lowerTag.contains('home')) {
      tagIcon = Icons.home_rounded;
    } else if (lowerTag.contains('work') || lowerTag.contains('office')) {
      tagIcon = Icons.business_rounded;
    } else {
      tagIcon = Icons.location_on_rounded;
    }

    final isVerified = address.isMapVerified;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(
          color: address.isDefault
              ? AppColors.primary
              : AppColors.surfaceBorder,
          width: address.isDefault ? 1.5 : 1.0,
        ),
        boxShadow: AppDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Tag, Default & Map Verified Badges, Options Menu
          Row(
            children: [
              Icon(tagIcon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppDimensions.xs),
              Text(
                address.tag.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),

              // Default Badge
              if (address.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppDimensions.roundedPill,
                  ),
                  child: const Text(
                    'DEFAULT',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              const SizedBox(width: 6),

              // Map Verified Badge
              if (isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: AppDimensions.roundedPill,
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 10,
                        color: AppColors.success,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'MAP VERIFIED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'edit') {
                    context.push(
                      '${AppRoutes.editAddressPrefix}/${address.id}/edit',
                    );
                  } else if (val == 'default') {
                    notifier.setDefault(address.id);
                  } else if (val == 'delete') {
                    notifier.deleteAddress(address.id);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit Address'),
                  ),
                  if (!address.isDefault)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Set as Default'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Address'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),

          Text(
            address.recipientName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            address.formattedAddress,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
          if (address.landmark != null && address.landmark!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Landmark: ${address.landmark}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Phone: ${address.phone}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),

          // For legacy addresses without GPS coordinates: prompt to verify
          if (!isVerified) ...[
            const SizedBox(height: AppDimensions.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: AppDimensions.roundedSm,
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pin not verified on map.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(
                      '${AppRoutes.editAddressPrefix}/${address.id}/edit',
                    ),
                    icon: const Icon(Icons.pin_drop_rounded, size: 14),
                    label: const Text(
                      'Verify on Map',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
