import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const ink = Color(0xFF163E33);
  static const sky = Color(0xFFD5F279);
  static const blue = Color(0xFF256550);
  static const navy = Color(0xFF163E33);
  static const cloud = Color(0xFFF5F6F2);
  static const muted = Color(0xFF7B857A);
  static const line = Color(0xFFE7EAE3);
  static const green = Color(0xFF28B875);
  static const orange = Color(0xFFFF9C45);
  static const lilac = Color(0xFFA789E9);
}

ThemeData buildTheme() {
  final text = GoogleFonts.manropeTextTheme();
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.sky,
      primary: AppColors.ink,
      surface: Colors.white,
      brightness: Brightness.light,
    ),
    textTheme: text.copyWith(
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.3,
        color: AppColors.ink,
      ),
      headlineLarge: text.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        color: AppColors.ink,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
        color: AppColors.ink,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyMedium: text.bodyMedium?.copyWith(
        color: AppColors.muted,
        height: 1.45,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.sky.withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          fontSize: 9,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cloud,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.sky, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    ),
  );
}
