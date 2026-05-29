import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../navigation/app_route_observer.dart';

enum ModuleBackgroundTheme {
  home,
  bank,
  shop,
  entertainment,
  record,
}

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
      duration: const Duration(seconds: 34),
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
              painter: _ModuleBackgroundPainter(
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

class _ModuleBackgroundPainter extends CustomPainter {
  final ModuleBackgroundTheme theme;
  final double progress;

  const _ModuleBackgroundPainter({
    required this.theme,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (theme) {
      case ModuleBackgroundTheme.home:
        _drawHome(canvas, size);
        break;
      case ModuleBackgroundTheme.bank:
        _drawBank(canvas, size);
        break;
      case ModuleBackgroundTheme.shop:
        _drawShop(canvas, size);
        break;
      case ModuleBackgroundTheme.entertainment:
        _drawEntertainment(canvas, size);
        break;
      case ModuleBackgroundTheme.record:
        _drawRecord(canvas, size);
        break;
    }
  }

  void _drawHome(Canvas canvas, Size size) {
    _drawRibbon(canvas, size, const Color(0xFFFFD6E0), 0.08, 0.14);
    _drawRibbon(canvas, size, const Color(0xFFFFF0A8), 0.34, 0.1);
    _drawHomeElements(canvas, size);
  }

  void _drawBank(Canvas canvas, Size size) {
    _drawRibbon(canvas, size, const Color(0xFFBFE8FF), 0.06, 0.13);
    _drawRibbon(canvas, size, const Color(0xFFFFD89D), 0.42, 0.09);
    _drawBankElements(canvas, size);
  }

  void _drawShop(Canvas canvas, Size size) {
    _drawRibbon(canvas, size, const Color(0xFFFFE49B), 0.1, 0.12);
    _drawRibbon(canvas, size, const Color(0xFFFFC7D6), 0.46, 0.1);
    _drawShopElements(canvas, size);
  }

  void _drawEntertainment(Canvas canvas, Size size) {
    _drawRibbon(canvas, size, const Color(0xFFFFB7C8), 0.08, 0.12);
    _drawRibbon(canvas, size, const Color(0xFFC4E5FF), 0.4, 0.1);
    _drawEntertainmentElements(canvas, size);
  }

  void _drawRecord(Canvas canvas, Size size) {
    _drawRibbon(canvas, size, const Color(0xFFD4F7DA), 0.07, 0.12);
    _drawRibbon(canvas, size, const Color(0xFFFFE4B6), 0.45, 0.1);
    _drawRecordElements(canvas, size);
  }

  void _drawRibbon(
    Canvas canvas,
    Size size,
    Color color,
    double yFactor,
    double amplitude,
  ) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final baseY = size.height * yFactor;
    path.moveTo(-40, baseY);
    for (var x = -40.0; x <= size.width + 40; x += 36) {
      final phase = (x / size.width + progress) * math.pi * 2;
      final y = baseY + math.sin(phase) * size.height * amplitude;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  void _drawHomeElements(Canvas canvas, Size size) {
    final star = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final heart = Paint()
      ..color = const Color(0xFFFF8A80).withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = const Color(0xFF64B5F6).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final sparkle = Paint()
      ..color = const Color(0xFF81C784).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 24; i++) {
      final center = _floatingPoint(size, i, 1.3);
      final radius = 4.0 + _unit(i, 2.1) * 9.0;
      switch (i % 4) {
        case 0:
          _drawRotated(canvas, center, _rotation(i, 1.4), () {
            _drawStar(canvas, center, radius, star);
          });
          break;
        case 1:
          _drawHeart(canvas, center, radius, heart);
          break;
        case 2:
          canvas.drawCircle(center, radius * 0.8, ring);
          break;
        default:
          _drawSparkle(canvas, center, radius, sparkle);
          break;
      }
    }
  }

  void _drawBankElements(Canvas canvas, Size size) {
    final coin = Paint()
      ..color = const Color(0xFFFFC447).withValues(alpha: 0.17)
      ..style = PaintingStyle.fill;
    final coinLine = Paint()
      ..color = const Color(0xFFE19A00).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final diamond = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final plus = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 22; i++) {
      final center = _floatingPoint(size, i, 3.7);
      final radius = 5.0 + _unit(i, 4.8) * 10.0;
      switch (i % 4) {
        case 0:
          _drawCoin(canvas, center, radius, coin, coinLine);
          break;
        case 1:
          _drawRotated(canvas, center, _rotation(i, 3.1), () {
            _drawDiamond(canvas, center, radius, diamond);
          });
          break;
        case 2:
          _drawSparkle(canvas, center, radius, plus);
          break;
        default:
          _drawMiniBars(canvas, center, radius, plus);
          break;
      }
    }
  }

  void _drawShopElements(Canvas canvas, Size size) {
    final gift = Paint()
      ..color = const Color(0xFFFFC928).withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final ribbon = Paint()
      ..color = const Color(0xFFFF6F91).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final tag = Paint()
      ..color = const Color(0xFF4DB6AC).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final star = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 23; i++) {
      final center = _floatingPoint(size, i, 6.2);
      final radius = 6.0 + _unit(i, 6.8) * 10.0;
      switch (i % 4) {
        case 0:
          _drawRotated(canvas, center, _rotation(i, 6.3), () {
            _drawGift(canvas, center, radius, gift, ribbon);
          });
          break;
        case 1:
          _drawTag(canvas, center, radius, tag);
          break;
        case 2:
          _drawBow(canvas, center, radius, ribbon);
          break;
        default:
          _drawStar(canvas, center, radius * 0.75, star);
          break;
      }
    }
  }

  void _drawEntertainmentElements(Canvas canvas, Size size) {
    final note = Paint()
      ..color = const Color(0xFFFF6B9D).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final dot = Paint()
      ..color = const Color(0xFF64B5F6).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final play = Paint()
      ..color = const Color(0xFFFFB74D).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final sparkle = Paint()
      ..color = const Color(0xFFAB47BC).withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 25; i++) {
      final center = _floatingPoint(size, i, 9.4);
      final radius = 5.0 + _unit(i, 9.8) * 10.0;
      switch (i % 5) {
        case 0:
        case 1:
          _drawRotated(canvas, center, _rotation(i, 9.1), () {
            _drawMusicNote(canvas, center, radius, note, dot);
          });
          break;
        case 2:
          _drawPlayTriangle(canvas, center, radius, play);
          break;
        case 3:
          canvas.drawCircle(center, radius * 0.85, sparkle);
          break;
        default:
          _drawSparkle(canvas, center, radius, sparkle);
          break;
      }
    }
  }

  void _drawRecordElements(Canvas canvas, Size size) {
    final heart = Paint()
      ..color = const Color(0xFFFF8A80).withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = const Color(0xFF66BB6A).withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final check = Paint()
      ..color = const Color(0xFF4FC3F7).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final calendar = Paint()
      ..color = const Color(0xFFFFB74D).withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < 22; i++) {
      final center = _floatingPoint(size, i, 12.5);
      final radius = 5.0 + _unit(i, 12.9) * 9.0;
      switch (i % 4) {
        case 0:
          _drawHeart(canvas, center, radius, heart);
          break;
        case 1:
          _drawHealthLine(canvas, center, radius, line);
          break;
        case 2:
          _drawCheckCircle(canvas, center, radius, check);
          break;
        default:
          _drawTinyCalendar(canvas, center, radius, calendar);
          break;
      }
    }
  }

  double _unit(int index, double salt) {
    final value = math.sin(index * 127.1 + salt * 311.7) * 43758.5453123;
    return value.abs() - value.abs().floorToDouble();
  }

  Offset _floatingPoint(Size size, int index, double salt) {
    final margin = 34.0 + _unit(index, salt + 0.7) * 18.0;
    final minX = math.min(margin, size.width / 2);
    final maxX = math.max(minX, size.width - margin);
    final minY = math.min(margin, size.height / 2);
    final maxY = math.max(minY, size.height - margin);
    final baseX = minX + _unit(index, salt) * (maxX - minX);
    final baseY = minY + _unit(index, salt + 7.9) * (maxY - minY);
    final cycleX = 1 + (_unit(index, salt + 2.3) * 3).floor();
    final cycleY = 1 + (_unit(index, salt + 5.1) * 3).floor();
    final wobbleX = 1 + (_unit(index, salt + 6.4) * 2).floor();
    final wobbleY = 1 + (_unit(index, salt + 8.6) * 2).floor();
    final phaseX = progress * math.pi * 2 * cycleX +
        _unit(index, salt + 11.2) * math.pi * 2;
    final phaseY = progress * math.pi * 2 * cycleY +
        _unit(index, salt + 13.4) * math.pi * 2;
    final ampX = 18.0 + _unit(index, salt + 17.6) * 24.0;
    final ampY = 14.0 + _unit(index, salt + 19.8) * 22.0;
    final rawX = baseX +
        math.sin(phaseX) * ampX +
        math.sin(phaseY * wobbleX) * ampX * 0.35;
    final rawY = baseY +
        math.cos(phaseY) * ampY +
        math.sin(phaseX * wobbleY) * ampY * 0.35;
    return Offset(
      rawX.clamp(minX, maxX).toDouble(),
      rawY.clamp(minY, maxY).toDouble(),
    );
  }

  double _rotation(int index, double salt) {
    final cycle = 1 + (_unit(index, salt) * 2).floor();
    final phase = progress * math.pi * 2 * cycle;
    return math.sin(phase + _unit(index, salt + 4.4) * math.pi * 2) * 0.35;
  }

  void _drawRotated(
    Canvas canvas,
    Offset center,
    double angle,
    VoidCallback draw,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      paint,
    );
    canvas.drawCircle(center, radius * 0.22, paint);
  }

  void _drawCoin(
    Canvas canvas,
    Offset center,
    double radius,
    Paint fill,
    Paint stroke,
  ) {
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius * 0.72, stroke);
    canvas.drawLine(
      Offset(center.dx - radius * 0.35, center.dy),
      Offset(center.dx + radius * 0.35, center.dy),
      stroke,
    );
  }

  void _drawDiamond(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.85, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.85, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawMiniBars(Canvas canvas, Offset center, double radius, Paint paint) {
    for (var i = 0; i < 3; i++) {
      final x = center.dx - radius * 0.55 + i * radius * 0.55;
      canvas.drawLine(
        Offset(x, center.dy + radius * 0.55),
        Offset(x, center.dy - radius * (0.2 + i * 0.18)),
        paint,
      );
    }
  }

  void _drawGift(
    Canvas canvas,
    Offset center,
    double radius,
    Paint box,
    Paint ribbon,
  ) {
    final rect = Rect.fromCenter(
      center: center,
      width: radius * 2.1,
      height: radius * 1.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      box,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.85),
      Offset(center.dx, center.dy + radius * 0.85),
      ribbon,
    );
    canvas.drawLine(
      Offset(center.dx - radius * 1.05, center.dy - radius * 0.15),
      Offset(center.dx + radius * 1.05, center.dy - radius * 0.15),
      ribbon,
    );
  }

  void _drawBow(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(
      Offset(center.dx - radius * 0.35, center.dy),
      radius * 0.4,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * 0.35, center.dy),
      radius * 0.4,
      paint,
    );
    canvas.drawCircle(center, radius * 0.18, paint);
  }

  void _drawTag(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - radius * 0.9, center.dy - radius * 0.45)
      ..lineTo(center.dx + radius * 0.35, center.dy - radius * 0.45)
      ..lineTo(center.dx + radius * 0.9, center.dy)
      ..lineTo(center.dx + radius * 0.35, center.dy + radius * 0.45)
      ..lineTo(center.dx - radius * 0.9, center.dy + radius * 0.45)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.45, center.dy),
      radius * 0.14,
      paint,
    );
  }

  void _drawMusicNote(
    Canvas canvas,
    Offset center,
    double radius,
    Paint stroke,
    Paint dot,
  ) {
    canvas.drawCircle(
      Offset(center.dx - radius * 0.25, center.dy + radius * 0.45),
      radius * 0.35,
      dot,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.1, center.dy + radius * 0.45),
      Offset(center.dx + radius * 0.1, center.dy - radius * 0.8),
      stroke,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        center.dx + radius * 0.1,
        center.dy - radius * 0.9,
        radius * 1.1,
        radius * 0.85,
      ),
      math.pi,
      math.pi * 0.75,
      false,
      stroke,
    );
  }

  void _drawPlayTriangle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path()
      ..moveTo(center.dx - radius * 0.45, center.dy - radius * 0.65)
      ..lineTo(center.dx - radius * 0.45, center.dy + radius * 0.65)
      ..lineTo(center.dx + radius * 0.7, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawHealthLine(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawLine(
      Offset(center.dx - radius * 1.25, center.dy),
      Offset(center.dx - radius * 0.45, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - radius * 0.45, center.dy),
      Offset(center.dx, center.dy - radius * 0.8),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.8),
      Offset(center.dx + radius * 0.45, center.dy + radius * 0.65),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.45, center.dy + radius * 0.65),
      Offset(center.dx + radius * 1.25, center.dy - radius * 0.2),
      paint,
    );
  }

  void _drawCheckCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(
      Offset(center.dx - radius * 0.42, center.dy),
      Offset(center.dx - radius * 0.1, center.dy + radius * 0.32),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - radius * 0.1, center.dy + radius * 0.32),
      Offset(center.dx + radius * 0.48, center.dy - radius * 0.38),
      paint,
    );
  }

  void _drawTinyCalendar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final rect = Rect.fromCenter(
      center: center,
      width: radius * 1.8,
      height: radius * 1.55,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, center.dy - radius * 0.35),
      Offset(rect.right, center.dy - radius * 0.35),
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx - radius * 0.35, center.dy + radius * 0.2),
      radius * 0.12,
      paint,
    );
    canvas.drawCircle(
      Offset(center.dx + radius * 0.35, center.dy + radius * 0.2),
      radius * 0.12,
      paint,
    );
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy + size * 0.45)
      ..cubicTo(
        center.dx - size * 1.25,
        center.dy - size * 0.35,
        center.dx - size * 0.55,
        center.dy - size * 1.25,
        center.dx,
        center.dy - size * 0.45,
      )
      ..cubicTo(
        center.dx + size * 0.55,
        center.dy - size * 1.25,
        center.dx + size * 1.25,
        center.dy - size * 0.35,
        center.dx,
        center.dy + size * 0.45,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ModuleBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.theme != theme;
  }
}
