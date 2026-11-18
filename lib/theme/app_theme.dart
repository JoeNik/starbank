import 'package:flutter/material.dart';

/// 全局中世纪现代（017 · Mid-Century Modern, 1945–1965）风格主题配置类
/// 致敬 Saul Bass、Paul Rand、Alexander Girard、Charles & Ray Eames、George Nelson、Reid Miles (Blue Note)
/// 核心五条规则：
/// 01. 剪刀代替尺子：每一块都是一张剪出来、能拿起来的纸，无粗黑描边，大字/装饰微斜 ±2°~3°
/// 02. 影子 = 高度 (h)：暖棕投影 #3A1C0C，偏移 (0.5h, h)，模糊 0.8h，浓度 0.3 - 0.004h
/// 03. 叠印出第三色：黄 × 粉 = 橘 #F55F1E，黄 × 绿松石 = 橄榄绿 #1F8B1E，粉 × 绿松石 = 孔雀蓝 #1E566D
/// 04. 原子时代形状：腰果、回旋镖、星芒、原子轨道、球与棍、月牙边角料、调色板
/// 05. 暖白纸 + 糖果色：暖白纸 #FBF3E3 占 40%，番茄红、向日葵黄、Girard 粉、绿松石、钴蓝主次分明，墨色只给字和细辐条
class AppTheme {
  // ==================== 中世纪现代核心色板 (Design Tokens) ====================

  /// 暖白纸：底色（建议面积 40%，#FBF3E3）
  static const Color cream = Color(0xFFFBF3E3);

  /// 次级暖卡纸色（用于层叠纸片与次级背景，#F2E5CE）
  static const Color creamDeep = Color(0xFFF2E5CE);

  /// 亮暖白卡纸（用于主信息卡片表面，#FFFDF8）
  static const Color paperWhite = Color(0xFFFFFDF8);

  /// 墨色：文字、球钟辐条、唱臂细线（建议面积 4%，#1E1B19）
  static const Color ink = Color(0xFF1E1B19);

  /// 说明文字：温暖灰棕小字（#8A7F72）
  static const Color textSub = Color(0xFF8A7F72);

  /// 暖棕影子：所有纸片的高度投影色（#3A1C0C，严禁使用纯黑投影）
  static const Color shadowBrown = Color(0xFF3A1C0C);

  /// 番茄红：第一主角、主按钮、重点强调（建议面积 14%，#F2542D）
  static const Color tomato = Color(0xFFF2542D);

  /// 向日葵黄：太阳、高光、叠印的“浅色”（建议面积 14%，#FFC62E）
  static const Color yellow = Color(0xFFFFC62E);

  /// Girard 粉：大块的背景剪纸形状与温柔主卡（建议面积 12%，#F57AA8）
  static const Color pink = Color(0xFFF57AA8);

  /// 绿松石：第二主角、正向状态、唱机/银行主色（建议面积 10%，#1FB3A6）
  static const Color teal = Color(0xFF1FB3A6);

  /// 钴蓝：点睛、星芒、Blue Note 爵士蓝（建议面积 6%，#2F6BD8）
  static const Color cobalt = Color(0xFF2F6BD8);

  // ==================== 叠印第三色 (Multiply Overprint) ====================

  /// 黄 × 粉 叠印暖橘（#F55F1E）
  static const Color overprintOrange = Color(0xFFF55F1E);

  /// 黄 × 绿松石 叠印橄榄绿（#1F8B1E）
  static const Color overprintOlive = Color(0xFF1F8B1E);

  /// 粉 × 绿松石 叠印深孔雀蓝（#1E566D）
  static const Color overprintPetrol = Color(0xFF1E566D);

  /// 兼容字段：将 lilac 映射为叠印暖橘/珊瑚色，契合中世纪现代色盘
  static const Color lilac = overprintOrange;

  /// 浅色糖果纸衬底（用于需要大面积展示详细文字的剪纸内卡）
  static const Color tomatoSoft = Color(0xFFFCE6DF);
  static const Color yellowSoft = Color(0xFFFFF4D2);
  static const Color pinkSoft = Color(0xFFFDE8F0);
  static const Color tealSoft = Color(0xFFDDF5F2);
  static const Color cobaltSoft = Color(0xFFE3ECFA);
  static const Color lilacSoft = Color(0xFFFDE9DC);

  /// 中世纪现代六大彩纸主色循环列表（按主次节奏排列）
  static const List<Color> candyColors = [
    tomato,
    yellow,
    teal,
    pink,
    cobalt,
    overprintOrange,
  ];

