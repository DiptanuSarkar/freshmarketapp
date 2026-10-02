import 'package:flutter/material.dart';

/// Centralized layout, padding, elevation, and border radius dimensions.
abstract final class AppDimensions {
  // Spacing / Margins / Paddings
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
  static const double huge = 48.0;

  // Border Radii
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusPill = 999.0;

  // BorderRadius objects for convenience
  static const BorderRadius roundedXs = BorderRadius.all(
    Radius.circular(radiusXs),
  );
  static const BorderRadius roundedSm = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius roundedMd = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius roundedLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius roundedXl = BorderRadius.all(
    Radius.circular(radiusXl),
  );
  static const BorderRadius roundedPill = BorderRadius.all(
    Radius.circular(radiusPill),
  );

  // Elevations & Soft Shadows
  static const double elevationLow = 1.0;
  static const double elevationMedium = 3.0;
  static const double elevationHigh = 6.0;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A000000),
      offset: Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  // Component Sizes
  static const double buttonHeight = 48.0;
  static const double buttonHeightSm = 36.0;
  static const double inputHeight = 48.0;
  static const double bottomNavHeight = 64.0;
  static const double appHeaderHeight = 60.0;
  static const double productCardWidth = 164.0;
  static const double productCardImageHeight = 120.0;
}
