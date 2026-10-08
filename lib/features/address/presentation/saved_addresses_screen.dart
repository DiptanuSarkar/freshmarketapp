import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../shared/models/address.dart';
import '../../../shared/providers/address_provider.dart';
import '../../profile/data/profile_repository.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressProvider);
    final addressNotifier = ref.read(addressProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Saved Addresses')),
      body: Column(
        children: [
          Expanded(
            child: addresses.isEmpty
                ? AppEmptyState(
                    title: 'No Saved Addresses',
                    message: 'Add your home or office address for fast delivery of fresh butchery cuts.',
                    icon: Icons.location_off_outlined,
                    actionLabel: 'Add Address',
                    onAction: () => _showAddAddressDialog(context, ref),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppDimensions.lg),
                    itemCount: addresses.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppDimensions.md),
                    itemBuilder: (context, index) {
                      final address = addresses[index];
                      return _buildAddressCard(
                        context,
                        address,
                        addressNotifier,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(AppDimensions.lg),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
            ),
            child: SafeArea(
              top: false,
              child: AppButton(
                label: 'Add New Address',
                icon: Icons.add_location_alt_outlined,
                onPressed: () => _showAddAddressDialog(context, ref),
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
              const Spacer(),
              if (address.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppDimensions.roundedPill,
                  ),
                  child: const Text(
                    'DEFAULT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'default') {
                    notifier.setDefault(address.id);
                  } else if (val == 'delete') {
                    notifier.deleteAddress(address.id);
                  }
                },
                itemBuilder: (context) => [
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
        ],
      ),
    );
  }

  void _showAddAddressDialog(BuildContext context, WidgetRef ref) {
    String tag = 'Home';
    final profile = ref.read(userProfileProvider).value;

    final nameCtrl = TextEditingController(text: profile?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: profile?.phone ?? '');
    final houseCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController(text: '560103');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppDimensions.lg,
                left: AppDimensions.lg,
                right: AppDimensions.lg,
                top: AppDimensions.lg,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppDimensions.radiusLg),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Delivery Address',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.md),

                    // Tag Selector
                    Row(
                      children: ['Home', 'Work', 'Other'].map((t) {
                        final isSel = t == tag;
                        return Padding(
                          padding: const EdgeInsets.only(
                            right: AppDimensions.sm,
                          ),
                          child: ChoiceChip(
                            label: Text(t.toUpperCase()),
                            selected: isSel,
                            selectedColor: AppColors.primaryContainer,
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSel
                                  ? AppColors.primaryDark
                                  : AppColors.textSecondary,
                            ),
                            onSelected: (_) => setModalState(() => tag = t),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Name',
                        hintText: 'Enter your full name',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact Phone Number',
                        hintText: '+91 98765 43210',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: houseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'House / Flat / Floor No.',
                        hintText: 'e.g. Flat 301, Block B',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: streetCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Apartment / Street / Area',
                        hintText: 'e.g. Green Glen Layout, Bellandur',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: landmarkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Landmark (Optional)',
                        hintText: 'e.g. Behind Cloudnine Hospital',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.sm),

                    TextField(
                      controller: pincodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Postal Pincode',
                      ),
                    ),
                    const SizedBox(height: AppDimensions.lg),

                    AppButton(
                      label: 'Save Address',
                      width: double.infinity,
                      onPressed: () async {
                        if (houseCtrl.text.isNotEmpty &&
                            streetCtrl.text.isNotEmpty &&
                            nameCtrl.text.isNotEmpty &&
                            phoneCtrl.text.isNotEmpty) {
                          try {
                            await ref
                                .read(addressProvider.notifier)
                                .addAddress(
                                  UserAddress(
                                    id: '',
                                    tag: tag,
                                    recipientName: nameCtrl.text.trim(),
                                    phone: phoneCtrl.text.trim(),
                                    houseOrFlat: houseCtrl.text.trim(),
                                    streetOrArea: streetCtrl.text.trim(),
                                    city: 'Bengaluru',
                                    pincode: pincodeCtrl.text.trim(),
                                    landmark: landmarkCtrl.text.trim().isEmpty
                                        ? null
                                        : landmarkCtrl.text.trim(),
                                    isDefault: ref
                                        .read(addressProvider)
                                        .isEmpty,
                                  ),
                                );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save address: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