  /// 中世纪现代浅色卡纸循环列表
  static const List<Color> candySoftColors = [
    yellowSoft,
    tealSoft,
    tomatoSoft,
    pinkSoft,
    cobaltSoft,
    lilacSoft,
  ];

  // ==================== 兼容旧版字段映射 ====================

  /// 主色调：中世纪现代第一主角「番茄红 #F2542D」
  static const Color primary = tomato;

  /// 深主色调：深孔雀蓝 / 叠印橘
  static const Color primaryDark = overprintPetrol;

  /// 浅主色调：浅暖纸粉
  static const Color primaryLight = tomatoSoft;

  /// 次要色调：绿松石 #1FB3A6
  static const Color secondary = teal;

  /// 页面背景色统一映射为暖白纸 #FBF3E3
  static const Color bgPink = cream;
  static const Color bgBlue = cream;
  static const Color bgYellow = cream;

  /// 主文字颜色：墨色 #1E1B19
  static const Color textMain = ink;

  // ==================== 规则 02：影子 = 高度 (Shadow = Elevation h) ====================

  /// 根据纸片离桌面的高度 [h]（貼着 4、常规 8~10、拿起 14、在手里 30、按下 0）计算暖棕影子
  /// 公式：偏移 (0.5h, h)，模糊 0.8h，浓度 0.30 - 0.004h，颜色 #3A1C0C
  static List<BoxShadow> paperShadow({
    double h = 8.0,
    Color color = shadowBrown,
  }) {
    if (h <= 0.1) return const [];
    final alpha = (0.28 - 0.004 * h).clamp(0.08, 0.30);
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        offset: Offset(h * 0.5, h),
        blurRadius: h * 0.85,
        spreadRadius: 0,
      ),
    ];
  }

  /// 细微的剪纸纸张切口边缘（非孟菲斯粗黑描边，仅给浅色纸片提供纸张厚度感）
  static Border border({
    double width = 1.0,
    Color color = const Color(0x1E3A1C0C),
  }) =>
      Border.all(color: color == ink ? const Color(0x223A1C0C) : color, width: width.clamp(0.5, 1.2));

  /// 兼容旧调用：将原硬投影自动转换为中世纪现代暖棕高度投影
  static List<BoxShadow> hardShadow({
    double offset = 6.0,
    Color color = shadowBrown,
  }) =>
      paperShadow(h: offset * 1.8, color: shadowBrown);

  /// 生成中世纪现代剪纸盒子装饰（无粗黑描边 + 暖棕高度影子）
  static BoxDecoration memphisBox({
    Color color = paperWhite,
    double radius = 16.0,
    double borderWidth = 0.0,
    double shadowOffset = 5.0,
    Color borderColor = const Color(0x1E3A1C0C),
    Color shadowColor = shadowBrown,
  }) {
    return BoxDecoration(
      color: color == Colors.white ? paperWhite : color,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius * 0.82),
        bottomLeft: Radius.circular(radius * 0.88),
        bottomRight: Radius.circular(radius * 1.06),
      ),
      border: Border.all(
        color: const Color(0x1A3A1C0C),
        width: 1.0,
      ),
      boxShadow: paperShadow(h: shadowOffset * 1.8),
    );
  }

  // ==================== 全局 Material 主题配置 ====================

  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: tomato,
      primary: tomato,
      secondary: teal,
      tertiary: yellow,
      surface: paperWhite,
      onPrimary: paperWhite,
      onSecondary: paperWhite,
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
        letterSpacing: 0.6,
      ),
    ),
    cardTheme: CardThemeData(
      color: paperWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x183A1C0C), width: 1.0),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cream,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x263A1C0C), width: 1.2),
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
        backgroundColor: tomato,
        foregroundColor: paperWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
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
        backgroundColor: paperWhite,
        foregroundColor: ink,
        side: const BorderSide(color: Color(0x333A1C0C), width: 1.2),
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
      fillColor: paperWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x283A1C0C), width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x283A1C0C), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: tomato, width: 2.0),
      ),
      labelStyle: const TextStyle(color: textSub, fontWeight: FontWeight.w700),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: creamDeep,
      selectedColor: tomato,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(
        color: ink,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x1F3A1C0C),
      thickness: 1.0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: const TextStyle(
        color: cream,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    fontFamily: 'MiSans',
  );
}
