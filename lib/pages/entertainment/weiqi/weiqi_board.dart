import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'weiqi_theme.dart';

/// 棋盘控制器：由页面触发「提子飞入口袋」动画。
class WqBoardController {
  void Function(List<int> points, int stoneColor)? _onFly;

  void flyCaptures(List<int> points, int stoneColor) {
    _onFly?.call(points, stoneColor);
  }
}

/// 棋盘视图：木纹棋盘 + 棋子 + 呼吸小灯 + 闪烁提示点 + 区域微光 +
/// 幽灵棋子（演示）+ 提子飞行动画 + 提子口袋。
class WeiqiBoardView extends StatefulWidget {
  final int n;
  final List<int> stones;
  final int lastMove;
  final Set<int> breathePoints;
  final bool breatheWarn;
  final Set<int> blinkPoints;
  final int? ghostStone; // 演示幽灵子
  final int ghostColor;
  final int? glowCenter; // 区域微光中心（索引）
  final double glowRadius; // 区域半径（百分比）
  final void Function(int point)? onPointTap;
  final WqBoardController? controller;
  final int capByBlack; // 黑方提子数（显示在白子口袋）
  final int capByWhite; // 白方提子数（显示在黑子口袋）

  const WeiqiBoardView({
    super.key,
    this.n = 9,
    required this.stones,
    this.lastMove = -1,
    this.breathePoints = const {},
    this.breatheWarn = false,
    this.blinkPoints = const {},
    this.ghostStone,
    this.ghostColor = 1,
    this.glowCenter,
    this.glowRadius = 22,
    this.onPointTap,
    this.controller,
    this.capByBlack = 0,
    this.capByWhite = 0,
  });

  @override
  State<WeiqiBoardView> createState() => _WeiqiBoardViewState();
}

