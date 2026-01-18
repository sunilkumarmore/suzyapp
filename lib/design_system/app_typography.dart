import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
class AppTypography {


  static final tileTitle = GoogleFonts.fredoka(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

 static final tileSubtitle = GoogleFonts.fredoka(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary.withOpacity(0.75),
  );

  static final headingLarge = GoogleFonts.fredoka(
    fontSize: 44,
    fontWeight: FontWeight.w700,
    height: 1.05,
    color: AppColors.textPrimary,
  );

  static final headingSubtitle = GoogleFonts.fredoka(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.textPrimary.withOpacity(0.7),
  );

}
