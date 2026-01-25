import 'package:flutter/material.dart';

class AppTheme {
  // Cute Pastel Palette
  static const Color primary = Color(0xFFFF9A9E); // Soft Pink
  static const Color primaryDark = Color(0xFFF06292);
  static const Color primaryLight = Color(0xFFFFCDD2); // Light Pink
  static const Color secondary =
      Color(0xFFA1887F); // Warm Brown (for text/details)

  static const Color bgPink = Color(0xFFFFF1F2);
  static const Color bgBlue = Color(0xFFE0F2F1);
  static const Color bgYellow = Color(0xFFFFF9DB);

  static const Color textMain = Color(0xFF4E342E);
  static const Color textSub = Color(0xFF8D6E63);

  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bgPink,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: Colors.lightBlue.shade200,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: textMain,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        fontFamily: 'MiSans',
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(color: primary.withOpacity(0.1), width: 2),
      ),
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),
    fontFamily: 'MiSans',
  );
}
