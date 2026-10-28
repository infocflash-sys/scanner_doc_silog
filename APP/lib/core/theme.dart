import 'package:flutter/material.dart';

class Brand {
  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF131D30);
  static const surface2 = Color(0xFF1B2740);
  static const border = Color(0xFF26344F);
  static const green = Color(0xFF22C55E);
  static const teal = Color(0xFF14B8A6);
  static const text = Color(0xFFE8EEF9);
  static const muted = Color(0xFFB4C2DC);
  static const danger = Color(0xFFF87171);
  static const warn = Color(0xFFFBBF24);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, teal],
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Brand.green,
    secondary: Brand.teal,
    surface: Brand.surface,
    error: Brand.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: Brand.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Brand.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Brand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Brand.green, width: 2),
      ),
      hintStyle: const TextStyle(color: Brand.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A3B5C),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      actionTextColor: Brand.green,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Brand.green, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.surface,
      titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
      contentTextStyle: const TextStyle(color: Brand.text, fontSize: 15, height: 1.4),
    ),
  );
}
