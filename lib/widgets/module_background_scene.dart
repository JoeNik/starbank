import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../navigation/app_route_observer.dart';
import '../theme/app_theme.dart';

/// 各功能模块的孟菲斯背景主题枚举
enum ModuleBackgroundTheme {
  home,
  bank,
  shop,
  entertainment,
  record,
}

/// 孟菲斯（Memphis Milano）风格动态几何背景画布组件
/// 严格遵循五条法则：
/// 1. 积木（SHAPES）：圆、三角、方块、半圆、圆环、波浪线
/// 2. 撞色（CLASH）：粉、黄、青、钴蓝、番茄红、淡紫，底色暖米白 #FDF6EC
/// 3. 纹样（PATTERN）：黑色圆点阵、波浪线、十字纸屑
/// 4. 歪着放（TILT）：6° / 12° / 18° 旋转
/// 5. 黑描边与硬投影（OUTLINE）：每块积木描黑边 + 右下黑色硬阴影
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late final AnimationController _controller;
  PageRoute<dynamic>? _route;
  bool _appActive = true;
  bool _routeVisible = true;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
    _syncAnimationState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncAnimationState();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _syncAnimationState();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncAnimationState();
  }

  /// 同步动画启停状态，后台或不可见时停止 Ticker 节省能耗
  void _syncAnimationState() {
    if (!mounted) return;
    final shouldAnimate = _appActive && _routeVisible && _tickerEnabled;
    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _MemphisBackgroundPainter(
                theme: widget.theme,
                progress: _controller.value,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

/// 孟菲斯几何积木与纹样绘制画笔
class _MemphisBackgroundPainter extends CustomPainter {
  final ModuleBackgroundTheme theme;
  final double progress;

  const _MemphisBackgroundPainter({
    required this.theme,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 1. 绘制暖米白底色 #FDF6EC
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppTheme.cream,
    );

    // 2. 绘制孟菲斯底层圆点阵/方格纸微纹样（仅黑色微透明，不干扰阅读）
    _drawBasePattern(canvas, size);

    // 3. 根据当前模块主题选择 3~4 种主打糖果色（遵循指南：一个画面 3-4 种彩色）
    final palette = _paletteForTheme(theme);
    final salt = _saltForTheme(theme);

    // 4. 绘制角落装饰斑马纹/斜条纹色块与波浪线（Squiggle）
    _drawCornerStripes(canvas, size, palette[0]);
    _drawSquiggle(
      canvas,
      Offset(size.width * 0.14, size.height * 0.12),
      56,
      palette[1],
      -12 * math.pi / 180,
    );
    _drawSquiggle(
      canvas,
      Offset(size.width * 0.84, size.height * 0.78),
      64,
      palette[2],
      12 * math.pi / 180,
    );

    // 5. 绘制漂浮的孟菲斯几何积木（圆、三角、方块、半圆、圆环）+ 黑色纸屑
    for (var i = 0; i < 14; i++) {
      final center = _floatingPoint(size, i, salt);
      final baseRadius = 9.0 + _unit(i, salt + 2.1) * 11.0;
      final tilt = _tiltAngle(i, salt);
      final color = palette[i % palette.length];

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);

      switch (i % 6) {
        case 0:
          // 孟菲斯圆积木（带黑边与右下硬阴影）
          _drawMemphisCircle(canvas, baseRadius, color);
          break;
        case 1:
          // 孟菲斯三角积木
          _drawMemphisTriangle(canvas, baseRadius * 1.15, color);
          break;
        case 2:
          // 孟菲斯方块积木
          _drawMemphisSquare(canvas, baseRadius * 1.0, color);
          break;
        case 3:
          // 孟菲斯半圆积木
          _drawMemphisHalfCircle(canvas, baseRadius * 1.1, color);
          break;
        case 4:
          // 孟菲斯圆环
          _drawMemphisRing(canvas, baseRadius * 0.95, color);
          break;
        default:
          // 黑色十字/细菌纹小纸屑（Confetti）
          _drawConfettiCross(canvas, baseRadius * 0.55);
          break;
      }
      canvas.restore();
    }
  }

  /// 每个模块挑选 4 种孟菲斯糖果色
  List<Color> _paletteForTheme(ModuleBackgroundTheme t) {
    switch (t) {
      case ModuleBackgroundTheme.home:
        return const [
          AppTheme.pink,
          AppTheme.yellow,
          AppTheme.teal,
          AppTheme.cobalt,
        ];
      case ModuleBackgroundTheme.bank:
        return const [
          AppTheme.teal,
          AppTheme.yellow,
          AppTheme.cobalt,
          AppTheme.pink,
        ];
      case ModuleBackgroundTheme.shop:
        return const [
          AppTheme.yellow,
          AppTheme.tomato,
          AppTheme.pink,
          AppTheme.teal,
        ];
      case ModuleBackgroundTheme.entertainment:
        return const [
          AppTheme.lilac,
          AppTheme.pink,
          AppTheme.yellow,
          AppTheme.teal,
        ];
      case ModuleBackgroundTheme.record:
        return const [
          AppTheme.yellow,
          AppTheme.pink,
          AppTheme.lilac,
          AppTheme.teal,
        ];
    }
  }

  double _saltForTheme(ModuleBackgroundTheme t) {
    switch (t) {
      case ModuleBackgroundTheme.home:
        return 1.3;
      case ModuleBackgroundTheme.bank:
        return 4.1;
      case ModuleBackgroundTheme.shop:
        return 7.3;
      case ModuleBackgroundTheme.entertainment:
        return 10.5;
      case ModuleBackgroundTheme.record:
        return 13.7;
    }
  }

  /// 绘制底层稀疏圆点阵（Polka Dots，#111111 低透明）
  void _drawBasePattern(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.065)
      ..style = PaintingStyle.fill;
    const step = 34.0;
    var row = 0;
    for (var y = 18.0; y < size.height; y += step) {
      final offsetX = row.isEven ? 16.0 : 33.0;
      for (var x = offsetX; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
      }
      row++;
    }
  }

  /// 绘制右上角与左下角孟菲斯斜条纹装饰块
  void _drawCornerStripes(Canvas canvas, Size size, Color accent) {
    final stripePaint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.08)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final offset = i * 11.0;
      canvas.drawLine(
        Offset(size.width - 68 + offset, 8),
        Offset(size.width - 8, 68 - offset),
        stripePaint,
      );
    }
  }

  /// 绘制孟菲斯锯齿波浪线（Squiggle）
  void _drawSquiggle(
    Canvas canvas,
    Offset center,
    double width,
    Color color,
    double angle,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path();
    const waves = 5;
    final step = width / (waves * 2);
    const amp = 5.0;
    path.moveTo(-width / 2, 0);
    for (var i = 0; i < waves * 2; i++) {
      final x = -width / 2 + (i + 1) * step;
      final y = i.isEven ? -amp : amp;
      path.lineTo(x, y);
    }

    // 硬阴影
    canvas.save();
    canvas.translate(3, 3);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // 彩色波浪主体
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  /// 绘制带黑边与硬阴影的孟菲斯圆
  void _drawMemphisCircle(Canvas canvas, double r, Color color) {
    const shadowShift = Offset(3.0, 3.0);
    canvas.drawCircle(
      shadowShift,
      r,
      Paint()..color = AppTheme.ink.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..color = color.withValues(alpha: 0.48),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  /// 绘制带黑边与硬阴影的孟菲斯三角
  void _drawMemphisTriangle(Canvas canvas, double r, Color color) {
    final path = Path()
      ..moveTo(0, -r)
      ..lineTo(r * 0.92, r * 0.76)
      ..lineTo(-r * 0.92, r * 0.76)
      ..close();

    canvas.save();
    canvas.translate(3.0, 3.0);
    canvas.drawPath(
      path,
      Paint()..color = AppTheme.ink.withValues(alpha: 0.28),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: 0.48),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// 绘制带黑边与硬阴影的孟菲斯方块
  void _drawMemphisSquare(Canvas canvas, double r, Color color) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.6),
      const Radius.circular(4),
    );
    final shadowRect = rect.shift(const Offset(3.0, 3.0));
    canvas.drawRRect(
      shadowRect,
      Paint()..color = AppTheme.ink.withValues(alpha: 0.28),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(alpha: 0.48),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  /// 绘制带黑边与硬阴影的孟菲斯半圆
  void _drawMemphisHalfCircle(Canvas canvas, double r, Color color) {
    final rect = Rect.fromCenter(
      center: Offset(0, r * 0.25),
      width: r * 1.9,
      height: r * 1.9,
    );
    final path = Path()
      ..arcTo(rect, math.pi, math.pi, false)
      ..close();

    canvas.save();
    canvas.translate(3.0, 3.0);
    canvas.drawPath(
      path,
      Paint()..color = AppTheme.ink.withValues(alpha: 0.28),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: 0.48),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// 绘制孟菲斯圆环
  void _drawMemphisRing(Canvas canvas, double r, Color color) {
    canvas.drawCircle(
      const Offset(2.5, 2.5),
      r,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = color.withValues(alpha: 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );
    canvas.drawCircle(
      Offset.zero,
      r + 2.2,
      Paint()
        ..color = AppTheme.ink.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// 绘制黑色十字纸屑（Confetti）
  void _drawConfettiCross(Canvas canvas, double r) {
    final paint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), paint);
    canvas.drawLine(Offset(0, -r), Offset(0, r), paint);
  }

  double _unit(int index, double salt) {
    final value = math.sin(index * 127.1 + salt * 311.7) * 43758.5453123;
    return value.abs() - value.abs().floorToDouble();
  }

  Offset _floatingPoint(Size size, int index, double salt) {
    final margin = 28.0 + _unit(index, salt + 0.7) * 16.0;
    final minX = math.min(margin, size.width / 2);
    final maxX = math.max(minX, size.width - margin);
    final minY = math.min(margin, size.height / 2);
    final maxY = math.max(minY, size.height - margin);
    final baseX = minX + _unit(index, salt) * (maxX - minX);
    final baseY = minY + _unit(index, salt + 7.9) * (maxY - minY);
    final phaseX = progress * math.pi * 2 + _unit(index, salt + 11.2) * math.pi * 2;
    final phaseY = progress * math.pi * 2 + _unit(index, salt + 13.4) * math.pi * 2;
    final rawX = baseX + math.sin(phaseX) * 10.0;
    final rawY = baseY + math.cos(phaseY) * 10.0;
    return Offset(
      rawX.clamp(minX, maxX).toDouble(),
      rawY.clamp(minY, maxY).toDouble(),
    );
  }

  /// 遵循规则 04「歪着放」：6° / 12° / 18° 三档旋转 + 轻微摆动
  double _tiltAngle(int index, double salt) {
    const tilts = [6.0, -6.0, 12.0, -12.0, 18.0, -18.0];
    final baseDeg = tilts[index % tilts.length];
    final wobble = math.sin(progress * math.pi * 2 + index) * 3.0;
    return (baseDeg + wobble) * math.pi / 180.0;
  }

  @override
  bool shouldRepaint(covariant _MemphisBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.theme != theme;
  }
}
