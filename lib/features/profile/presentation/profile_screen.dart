import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Account')),
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
                    child: const Center(
                      child: Text(
                        'RS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rahul Sharma',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '+91 98765 43210 • rahul@example.com',
                          style: TextStyle(
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FreshMarket Wallet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${AppStrings.currencySymbol}210.00 Balance',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
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
                            'Ledger',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Navigation Options
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
                    subtitle: 'Track order progress and review past cuts',
                    onTap: () => context.push(AppRoutes.orders),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.location_on_outlined,
                    title: 'Saved Delivery Addresses',
                    subtitle: 'Manage home, office, and delivery pins',
                    onTap: () => context.push(AppRoutes.addresses),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.favorite_border_rounded,
                    title: 'My Wishlist',
                    subtitle: 'Saved favorites for fast re-ordering',
                    onTap: () => context.push(AppRoutes.wishlist),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.notifications_none_rounded,
                    title: 'Notification Centre',
                    subtitle: 'Order milestones, receipts & offers',
                    onTap: () => context.push(AppRoutes.notifications),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            // Support & Info Options
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
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'WhatsApp Butchery Support',
                    subtitle: 'Click-to-chat with fresh cut specialists',
                    onTap: () => context.push(AppRoutes.contactUs),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'About FreshMarket',
                    subtitle: 'Our farm sourcing and hygiene standards',
                    onTap: () => context.push(AppRoutes.aboutUs),
                  ),
                  const Divider(height: 1),
                  _buildMenuTile(
                    context,
                    icon: Icons.contact_support_outlined,
                    title: 'Contact Us',
                    subtitle: 'Customer care, feedback and grievances',
                    onTap: () => context.push(AppRoutes.contactUs),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Sign out button
            ListTile(
              shape: const RoundedRectangleBorder(
                borderRadius: AppDimensions.roundedMd,
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
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.go(AppRoutes.login);
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
