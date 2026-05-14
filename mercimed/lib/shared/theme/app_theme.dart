import 'package:flutter/material.dart';

class AppTheme {
  // Design tokens
  static const Color background  = Color(0xFFC8D8D4);
  static const Color surface     = Color(0xFFEFF4F3);
  static const Color primaryDark = Color(0xFF1A2E35);
  static const Color teal        = Color(0xFF2D6B6B);
  static const Color muted       = Color(0xFF6B8A8A);
  static const Color white       = Colors.white;

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          brightness: Brightness.light,
        ).copyWith(
          primary: primaryDark,
          surface: surface,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: primaryDark),
          titleTextStyle: TextStyle(
            color: primaryDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: surface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryDark,
            foregroundColor: white,
            minimumSize: const Size(double.infinity, 54),
            shape: const StadiumBorder(),
            elevation: 0,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: teal),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD8E4E2),
          space: 0,
          thickness: 1,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: primaryDark,
            fontWeight: FontWeight.w700,
            fontSize: 32,
          ),
          headlineMedium: TextStyle(
            color: primaryDark,
            fontWeight: FontWeight.w700,
            fontSize: 26,
          ),
          titleLarge: TextStyle(
            color: primaryDark,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
          titleMedium: TextStyle(
            color: primaryDark,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          bodyLarge: TextStyle(color: primaryDark, fontSize: 16),
          bodyMedium: TextStyle(color: primaryDark, fontSize: 14),
          bodySmall: TextStyle(color: muted, fontSize: 12),
          labelSmall: TextStyle(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );
}
