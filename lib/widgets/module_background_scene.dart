import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 各功能模块的中世纪现代（017 Mid-Century Modern）背景主题枚举
enum ModuleBackgroundTheme {
  home,
  bank,
  shop,
  entertainment,
  record,
}

/// 017 · 中世纪现代 (Mid-Century Modern, 1945–1965) 剪纸舞台背景组件
/// 核心设计：
/// 1. 遵循五条规则：暖白纸 #FBF3E3 + 剪刀边有机几何（腰果肾形、回旋镖、太阳圆、星芒、Nelson 原子球钟）+ 暖棕高度影子 #3A1C0C + Multiply 叠印第三色。
/// 2. 性能大优化 + Q 弹入场：移除原本 36 秒无限循环 60fps 全屏重绘！仅在页面首次展示或切换 Tab 激活时执行一次 760ms 的 `Curves.elasticOut` 剪纸落桌 Q 弹动画，落定后由 `RepaintBoundary` 缓存为静态 GPU 纹理，列表滚动与交互时 0 重绘开销。
class ModuleBackgroundScene extends StatefulWidget {
  final ModuleBackgroundTheme theme;

  const ModuleBackgroundScene({
    super.key,
    required this.theme,
  });

  @override
  State<ModuleBackgroundScene> createState() => _ModuleBackgroundSceneState();
}

