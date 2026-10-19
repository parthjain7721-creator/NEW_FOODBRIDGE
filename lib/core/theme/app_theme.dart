import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Brand colors inspired by the FoodBridge logo.
  static const Color navy = Color(0xFF1F3557);
  static const Color darkNavy = Color(0xFF172A45);

  static const Color forestGreen = Color(0xFF356B4D);
  static const Color mediumGreen = Color(0xFF5C8E61);
  static const Color sageGreen = Color(0xFFA7C49A);

  static const Color lightGreen = Color(0xFFEAF3E8);
  static const Color offWhite = Color(0xFFF8FAF8);
  static const Color charcoal = Color(0xFF27332D);
  static const Color mutedText = Color(0xFF718078);

  static const Color warning = Color(0xFFE6A23C);
  static const Color error = Color(0xFFC94C4C);
  static const Color success = Color(0xFF39815A);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: offWhite,
    colorScheme: ColorScheme.fromSeed(
      seedColor: forestGreen,
      primary: forestGreen,
      secondary: navy,
      surface: white,
      error: error,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: offWhite,
      foregroundColor: charcoal,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: charcoal,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: charcoal,
        fontSize: 34,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      displayMedium: TextStyle(
        color: charcoal,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      headlineLarge: TextStyle(
        color: charcoal,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        color: charcoal,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        color: charcoal,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: charcoal,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: charcoal,
        fontSize: 16,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: mutedText,
        fontSize: 14,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        color: white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      hintStyle: const TextStyle(
        color: mutedText,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        color: mutedText,
        fontSize: 14,
      ),
      prefixIconColor: forestGreen,
      suffixIconColor: mutedText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFFDCE6DE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: forestGreen,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: error,
          width: 1.5,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: forestGreen,
        foregroundColor: white,
        minimumSize: const Size(double.infinity, 54),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: forestGreen,
        minimumSize: const Size(double.infinity, 54),
        side: const BorderSide(
          color: forestGreen,
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: forestGreen,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: lightGreen,
      selectedColor: forestGreen,
      labelStyle: const TextStyle(
        color: forestGreen,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static const Color white = Color(0xFFFFFFFF);
}