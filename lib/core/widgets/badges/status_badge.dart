import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';

enum BadgeVariant { success, warning, error, info, accent, neutral }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.variant = BadgeVariant.neutral,
    this.icon,
  });

  final String label;
  final BadgeVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    switch (variant) {
      case BadgeVariant.success:
        bg = AppColors.successContainer;
        fg = AppColors.success;
      case BadgeVariant.warning:
        bg = AppColors.warningContainer;
        fg = AppColors.warning;
      case BadgeVariant.error:
        bg = AppColors.errorContainer;
        fg = AppColors.error;
      case BadgeVariant.info:
        bg = AppColors.infoContainer;
        fg = AppColors.info;
      case BadgeVariant.accent:
        bg = AppColors.accentContainer;
        fg = AppColors.accent;
      case BadgeVariant.neutral:
        bg = AppColors.surfaceSubtle;
        fg = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppDimensions.roundedPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