class _WeiqiBoardViewState extends State<WeiqiBoardView>
    with TickerProviderStateMixin {
  static const double _pad = 6.2; // 与原型一致：棋盘边缘留白百分比
  late final AnimationController _pulse; // 呼吸/闪烁共用脉冲
  late final AnimationController _pop; // 落子弹跳（最后一手）
  final List<_FlyStone> _flies = [];
  Timer? _ghostTimer;
  int? _ghost;
  int _ghostColor = 1;
  int _popPoint = -1;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
    widget.controller?._onFly = _spawnFlies;
  }

  @override
  void didUpdateWidget(covariant WeiqiBoardView old) {
    super.didUpdateWidget(old);
    if (widget.ghostStone != old.ghostStone) {
      _ghost = widget.ghostStone;
      _ghostColor = widget.ghostColor;
      _ghostTimer?.cancel();
      if (_ghost != null) {
        _ghostTimer = Timer(const Duration(milliseconds: 1100), () {
          if (mounted) setState(() => _ghost = null);
        });
      }
      setState(() {});
    }
    if (widget.lastMove != old.lastMove && widget.lastMove >= 0) {
      // 最后一手弹跳入场（对应原型 .stone.drop）
      _popPoint = widget.lastMove;
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller?._onFly = null;
    _ghostTimer?.cancel();
    _pulse.dispose();
    _pop.dispose();
    for (final f in List<_FlyStone>.from(_flies)) {
      f.ctrl.dispose();
    }
    _flies.clear();
    super.dispose();
  }

  void _spawnFlies(List<int> points, int stoneColor) {
    for (final p in points) {
      try {
        final ctrl = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 620),
        );
        final fly = _FlyStone(point: p, color: stoneColor, ctrl: ctrl);
        setState(() => _flies.add(fly));
        ctrl.forward().whenComplete(() {
          if (mounted) setState(() => _flies.remove(fly));
          ctrl.dispose();
        });
      } catch (_) {
        // 动画失败不影响棋局
      }
    }
  }

  double _frac(int coord) => (_pad + coord * _step) / 100;
  double get _step => (100 - _pad * 2) / (widget.n - 1);

  Offset _pointOffset(int i, Size size) {
    return Offset(_frac(i % widget.n) * size.width,
        _frac(i ~/ widget.n) * size.height);
  }

  void _handleTap(Offset local, Size size) {
    if (widget.onPointTap == null) return;
    final fx = local.dx / size.width * 100;
    final fy = local.dy / size.height * 100;
    final gx = ((fx - _pad) / _step).round();
    final gy = ((fy - _pad) / _step).round();
    if (gx < 0 || gy < 0 || gx >= widget.n || gy >= widget.n) return;
    widget.onPointTap!(gy * widget.n + gx);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxWidth);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onPointTap == null
              ? null
              : (d) => _handleTap(d.localPosition, size),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const RadialGradient(
                    center: Alignment(-0.6, -0.8),
                    radius: 1.4,
                    colors: [Color(0xFFF2CD8C), WqTheme.boardA, WqTheme.boardB],
                    stops: [0, 0.45, 1],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8C5E2D).withValues(alpha: 0.45),
                      offset: const Offset(0, 6),
                      blurRadius: 0,
                    ),
                    BoxShadow(
                      color: WqTheme.line.withValues(alpha: 0.16),
                      offset: const Offset(0, 10),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: CustomPaint(
                  size: size,
                  painter: _BoardPainter(
                    n: widget.n,
                    stones: widget.stones,
                    lastMove: widget.lastMove,
                    breathePoints: widget.breathePoints,
                    breatheWarn: widget.breatheWarn,
                    blinkPoints: widget.blinkPoints,
                    glowCenter: widget.glowCenter,
                    glowRadius: widget.glowRadius,
                    pulse: _pulse,
                    pop: _pop,
                    popPoint: _popPoint,
                    ghost: _ghost ?? widget.ghostStone,
                    ghostColor: _ghostColor,
                  ),
                ),
              ),
              // 提子飞行动画层
              ..._flies.map((f) => AnimatedBuilder(
                    animation: f.ctrl,
                    builder: (context, _) {
                      final t = Curves.easeInOutCubic.transform(f.ctrl.value);
                      final start = _pointOffset(f.point, size);
                      final end = Offset(
                        f.color == 2 ? size.width * 0.88 : size.width * 0.12,
                        f.color == 2 ? size.height * 0.10 : size.height * 0.90,
                      );
                      final pos = Offset.lerp(start, end, t)!;
                      final scale = 1 - 0.68 * t;
                      return Positioned(
                        left: pos.dx - size.width * 0.047,
                        top: pos.dy - size.width * 0.047,
                        child: Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: (1 - t).clamp(0.0, 1.0),
                            child: SizedBox(
                              width: size.width * 0.094,
                              height: size.width * 0.094,
                              child: CustomPaint(
                                painter: _StonePainter(
                                    color: f.color, boardSize: size.width),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )),
              // 提子口袋
              _pocket(
                color: 2,
                count: widget.capByBlack,
                left: 8,
                bottom: 8,
                size: size,
              ),
              _pocket(
                color: 1,
                count: widget.capByWhite,
                right: 8,
                top: 8,
                size: size,
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _pocket({
    required int color,
    required int count,
    double? left,
    double? right,
    double? top,
    double? bottom,
    required Size size,
  }) {
    return Positioned(
      left: left?.toDouble(),
      right: right?.toDouble(),
      top: top?.toDouble(),
      bottom: bottom?.toDouble(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14233240),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.4),
                  colors: color == 1
                      ? const [WqTheme.stoneBlackA, WqTheme.stoneBlackC]
                      : const [WqTheme.stoneWhiteA, WqTheme.stoneWhiteC],
                ),
                border: color == 2
                    ? Border.all(color: const Color(0x338C8278))
                    : null,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: WqTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlyStone {
  final int point;
  final int color;
  final AnimationController ctrl;

  _FlyStone({required this.point, required this.color, required this.ctrl});
}

class _BoardPainter extends CustomPainter {
  final int n;
  final List<int> stones;
  final int lastMove;
  final Set<int> breathePoints;
  final bool breatheWarn;
  final Set<int> blinkPoints;
  final int? glowCenter;
  final double glowRadius;
  final Animation<double> pulse;
  final Animation<double> pop; // 最后一手落子弹跳 0→1
  final int popPoint;
  final int? ghost;
  final int ghostColor;

  _BoardPainter({
    required this.n,
    required this.stones,
    required this.lastMove,
    required this.breathePoints,
    required this.breatheWarn,
    required this.blinkPoints,
    required this.glowCenter,
    required this.glowRadius,
    required this.pulse,
    required this.pop,
    required this.popPoint,
    required this.ghost,
    required this.ghostColor,
  }) : super(repaint: Listenable.merge([pulse, pop]));

  static const double _pad = 6.2;
  double _stepFrac() => (100 - _pad * 2) / (n - 1) / 100;

  Offset _pt(int i, Size size) {
    final x = i % n, y = i ~/ n;
    return Offset((_pad + x * _stepFrac() * 100) / 100 * size.width,
        (_pad + y * _stepFrac() * 100) / 100 * size.width);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (glowCenter != null) _paintGlow(canvas, size);
    _paintStones(canvas, size);
    _paintBreathe(canvas, size);
    _paintBlink(canvas, size);
    if (ghost != null) {
      _paintOneStone(canvas, size, ghost!, ghostColor, alpha: 0.55);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = WqTheme.line.withValues(alpha: 0.9)
      ..strokeWidth = (size.width * 0.0055).clamp(0.8, 1.6)
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < n; k++) {
      final p = _pad + k * _stepFrac() * 100;
      final v = p / 100 * size.width;
      canvas.drawLine(Offset(_pad / 100 * size.width, v),
          Offset((100 - _pad) / 100 * size.width, v), line);
      canvas.drawLine(Offset(v, _pad / 100 * size.width),
          Offset(v, (100 - _pad) / 100 * size.width), line);
    }
    // 星位
    final star = Paint()..color = WqTheme.line;
    const stars = [(2, 2), (6, 2), (2, 6), (6, 6), (4, 4)];
    for (final (sx, sy) in stars) {
      if (sx >= n || sy >= n) continue;
      canvas.drawCircle(
        Offset((_pad + sx * _stepFrac() * 100) / 100 * size.width,
            (_pad + sy * _stepFrac() * 100) / 100 * size.width),
        size.width * 0.012,
        star,
      );
    }
  }

  void _paintStones(Canvas canvas, Size size) {
    for (var i = 0; i < stones.length; i++) {
      if (stones[i] == 0) continue;
      if (i == popPoint && pop.value < 1) {
        // 落子弹跳：从 1.6 倍缩回原尺寸（原型 .drop 动画）
        final t = Curves.easeOutBack.transform(pop.value);
        final scale = 1.6 - 0.6 * t;
        final c = _pt(i, size);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(scale);
        canvas.translate(-c.dx, -c.dy);
        _paintOneStone(canvas, size, i, stones[i]);
        if (i == lastMove) _paintLastMark(canvas, size, i);
        canvas.restore();
        continue;
      }
      _paintOneStone(canvas, size, i, stones[i]);
      if (i == lastMove) _paintLastMark(canvas, size, i);
    }
  }

  void _paintLastMark(Canvas canvas, Size size, int i) {
    final c = _pt(i, size);
    canvas.drawCircle(
      c,
      size.width * 0.013,
      Paint()
        ..color = stones[i] == 1
            ? const Color(0xFFFFC53D).withValues(alpha: 0.9)
            : const Color(0xFF34B37E).withValues(alpha: 0.85),
    );
  }

  void _paintOneStone(Canvas canvas, Size size, int i, int color,
      {double alpha = 1.0}) {
    final c = _pt(i, size);
    final r = size.width * 0.047;
    // 阴影
    canvas.drawCircle(
      c.translate(0, size.width * 0.006),
      r,
      Paint()
        ..color = const Color(0x73140F05).withValues(alpha: 0.45 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final grad = RadialGradient(
      center: const Alignment(-0.35, -0.45),
      radius: 1.1,
      colors: color == 1
          ? const [
              WqTheme.stoneBlackA,
              WqTheme.stoneBlackB,
              WqTheme.stoneBlackC
            ]
          : const [WqTheme.stoneWhiteA, WqTheme.stoneWhiteB, WqTheme.stoneWhiteC],
      stops: const [0, 0.5, 1],
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = grad.createShader(Rect.fromCircle(center: c, radius: r))
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  void _paintBreathe(Canvas canvas, Size size) {
    final t = math.sin(pulse.value * 2 * math.pi);
    final scale = 0.82 + 0.18 * (t + 1) / 2 * 1.4; // 0.82~1.1
    final opacity = 0.72 + 0.28 * (t + 1) / 2;
    final grad = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      colors: breatheWarn
          ? const [Color(0xFFFFE49A), Color(0xFFFFB020)]
          : const [Color(0xFFB8F1D4), Color(0xFF3FC98B)],
    );
    final ring = Paint()
      ..color = breatheWarn
          ? const Color(0xFFFFB020).withValues(alpha: 0.28 * opacity)
          : const Color(0xFF3FC98B).withValues(alpha: 0.25 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.008;
    for (final p in breathePoints) {
      final c = _pt(p, size);
      final r = size.width * 0.043 * scale;
      final paint = Paint()
        ..shader = grad.createShader(Rect.fromCircle(center: c, radius: r))
        ..color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(c, r, paint);
      canvas.drawCircle(c, r + size.width * 0.008, ring);
    }
  }

  void _paintBlink(Canvas canvas, Size size) {
    final t = math.sin(pulse.value * 2 * math.pi);
    final opacity = 0.3 + 0.7 * (t + 1) / 2;
    final scale = 0.85 + 0.27 * (t + 1) / 2;
    for (final p in blinkPoints) {
      final c = _pt(p, size);
      final r = size.width * 0.046 * scale;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = WqTheme.sun.withValues(alpha: 0.25 * opacity),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = WqTheme.sun.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.009,
      );
    }
  }

  void _paintGlow(Canvas canvas, Size size) {
    final c = _pt(glowCenter!, size);
    final r = size.width * (glowRadius / 100) * 2;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = const Color(0xFF3FC98B).withValues(alpha: 0.10),
    );
    // 虚线圈
    final dash = Paint()
      ..color = const Color(0xFF3FC98B).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.009;
    const segments = 28;
    final circumference = 2 * math.pi * r;
    final dashLen = circumference / segments * 0.55;
    final gapLen = circumference / segments * 0.45;
    var dist = 0.0;
    while (dist < circumference) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), dist / r, dashLen / r,
          false, dash);
      dist += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) {
    return old.lastMove != lastMove ||
        old.breatheWarn != breatheWarn ||
        old.glowCenter != glowCenter ||
        old.glowRadius != glowRadius ||
        old.popPoint != popPoint ||
        old.ghost != ghost ||
        old.ghostColor != ghostColor ||
        old.breathePoints.length != breathePoints.length ||
        old.blinkPoints.length != blinkPoints.length ||
        !_listEq(old.stones, stones);
  }

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _StonePainter extends CustomPainter {
  final int color;
  final double boardSize;

  _StonePainter({required this.color, required this.boardSize});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final grad = RadialGradient(
      center: const Alignment(-0.35, -0.45),
      radius: 1.1,
      colors: color == 1
          ? const [WqTheme.stoneBlackA, WqTheme.stoneBlackB, WqTheme.stoneBlackC]
          : const [WqTheme.stoneWhiteA, WqTheme.stoneWhiteB, WqTheme.stoneWhiteC],
      stops: const [0, 0.5, 1],
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = grad.createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _StonePainter old) => old.color != color;
}
