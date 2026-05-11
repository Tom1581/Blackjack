import 'package:flutter/material.dart';

class AppColors {
  // Felt backgrounds
  static const bg = Color(0xFF081F0E);
  static const table = Color(0xFF1B5E2E);
  static const tableDark = Color(0xFF145222);

  // Wood tones (top/bottom rails)
  static const wood = Color(0xFF2C1208);
  static const woodLight = Color(0xFF4A2010);

  // Gold accents
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF0CB45);
  static const goldDim = Color(0xFF8A7020);
  static const accent = Color(0xFFD4AF37);
  static const accentLight = Color(0xFFF0CB45);

  // Cards & surfaces
  static const surface = Color(0xFF0E2218);
  static const cardFace = Colors.white;
  static const cardBack = Color(0xFF1A3D9A);

  // Suit colors
  static const hearts = Color(0xFFCC2222);
  static const diamonds = Color(0xFFCC2222);
  static const clubs = Color(0xFF111111);
  static const spades = Color(0xFF111111);

  // Count signal colors
  static const favorable = Color(0xFF4ade80);
  static const unfavorable = Color(0xFFf87171);
  static const neutral = Color(0xFFb8c8d4);

  // Action button fill colors
  static const btnStand = Color(0xFF6B1A1A);
  static const btnSplit = Color(0xFF7A4E0A);
  static const btnDouble = Color(0xFF0D3E74);
  static const btnHit = Color(0xFF155225);

  // Chip colors (red, green, blue, black, purple)
  static const chipColors = [
    Color(0xFFCC2222),
    Color(0xFF1E6B32),
    Color(0xFF1155BB),
    Color(0xFF1A1A1A),
    Color(0xFF6A1B9A),
  ];
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.gold,
      secondary: AppColors.goldLight,
    ),
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.gold,
        fontSize: 48,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
      titleLarge: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
      bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      bodyMedium: TextStyle(color: AppColors.neutral, fontSize: 14),
      labelLarge: TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.wood,
        minimumSize: const Size(120, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.gold;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.goldDim;
        }
        return null;
      }),
    ),
  );
}
