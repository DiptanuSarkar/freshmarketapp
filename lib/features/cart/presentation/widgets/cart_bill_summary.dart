import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../shared/providers/cart_provider.dart';

class CartBillSummary extends StatelessWidget {
  const CartBillSummary({super.key, required this.cartState});

  final CartState cartState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(color: AppColors.surfaceBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bill Summary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.md),

          // Item Total
          _buildSummaryRow(
            'Item Total',
            '${AppStrings.currencySymbol}${cartState.subtotal.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 8),

          // Product Savings
          if (cartState.productSavings > 0) ...[
            _buildSummaryRow(
              'Product Discount',
              '-${AppStrings.currencySymbol}${cartState.productSavings.toStringAsFixed(0)}',
              valueColor: AppColors.success,
            ),
            const SizedBox(height: 8),
          ],

          // Coupon Discount
          if (cartState.couponDiscount > 0) ...[
            _buildSummaryRow(
              'Coupon (${cartState.appliedCouponCode})',
              '-${AppStrings.currencySymbol}${cartState.couponDiscount.toStringAsFixed(0)}',
              valueColor: AppColors.success,
            ),
            const SizedBox(height: 8),
          ],

          // Delivery Fee
          _buildSummaryRow(
            'Delivery Partner Fee',
            cartState.deliveryFee == 0
                ? 'FREE'
                : '${AppStrings.currencySymbol}${cartState.deliveryFee.toStringAsFixed(0)}',
            valueColor: cartState.deliveryFee == 0
                ? AppColors.success
                : AppColors.textPrimary,
          ),

          if (cartState.deliveryFee > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: AppDimensions.roundedXs,
              ),
              child: Text(
                'Add ₹${(499 - cartState.subtotal).toStringAsFixed(0)} more for FREE Delivery!',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],

          const Divider(height: 24),

          // Total Payable
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'To Pay',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${AppStrings.currencySymbol}${cartState.totalPayable.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
