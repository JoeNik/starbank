import 'package:flutter/material.dart';

/// 棋妙岛模块专属视觉（国潮卡通，见 PRD 第 8 章）。
/// 与宿主 AppTheme 完全隔离：模块内组件只读这里的颜色，
/// 不依赖也不污染宿主主题。
class WqTheme {
  WqTheme._();

  static const Color ink = Color(0xFF23324D); // 靛蓝：文字/边框
  static const Color inkSoft = Color(0xFF5F6F8F);
  static const Color inkFaint = Color(0xFF93A0B8);
  static const Color cream = Color(0xFFFFF7EA); // 米白：页面背景
  static const Color creamDeep = Color(0xFFFBEED8);
  static const Color card = Colors.white;

  static const Color green = Color(0xFF34B37E); // 竹绿：主操作
  static const Color greenBright = Color(0xFF3FC98B);
  static const Color greenDeep = Color(0xFF1E8F63);
  static const Color greenSoft = Color(0xFFE4F6EC);

  static const Color sun = Color(0xFFFFC53D); // 暖黄：提示/庆祝
  static const Color sunDeep = Color(0xFFE89B1C);
  static const Color sunSoft = Color(0xFFFFF1D6);

  static const Color coral = Color(0xFFFF7A59); // 珊瑚：仅庆祝，不用于错误
  static const Color coralSoft = Color(0xFFFFE7DE);
  static const Color sky = Color(0xFF6EC6FF);
  static const Color skySoft = Color(0xFFE3F3FF);
  static const Color grape = Color(0xFF9B8CFF);
  static const Color grapeSoft = Color(0xFFEEEBFF);

  static const Color boardA = Color(0xFFEEC27A); // 棋盘木色
  static const Color boardB = Color(0xFFDFA95C);
  static const Color line = Color(0xFF7C5230);

  static const Color stoneBlackA = Color(0xFF5C5C66);
  static const Color stoneBlackB = Color(0xFF26262E);
  static const Color stoneBlackC = Color(0xFF0C0C12);
  static const Color stoneWhiteA = Color(0xFFFFFFFF);
  static const Color stoneWhiteB = Color(0xFFF3F1EA);
  static const Color stoneWhiteC = Color(0xFFD8D4C6);
}
