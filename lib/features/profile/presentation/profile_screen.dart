import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../auth/data/auth_provider.dart';
import '../../wallet/data/wallet_repository.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final user = ref.watch(currentUserProvider);
    final walletBalanceAsync = ref.watch(walletBalanceProvider);

    final profile = profileAsync.value;
    final displayName = (profile != null && profile.fullName.isNotEmpty)
        ? profile.fullName
        : (user?.email?.split('@').first ?? 'FreshMarket Customer');
    final displayEmail = profile?.email ?? user?.email ?? 'No email';
    final displayPhone = (profile?.phone?.isNotEmpty == true)
        ? profile!.phone!
        : (user?.userMetadata?['phone'] as String? ?? 'No phone added');

    final initials = displayName
        .trim()
        .split(' ')
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .take(2)
        .join();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile Name',
            onPressed: () => _showEditProfileDialog(context, ref, displayName),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.lg),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // User Profile Card
            Container(
              padding: const EdgeInsets.all(AppDimensions.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: AppColors.surfaceBorder),
                boxShadow: AppDimensions.cardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials.isNotEmpty ? initials : 'FM',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
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
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$displayPhone • $displayEmail',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            // Wallet Quick Banner
            InkWell(
              onTap: () => context.push(AppRoutes.wallet),
              borderRadius: AppDimensions.roundedMd,
              child: Container(
                padding: const EdgeInsets.all(AppDimensions.md),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                  ),
                  borderRadius: AppDimensions.roundedMd,
                  boxShadow: AppDimensions.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FreshMarket Wallet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          walletBalanceAsync.when(
                            loading: () => const Text(
                              '₹... Balance',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            error: (_, _) => const Text(
                              '₹0.00 Balance',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            data: (bal) => Text(
                              '${AppStrings.currencySymbol}${bal.toStringAsFixed(2)} Balance',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppDimensions.roundedPill,
                      ),
                      child: const Row(
                        children: [
                          Text(
                            'View',
                            style: TextStyle(
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 12,
                            color: Color(0xFF0F766E),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Account & Preferences Group
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  _buildMenuTile(
                    context,
                    icon: Icons.receipt_long_outlined,
                    title: 'My Orders',
                    subtitle: 'Track live orders & butchery preparation',
                    onTap: () => context.push(AppRoutes.orders),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.favorite_border_rounded,
                    title: 'Favorite Cuts',
                    subtitle: 'Quick re-order your preferred meats',
                    onTap: () => context.push(AppRoutes.wishlist),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Delivery Addresses',
                    subtitle: 'Manage home & workplace delivery points',
                    onTap: () => context.push(AppRoutes.addresses),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    subtitle: 'Offers, dispatch alerts, and reminders',
                    onTap: () => context.push(AppRoutes.notifications),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Support & Information Group
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  _buildMenuTile(
                    context,
                    icon: Icons.support_agent_rounded,
                    title: 'Contact Us',
                    subtitle: 'Direct WhatsApp and Butchery Care Helpline',
                    onTap: () => context.push(AppRoutes.contactUs),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'About FreshMarket',
                    subtitle: 'Our cold-chain, butchery, & safety promise',
                    onTap: () => context.push(AppRoutes.aboutUs),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Logout Button
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: AppDimensions.roundedMd,
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
              tileColor: AppColors.surface,
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: const Text(
                'Sign Out',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text(
                      'Are you sure you want to sign out of FreshMarket?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await ref
                              .read(authNotifierProvider.notifier)
                              .signOut();
                          if (context.mounted) {
                            context.go(AppRoutes.login);
                          }
                        },
                        child: const Text(
                          'Sign Out',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppDimensions.xl),

            // Version info
            const Text(
              'FreshMarket Customer App • v1.0.0 (Build 1)',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppDimensions.xxxl),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    final nameCtrl = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Full Name'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Full Name',
            hintText: 'Enter your full name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(profileRepositoryProvider)
                      .updateProfile(fullName: newName);
                  ref.invalidate(userProfileProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating profile: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
