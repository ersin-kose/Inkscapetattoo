import 'package:flutter/material.dart';

/// Central brand palette for easy customization.
/// Replace the default values with your brand HEX codes.
class BrandTheme {
  // Premium hero gradient (Onyx + Gold look)
  static const Color premiumStart = Color(0xFFFCD34D); // Amber 300
  static const Color premiumEnd = Color(0xFFF59E0B); // Amber 600

  // Text/icon colors on premium hero background
  static const Color onPremium = Colors.black; // good legibility on light gradient

  // Primary call-to-action (subscribe) color
  static const Color cta = Color(0xFF22C55E); // Emerald 500
  static const Color onCta = Colors.white;

  // Accent for icons/highlights
  static const Color accent = Color(0xFF34D399); // Emerald 400
}
