import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF0D131D);
  static const sidebar = Color(0xFF101925);
  static const panel = Color(0xFF151F2D);
  static const line = Color(0xFF263447);
  static const blue = Color(0xFF62A8FF);
  static const muted = Color(0xFF8290A3);
  static const secondaryText = Color(0xFFB9C4D2);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: blue,
      secondary: blue,
      surface: panel,
    ),
    useMaterial3: true,
    fontFamily: 'Roboto',
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      hintStyle: const TextStyle(color: muted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: blue),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: secondaryText),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: blue,
      foregroundColor: Color(0xFF07111E),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
