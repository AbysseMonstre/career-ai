import 'package:flutter/material.dart';

/// "Aura" theme — dark violet, glassmorphism, visionOS-like depth.
class AppTheme {
  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetLight = Color(0xFFC4B5FD);
  static const Color indigo = Color(0xFF6366F1);
  static const Color cyan = Color(0xFF22D3EE);

  // semantic aliases used across screens
  static const Color primary = violet;
  static const Color accent = cyan;
  static const Color sheet = Color(0xFF1A1030); // dark surface for modals

  // base background stops for the aurora gradient
  static const Color bgTop = Color(0xFF2A1850);
  static const Color bgMid = Color(0xFF150E2B);
  static const Color bgBottom = Color(0xFF0C0820);

  static const Color ink = Colors.white;
  static const Color muted = Color(0xFFA9A3C2);
  static const Color muted2 = Color(0xFF7E7898);

  static const Color green = Color(0xFF34D399);
  static const Color amber = Color(0xFFFBBF24);
  static const Color red = Color(0xFFFB7185);

  // More transparent glass so the animated aurora shows through the panels.
  static Color glass([double o = 0.035]) => Colors.white.withValues(alpha: o);
  static Color glassBorder([double o = 0.12]) => Colors.white.withValues(alpha: o);

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: violet,
        brightness: Brightness.dark,
        primary: violet,
        secondary: cyan,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: '.SF Pro Display',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: ink,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: glass(),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: glassBorder()),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violetLight,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: glassBorder()),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: violetLight),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glass(0.06),
        hintStyle: const TextStyle(color: muted2),
        labelStyle: const TextStyle(color: muted),
        prefixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: glassBorder()),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: glassBorder()),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: violetLight, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF140C28).withValues(alpha: 0.55),
        indicatorColor: violet.withValues(alpha: 0.25),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11,
            color: s.contains(WidgetState.selected) ? Colors.white : muted2,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? Colors.white : muted2,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: glassBorder()),
    );
  }

  /// Colour for a match score 0-100.
  static Color scoreColor(int score) {
    if (score >= 70) return green;
    if (score >= 40) return amber;
    return red;
  }

  static const Gradient brandGradient =
      LinearGradient(colors: [violet, cyan], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const Gradient ctaGradient =
      LinearGradient(colors: [Color(0xFF7C3AED), indigo], begin: Alignment.topLeft, end: Alignment.bottomRight);
}
