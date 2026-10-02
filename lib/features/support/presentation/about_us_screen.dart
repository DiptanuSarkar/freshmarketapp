import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('About FreshMarket')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.lg),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Brand Statement
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDimensions.xl),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: AppDimensions.roundedLg,
                border: Border.all(
                  color: AppColors.primaryLight.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.md),
                  Text(
                    'Reinventing Fresh Meat & Daily Staples',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.sm),
                  Text(
                    'At ${AppStrings.appName}, we believe everyone deserves meat and food that is strictly antibiotic-free, ethically raised, and processed with surgical hygiene.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primaryDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.xl),

            // Sourcing Pillars
            const Text(
              'Our Five Freshness Pillars',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.md),

            _buildPillarCard(
              icon: Icons.shield_outlined,
              title: 'Antibiotic Residue-Free',
              description: 'We test every flock for zero antibiotic residue, growth hormones, and artificial chemicals.',
            ),
            const SizedBox(height: AppDimensions.sm),

            _buildPillarCard(
              icon: Icons.ac_unit_rounded,
              title: '0° - 4° C Strict Cold Chain',
              description: 'Never frozen, never thawed. Our cuts are maintained at natural refrigerated temperatures from dispatch to door.',
            ),
            const SizedBox(height: AppDimensions.sm),

            _buildPillarCard(
              icon: Icons.sailing_outlined,
              title: 'Daily Harbor Catch',
              description: 'Fish sourced directly from verified coastal day-boats. Delivered within 24 hours of catch.',
            ),
            const SizedBox(height: AppDimensions.sm),

            _buildPillarCard(
              icon: Icons.cleaning_services_outlined,
              title: 'Surgical Hygiene & RO Cleansing',
              description: 'Processed in state-of-the-art biosecure butchery hubs utilizing RO water wash and vacuum sealing.',
            ),
            const SizedBox(height: AppDimensions.sm),

            _buildPillarCard(
              icon: Icons.delivery_dining_outlined,
              title: 'Express 90-120 Min Delivery',
              description: 'Dedicated delivery riders equipped with temperature-insulated chilled carry bags.',
            ),
            const SizedBox(height: AppDimensions.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildPillarCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
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
            decoration: const BoxDecoration(
              color: AppColors.surfaceSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppDimensions.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
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
    );
  }
}
