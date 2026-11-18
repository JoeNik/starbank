import 'package:flutter/material.dart';

/// 棋妙岛模块专属「017 · 中世纪现代 (Mid-Century Modern, 1945–1965)」视觉色板 + 经典护眼棋盘配色。
/// 外围 UI 遵循中世纪现代五条规则（暖白纸 #FBF3E3、无粗黑描边剪纸边、暖棕高度影子 #3A1C0C、糖果色与叠印）；
/// 棋盘与黑白云子保留温润榧木色与立体质感，保障长久对弈与做题的护眼辨识度。
class WqTheme {
  WqTheme._();

  // ==================== 中世纪现代基础墨色与暖白纸 ====================
  static const Color ink = Color(0xFF1E1B19); // 中世纪现代墨色：文字、细辐条
  static const Color inkSoft = Color(0xFF5C5349);
  static const Color inkFaint = Color(0xFF8A7F72);
  static const Color shadowBrown = Color(0xFF3A1C0C); // 暖深棕：所有纸片高度投影色

  static const Color cream = Color(0xFFFBF3E3); // 暖白纸：页面主底色（40%面积）
  static const Color creamDeep = Color(0xFFF2E5CE); // 次级暖卡纸
  static const Color card = Color(0xFFFFFDF8); // 亮暖白卡纸表面

  // ==================== 中世纪现代五主色 + 叠印第三色 ====================
  static const Color green = Color(0xFF1FB3A6); // 绿松石：第二主角/安全气
  static const Color greenBright = Color(0xFF28C4B6);
  static const Color greenDeep = Color(0xFF11756C);
  static const Color greenSoft = Color(0xFFDDF5F2);

  static const Color sun = Color(0xFFFFC62E); // 向日葵黄：太阳/高光/浅色叠印
  static const Color sunDeep = Color(0xFF9E6B00);
  static const Color sunSoft = Color(0xFFFFF4D2);

  static const Color coral = Color(0xFFF2542D); // 番茄红：第一主角/主按钮/警示
  static const Color coralSoft = Color(0xFFFCE6DF);

  static const Color pink = Color(0xFFF57AA8); // Girard 粉：大块背景剪纸形状
  static const Color pinkSoft = Color(0xFFFDE8F0);

  static const Color sky = Color(0xFF2F6BD8); // 钴蓝：点睛/星芒
  static const Color skySoft = Color(0xFFE3ECFA);

  static const Color grape = Color(0xFFF55F1E); // 叠印暖橘（黄×粉）
  static const Color grapeSoft = Color(0xFFFDE9DC);

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

  // ==================== 规则 02：影子 = 高度 (Shadow = Elevation h) ====================

  /// 根据纸片离桌面的高度 [h]（贴着 4、常规 8~10、拿起 14、按下 0）生成暖棕投影
  static List<BoxShadow> paperShadow({double h = 8.0}) {
    if (h <= 0.1) return const [];
    final alpha = (0.28 - 0.004 * h).clamp(0.08, 0.28);
    return [
      BoxShadow(
        color: shadowBrown.withValues(alpha: alpha),
        offset: Offset(h * 0.5, h),
        blurRadius: h * 0.85,
        spreadRadius: 0,
      ),
    ];
  }

  /// 纸片微切口边缘（非孟菲斯粗黑描边）
  static Border border({double width = 1.0}) => Border.all(
        color: const Color(0x223A1C0C),
        width: width.clamp(0.5, 1.2),
      );
}
