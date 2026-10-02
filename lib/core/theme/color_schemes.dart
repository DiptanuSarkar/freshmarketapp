import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

abstract final class AppColorSchemes {
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.accent,
    onTertiary: AppColors.onAccent,
    tertiaryContainer: AppColors.accentContainer,
    onTertiaryContainer: AppColors.accent,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.error,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceSubtle,
    outline: AppColors.surfaceBorder,
    outlineVariant: AppColors.divider,
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryLight,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: AppColors.onPrimary,
    secondary: AppColors.darkSurfaceSubtle,
    onSecondary: AppColors.darkTextPrimary,
    secondaryContainer: AppColors.darkSurface,
    onSecondaryContainer: AppColors.darkTextPrimary,
    tertiary: AppColors.accent,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFF4C0519),
    onTertiaryContainer: Color(0xFFFFD1D8),
    error: Color(0xFFF87171),
    onError: Colors.white,
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFECACA),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkTextPrimary,
    surfaceContainerHighest: AppColors.darkSurfaceSubtle,
    outline: AppColors.darkSurfaceBorder,
    outlineVariant: AppColors.darkSurfaceBorder,
  );
}
