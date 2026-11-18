import 'package:flutter/material.dart';

/// 全局孟菲斯（Memphis Milano 1980-1988）风格主题配置类
/// 核心法则：一块一色、描一圈黑边（#111111）、往右下黑色硬投影（不模糊）、只歪装饰不歪信息
class AppTheme {
  // ==================== 孟菲斯核心色板 (Design Tokens) ====================

  /// 底色：暖米白（建议面积 35%+，让糖果色跳出来）
  static const Color cream = Color(0xFFFDF6EC);

  /// 浅米黄底色（用于次级容器或交替块）
  static const Color creamDeep = Color(0xFFF7EBD9);

  /// 胶水黑：描边、硬投影、纹样、主正文（#111111）
  static const Color ink = Color(0xFF111111);

  /// 泡泡糖粉：主角色之一，大圆、标题、主按钮（#FF7EB6）
  static const Color pink = Color(0xFFFF7EB6);

  /// 柠檬黄：三角、标签、高亮主卡、按钮（#FFD23F）
  static const Color yellow = Color(0xFFFFD23F);

  /// 薄荷青：方块、波浪线、正向状态色（#22C3B5）
  static const Color teal = Color(0xFF22C3B5);

  /// 钴蓝：半圆、点缀、最稳重的彩色（#2D4BFF）
  static const Color cobalt = Color(0xFF2D4BFF);

  /// 番茄红：小圆、强调、重要提醒（#FF5A36）
  static const Color tomato = Color(0xFFFF5A36);

  /// 淡紫：半圆、贴纸、背景块（#B79CFF）
  static const Color lilac = Color(0xFFB79CFF);

  /// 浅色糖果衬底（用于需要摆放大量阅读文字的卡片内部区域）
  static const Color pinkSoft = Color(0xFFFFEAF3);
  static const Color yellowSoft = Color(0xFFFFF6D6);
  static const Color tealSoft = Color(0xFFE0F8F5);
  static const Color cobaltSoft = Color(0xFFE6EAFF);
  static const Color tomatoSoft = Color(0xFFFFE8E2);
  static const Color lilacSoft = Color(0xFFF2EDFF);

  /// 孟菲斯六大糖果主色循环列表（相邻块取不同色）
  static const List<Color> candyColors = [
    pink,
    yellow,
    teal,
    cobalt,
    tomato,
    lilac,
  ];

  /// 孟菲斯六大浅色衬底循环列表
  static const List<Color> candySoftColors = [
    yellowSoft,
    tealSoft,
    pinkSoft,
    lilacSoft,
    cobaltSoft,
    tomatoSoft,
  ];

  // ==================== 兼容旧版字段映射 ====================

  /// 主色调：泡泡糖粉
  static const Color primary = pink;

  /// 深主色调：番茄红/深粉强调色
  static const Color primaryDark = tomato;

  /// 浅主色调：浅粉衬底
  static const Color primaryLight = pinkSoft;

  /// 次要色调：薄荷青
  static const Color secondary = teal;

  /// 页面背景色统一映射为孟菲斯暖米白 #FDF6EC
  static const Color bgPink = cream;
  static const Color bgBlue = cream;
  static const Color bgYellow = cream;

  /// 主文字颜色：孟菲斯黑 #111111
  static const Color textMain = ink;

  /// 次级文字颜色：高对比深炭灰（保持干净可读）
  static const Color textSub = Color(0xFF3E3B36);

  // ==================== 孟菲斯边框与硬投影工具 ====================

  /// 标准粗黑边框（默认 2.5px）
  static Border border({double width = 2.5, Color color = ink}) =>
      Border.all(color: color, width: width);

  /// 标准右下黑色硬投影（零模糊）
  static List<BoxShadow> hardShadow({
    double offset = 4.0,
    Color color = ink,
  }) =>
      [
        BoxShadow(
          color: color,
          offset: Offset(offset, offset),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

  /// 生成标准孟菲斯积木盒子装饰（单色底 + 粗黑边 + 硬投影）
  static BoxDecoration memphisBox({
    Color color = Colors.white,
    double radius = 16.0,
    double borderWidth = 2.5,
    double shadowOffset = 4.0,
    Color borderColor = ink,
    Color shadowColor = ink,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: shadowOffset > 0
          ? [
              BoxShadow(
                color: shadowColor,
                offset: Offset(shadowOffset, shadowOffset),
                blurRadius: 0,
              ),
            ]
          : const [],
    );
  }

  // ==================== 全局 Material 主题配置 ====================

  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: pink,
      primary: pink,
      secondary: teal,
      tertiary: yellow,
      surface: Colors.white,
      onPrimary: ink,
      onSecondary: ink,
      onSurface: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: ink, size: 22),
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 21,
        fontWeight: FontWeight.w900,
        fontFamily: 'MiSans',
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: ink, width: 2.5),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cream,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: ink, width: 3),
      ),
      titleTextStyle: const TextStyle(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        fontFamily: 'MiSans',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: yellow,
        foregroundColor: ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ink, width: 2.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          fontFamily: 'MiSans',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        side: const BorderSide(color: ink, width: 2.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          fontFamily: 'MiSans',
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ink, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ink, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: cobalt, width: 2.5),
      ),
      labelStyle: const TextStyle(color: textSub, fontWeight: FontWeight.w700),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: yellowSoft,
      selectedColor: yellow,
      side: const BorderSide(color: ink, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(
        color: ink,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: ink,
      thickness: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: yellow,
      contentTextStyle: const TextStyle(
        color: ink,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ink, width: 2.5),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    fontFamily: 'MiSans',
  );
}
