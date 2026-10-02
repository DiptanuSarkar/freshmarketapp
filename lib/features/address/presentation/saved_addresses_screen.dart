import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../shared/models/address.dart';
import '../../../shared/providers/address_provider.dart';

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
    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(
          color: address.isDefault
              ? AppColors.primary
              : AppColors.surfaceBorder,
          width: address.isDefault ? 1.5 : 1,
        ),
        boxShadow: AppDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: address.isDefault
                          ? AppColors.primaryContainer
                          : AppColors.surfaceSubtle,
                      borderRadius: AppDimensions.roundedPill,
                    ),
                    child: Text(
                      address.tag,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: address.isDefault
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (address.isDefault) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'DEFAULT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
              if (!address.isDefault)
                TextButton(
                  onPressed: () => notifier.setDefault(address.id),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Set as Default',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimensions.sm),
          Text(
            '${address.recipientName} • ${address.phone}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            address.formattedAddress,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddAddressDialog(BuildContext context, WidgetRef ref) {
    final houseCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController(text: '560103');
    String tag = 'Home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.radiusLg),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppDimensions.lg,
                right: AppDimensions.lg,
                top: AppDimensions.lg,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppDimensions.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Delivery Address',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.md),

                    // Tag Selector
                    Row(
                      children: ['Home', 'Work', 'Other'].map((t) {
                        final isSel = tag == t;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(t),
                            selected: isSel,
                            onSelected: (val) => setModalState(() => tag = t),
                          ),
                        );
                      }).toList(),
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
                      onPressed: () {
                        if (houseCtrl.text.isNotEmpty &&
                            streetCtrl.text.isNotEmpty) {
                          ref
                              .read(addressProvider.notifier)
                              .addAddress(
                                UserAddress(
                                  id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
                                  tag: tag,
                                  recipientName: 'Rahul Sharma',
                                  phone: '+91 98765 43210',
                                  houseOrFlat: houseCtrl.text.trim(),
                                  streetOrArea: streetCtrl.text.trim(),
                                  city: 'Bengaluru',
                                  pincode: pincodeCtrl.text.trim(),
                                  landmark: landmarkCtrl.text.trim().isEmpty
                                      ? null
                                      : landmarkCtrl.text.trim(),
                                ),
                              );
                          Navigator.pop(ctx);
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
