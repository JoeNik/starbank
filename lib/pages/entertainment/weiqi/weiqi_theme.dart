import 'package:flutter/material.dart';

/// 棋妙岛模块专属孟菲斯（Memphis Milano）视觉色板 + 经典护眼棋盘配色。
/// 外围 UI 严格遵循孟菲斯五条法则（暖米白底 #FDF6EC、粗黑描边 #111111、零模糊硬投影、糖果撞色）；
/// 棋盘与黑白云子保留温润榧木色与立体质感，保障长久对弈与做题的护眼辨识度。
class WqTheme {
  WqTheme._();

  // ==================== 孟菲斯基础墨色与底色 ====================
  static const Color ink = Color(0xFF111111); // 孟菲斯胶水黑：描边/硬投影/正文
  static const Color inkSoft = Color(0xFF3E3B36);
  static const Color inkFaint = Color(0xFF757067);
  static const Color cream = Color(0xFFFDF6EC); // 孟菲斯暖米白：页面主底色
  static const Color creamDeep = Color(0xFFF5E8D5);
  static const Color card = Colors.white;

  // ==================== 孟菲斯六大糖果色 ====================
  static const Color green = Color(0xFF22C3B5); // 薄荷青：主操作/安全气
  static const Color greenBright = Color(0xFF26D4C5);
  static const Color greenDeep = Color(0xFF0C6B62);
  static const Color greenSoft = Color(0xFFE0F8F5);

  static const Color sun = Color(0xFFFFD23F); // 柠檬黄：高亮/星级/贴纸
  static const Color sunDeep = Color(0xFF9E6B00);
  static const Color sunSoft = Color(0xFFFFF6D6);

  static const Color coral = Color(0xFFFF5A36); // 番茄红：警示/重要徽章
  static const Color coralSoft = Color(0xFFFFE8E2);

  static const Color pink = Color(0xFFFF7EB6); // 泡泡糖粉：装饰/主视觉贴纸
  static const Color pinkSoft = Color(0xFFFFEAF3);

  static const Color sky = Color(0xFF2D4BFF); // 钴蓝：稳重点缀/分类
  static const Color skySoft = Color(0xFFE6EAFF);

  static const Color grape = Color(0xFFB79CFF); // 淡紫：副卡/岛屿标签
  static const Color grapeSoft = Color(0xFFF2EDFF);

  // ==================== 经典护眼榧木棋盘与黑白云子 ====================
  static const Color boardA = Color(0xFFEEC27A); // 棋盘木色
  static const Color boardB = Color(0xFFDFA95C);
  static const Color line = Color(0xFF4A3018);

  static const Color stoneBlackA = Color(0xFF5C5C66);
  static const Color stoneBlackB = Color(0xFF26262E);
  static const Color stoneBlackC = Color(0xFF0C0C12);
  static const Color stoneWhiteA = Color(0xFFFFFFFF);
  static const Color stoneWhiteB = Color(0xFFF3F1EA);
  static const Color stoneWhiteC = Color(0xFFD8D4C6);
}