class _ModuleBackgroundSceneState extends State<ModuleBackgroundScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dropController;
  late final Animation<double> _dropCurve;
  bool _lastTickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _dropCurve = CurvedAnimation(
      parent: _dropController,
      curve: Curves.elasticOut,
    );
    _dropController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.of(context);
    if (tickerEnabled && !_lastTickerEnabled) {
      // 从其他 Tab 切换回来时，执行一次轻盈的纸片 Q 弹落桌动画
      _dropController.forward(from: 0);
    }
    _lastTickerEnabled = tickerEnabled;
  }

  @override
  void didUpdateWidget(covariant ModuleBackgroundScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) {
      _dropController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: ColoredBox(
          color: AppTheme.cream,
          child: AnimatedBuilder(
            animation: _dropCurve,
            builder: (context, _) {
              return CustomPaint(
                size: Size.infinite,
                painter: _MidCenturyCutPaperPainter(
                  theme: widget.theme,
                  dropProgress: _dropCurve.value,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 中世纪现代剪纸画笔：
/// 绘制剪纸腰果/肾形、回旋镖、叠印太阳圆、原子球钟辐条与钴蓝星芒
class _MidCenturyCutPaperPainter extends CustomPainter {
  final ModuleBackgroundTheme theme;

  /// 纸片从桌面外落定到桌面的 Q 弹进度（0.0 -> 1.0，带轻微超调）
  final double dropProgress;

  _MidCenturyCutPaperPainter({
    required this.theme,
    required this.dropProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 纸片落地缩放与微旋（模拟风格指南：纸片抛上桌，落地轻压回正）
    final settle = (1.0 - dropProgress);
    final paperLift = 1.0 + settle * 0.08;
    final paperTilt = settle * 0.05;

    canvas.save();
    canvas.translate(w * 0.5, h * 0.25);
    canvas.scale(paperLift);
    canvas.rotate(paperTilt);
    canvas.translate(-w * 0.5, -h * 0.25);

    switch (theme) {
      case ModuleBackgroundTheme.home:
        // 右上：Girard 粉腰果肾形 + 向日葵黄太阳圆（交叠处产生 #F55F1E 暖橘叠印）
        _drawKidneyPaper(
          canvas,
          center: Offset(w * 0.86, h * 0.11),
          rx: 84,
          ry: 62,
          angle: -0.22,
          color: AppTheme.pink.withValues(alpha: 0.32),
          elevationH: 8,
        );
        _drawCutSunPaper(
          canvas,
          center: Offset(w * 0.72, h * 0.15),
          radius: 44,
          color: AppTheme.yellow.withValues(alpha: 0.44),
          overprint: true,
        );
        // 左中：绿松石回旋镖
        _drawBoomerangPaper(
          canvas,
          center: Offset(w * 0.12, h * 0.42),
          scale: 68,
          angle: 0.35,
          color: AppTheme.teal.withValues(alpha: 0.26),
          elevationH: 6,
        );
        // 右下：George Nelson 原子球钟局部
        _drawBallClock(
          canvas,
          center: Offset(w * 0.88, h * 0.78),
          radius: 46,
        );
        // 左上点睛：钴蓝八芒星
        _drawStarburst(
          canvas,
          center: Offset(w * 0.14, h * 0.16),
          outerR: 18,
          color: AppTheme.cobalt.withValues(alpha: 0.60),
        );
        break;

      case ModuleBackgroundTheme.bank:
        // 右上：绿松石大肾形 + 向日葵黄圆（叠印橄榄绿）
        _drawKidneyPaper(
          canvas,
          center: Offset(w * 0.84, h * 0.12),
          rx: 88,
          ry: 60,
          angle: 0.18,
          color: AppTheme.teal.withValues(alpha: 0.30),
          elevationH: 8,
        );
        _drawCutSunPaper(
          canvas,
          center: Offset(w * 0.70, h * 0.16),
          radius: 42,
          color: AppTheme.yellow.withValues(alpha: 0.44),
          overprint: true,
        );
        // 左下：番茄红回旋镖
        _drawBoomerangPaper(
          canvas,
          center: Offset(w * 0.14, h * 0.72),
          scale: 72,
          angle: -0.4,
          color: AppTheme.tomato.withValues(alpha: 0.22),
          elevationH: 6,
        );
        _drawStarburst(
          canvas,
          center: Offset(w * 0.86, h * 0.56),
          outerR: 20,
          color: AppTheme.cobalt.withValues(alpha: 0.52),
        );
        break;

      case ModuleBackgroundTheme.record:
        // 亲宝宝：向日葵黄太阳 + Girard 粉月牙剪纸
        _drawCutSunPaper(
          canvas,
          center: Offset(w * 0.85, h * 0.11),
          radius: 56,
          color: AppTheme.yellow.withValues(alpha: 0.40),
          overprint: false,
        );
        _drawKidneyPaper(
          canvas,
          center: Offset(w * 0.16, h * 0.24),
          rx: 70,
          ry: 50,
          angle: -0.30,
          color: AppTheme.pink.withValues(alpha: 0.28),
          elevationH: 7,
        );
        _drawBoomerangPaper(
          canvas,
          center: Offset(w * 0.84, h * 0.68),
          scale: 66,
          angle: 0.48,
          color: AppTheme.teal.withValues(alpha: 0.26),
          elevationH: 6,
        );
        _drawStarburst(
          canvas,
          center: Offset(w * 0.18, h * 0.78),
          outerR: 18,
          color: AppTheme.tomato.withValues(alpha: 0.52),
        );
        break;

      case ModuleBackgroundTheme.entertainment:
        // 娱乐：Saul Bass & Blue Note 爵士电台灵感（钴蓝星芒 + 番茄红回旋镖 + 原子球钟）
        _drawKidneyPaper(
          canvas,
          center: Offset(w * 0.86, h * 0.13),
          rx: 82,
          ry: 58,
          angle: 0.25,
          color: AppTheme.tomato.withValues(alpha: 0.24),
          elevationH: 8,
        );
        _drawCutSunPaper(
          canvas,
          center: Offset(w * 0.74, h * 0.17),
          radius: 40,
          color: AppTheme.yellow.withValues(alpha: 0.44),
          overprint: true,
        );
        _drawBallClock(
          canvas,
          center: Offset(w * 0.14, h * 0.48),
          radius: 42,
        );
        _drawStarburst(
          canvas,
          center: Offset(w * 0.86, h * 0.64),
          outerR: 22,
          color: AppTheme.cobalt.withValues(alpha: 0.55),
        );
        break;

      case ModuleBackgroundTheme.shop:
        // 商店：Girard 织物糖果色拼接（向日葵黄 + 绿松石 + 番茄红星芒）
        _drawBoomerangPaper(
          canvas,
          center: Offset(w * 0.82, h * 0.12),
          scale: 82,
          angle: -0.28,
          color: AppTheme.yellow.withValues(alpha: 0.42),
          elevationH: 8,
        );
        _drawKidneyPaper(
          canvas,
          center: Offset(w * 0.15, h * 0.36),
          rx: 68,
          ry: 48,
          angle: 0.22,
          color: AppTheme.teal.withValues(alpha: 0.26),
          elevationH: 6,
        );
        _drawStarburst(
          canvas,
          center: Offset(w * 0.86, h * 0.72),
          outerR: 20,
          color: AppTheme.tomato.withValues(alpha: 0.55),
        );
        break;
    }

    canvas.restore();
  }

  /// 绘制剪纸腰果/肾形（带暖棕高度阴影）
  void _drawKidneyPaper(
    Canvas canvas, {
    required Offset center,
    required double rx,
    required double ry,
    required double angle,
    required Color color,
    required double elevationH,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(-rx * 0.65, -ry * 0.45)
      ..cubicTo(0, -ry * 1.05, rx * 0.95, -ry * 0.65, rx * 0.82, ry * 0.15)
      ..cubicTo(
          rx * 0.70, ry * 0.92, -rx * 0.20, ry * 0.98, -rx * 0.72, ry * 0.42)
      ..cubicTo(
          -rx * 0.98, ry * 0.10, -rx * 0.32, -ry * 0.05, -rx * 0.65, -ry * 0.45)
      ..close();

    canvas.save();
    canvas.translate(elevationH * 0.5, elevationH);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.shadowBrown.withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, elevationH * 0.6),
    );
    canvas.restore();

    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  /// 绘制手工剪纸圆（支持 Multiply 叠印）
  void _drawCutSunPaper(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required bool overprint,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final path = Path();
    const segs = 16;
    for (var i = 0; i < segs; i++) {
      final a = i * 2 * math.pi / segs;
      final wobble = (i.isEven ? 1.015 : 0.985) * radius;
      final pt = Offset(math.cos(a) * wobble, math.sin(a) * wobble);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..blendMode = overprint ? BlendMode.multiply : BlendMode.srcOver,
    );
    canvas.restore();
  }

  /// 绘制 1950s Formica 回旋镖剪纸
  void _drawBoomerangPaper(
    Canvas canvas, {
    required Offset center,
    required double scale,
    required double angle,
    required Color color,
    required double elevationH,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(-scale * 0.85, scale * 0.42)
      ..quadraticBezierTo(
          -scale * 0.08, -scale * 0.78, scale * 0.88, -scale * 0.24)
      ..quadraticBezierTo(
          scale * 0.06, -scale * 0.08, -scale * 0.85, scale * 0.42)
      ..close();

    canvas.save();
    canvas.translate(elevationH * 0.5, elevationH);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.shadowBrown.withValues(alpha: 0.09)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, elevationH * 0.5),
    );
    canvas.restore();

    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  /// 绘制 George Nelson 1948 原子球钟（12 根细墨辐条 + 12 颗糖果彩球）
  void _drawBallClock(
    Canvas canvas, {
    required Offset center,
    required double radius,
  }) {
    final spokePaint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const ballPalette = [
      AppTheme.tomato,
      AppTheme.yellow,
      AppTheme.teal,
      AppTheme.pink,
      AppTheme.cobalt,
      AppTheme.overprintOrange,
    ];

    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final tip = Offset(
        center.dx + math.cos(a) * radius,
        center.dy + math.sin(a) * radius,
      );
      canvas.drawLine(center, tip, spokePaint);
      canvas.drawCircle(
        tip,
        4.2,
        Paint()
          ..color = ballPalette[i % ballPalette.length].withValues(alpha: 0.48),
      );
    }
    canvas.drawCircle(
      center,
      7.5,
      Paint()..color = AppTheme.yellow.withValues(alpha: 0.65),
    );
  }

  /// 绘制原子时代八芒星（Starburst）
  void _drawStarburst(
    Canvas canvas, {
    required Offset center,
    required double outerR,
    required Color color,
  }) {
    final path = Path();
    const points = 8;
    final innerR = outerR * 0.28;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = i * math.pi / points - math.pi / 2;
      final pt = Offset(
        center.dx + math.cos(a) * r,
        center.dy + math.sin(a) * r,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MidCenturyCutPaperPainter oldDelegate) {
    return oldDelegate.theme != theme ||
        oldDelegate.dropProgress != dropProgress;
  }
}
