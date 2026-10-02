import 'package:flutter/material.dart';

/// Centralized color palette for FreshMarket.
/// Designed for a premium, clean, food-first aesthetic:
/// - Crisp clean surfaces
/// - Deep natural emerald green accents for freshness and trust
/// - Warm coral/amber accents for deals and call-to-actions
/// - Balanced high-contrast text typography
abstract final class AppColors {
  // Brand Primary (Fresh Emerald Green)
  static const Color primary = Color(0xFF0F766E); // Deep Teal / Forest
  static const Color primaryDark = Color(0xFF0D5D57);
  static const Color primaryLight = Color(0xFF14B8A6);
  static const Color primaryContainer = Color(0xFFE6F4F1);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF042F2C);

  // Secondary (Warm Charcoal / Slate)
  static const Color secondary = Color(0xFF1F2937);
  static const Color secondaryContainer = Color(0xFFF3F4F6);
  static const Color onSecondary = Color(0xFFFFFFFF);

  // Warm Accent (Deals & Offers)
  static const Color accent = Color(
    0xFFE11D48,
  ); // Crisp Rose/Red for meat deals
  static const Color accentWarm = Color(
    0xFFF59E0B,
  ); // Amber for ratings & badges
  static const Color accentContainer = Color(0xFFFFF1F2);
  static const Color onAccent = Color(0xFFFFFFFF);

  // Neutral Backgrounds & Surfaces (Light)
  static const Color background = Color(0xFFF8FAFC); // Clean slate tint
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF1F5F9);
  static const Color surfaceBorder = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFEEF2F6);

  // Text Typography Colors
  static const Color textPrimary = Color(0xFF0F172A); // Very deep slate/black
  static const Color textSecondary = Color(0xFF475569); // Muted readable slate
  static const Color textTertiary = Color(0xFF94A3B8); // Light placeholder/hint
  static const Color textInverse = Color(0xFFFFFFFF);

  // Status & Feedback Colors
  static const Color success = Color(0xFF16A34A);
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0284C7);
  static const Color infoContainer = Color(0xFFE0F2FE);

  // Meat / Category-Specific Accent Accents
  static const Color chickenBadge = Color(0xFFF97316);
  static const Color muttonBadge = Color(0xFFB91C1C);
  static const Color fishBadge = Color(0xFF0284C7);
  static const Color porkBadge = Color(0xFFBE185D);
  static const Color groceryBadge = Color(0xFF15803D);

  // Dark Mode Tokens (Prepared for future theme toggling)
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceSubtle = Color(0xFF334155);
  static const Color darkSurfaceBorder = Color(0xFF475569);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);
}
