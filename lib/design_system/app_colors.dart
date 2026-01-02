import 'package:flutter/material.dart';


class AppColors {
  static const background = Color(0xFFF7EFE3); // warm cream
  static const surface    = Color(0xFFFFFFFF);

  // Text
  static const textPrimary   = Color(0xFF2F2F2F);
  static const textSecondary = Color(0xFF5A5A5A);

  // Tile colors (like screenshots)
  static const tileYellow = Color(0xFFF6C463);
  static const tileBlue   = Color(0xFF86C6E6);

  // Choice colors (green/red/purple)
  static const choiceGreen  = Color(0xFF57B37A);
  static const choiceRed    = Color(0xFFE35A55);
  static const choicePurple = Color(0xFF7B63E6);

  static const primaryYellow = tileYellow;
static const primaryBlue   = tileBlue;
static const accentCoral   = choiceRed;

  // Accents
  static const outline = Color(0x1A000000); // 10% black
  static const shadow  = Color(0x14000000); // ~8% black
}

BoxDecoration pillCard(Color color) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(28),
  boxShadow: const [
    BoxShadow(
      color: AppColors.shadow,
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ],
);
