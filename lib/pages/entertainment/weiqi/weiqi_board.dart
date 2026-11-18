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

/// 商业级围棋棋盘视图：
/// 孟菲斯粗黑边硬投影底座 + 护眼榧木纹棋盘 + 立体黑白云子 +
/// 呼吸气点小灯 + 闪烁提示点 + 区域微光 + 幽灵棋子（演示）+
/// 棋盘坐标刻度（A-T / 1-19）+ 手数编号渲染 +
/// 形势判断/终局点目领地小方块叠加层 + 死子标记 +
/// 13/19路十字准星防误触落子预览 + 提子飞行动画与口袋。
class WeiqiBoardView extends StatefulWidget {
  final int n;
  final List<int> stones;
  final int lastMove;
  final Set<int> breathePoints;
  final bool breatheWarn;
  final Set<int> blinkPoints;
  final int? ghostStone; // 演示幽灵子
  final int ghostColor;

  /// 提子讲解残影：点 → 棋子颜色，半透明重现刚被提走的棋子
  final Map<int, int> ghostStones;
  final int? glowCenter; // 区域微光中心（索引）
  final double glowRadius; // 区域半径（百分比）
  final void Function(int point)? onPointTap;
  final WqBoardController? controller;
  final int capByBlack; // 黑方提子数（显示在白子口袋）
  final int capByWhite; // 白方提子数（显示在黑子口袋）

  /// 是否显示棋盘坐标（A-T / 1-19）
  final bool showCoords;

  /// 棋子手数映射：棋盘点索引 → 第几手（为空时不显示手数）
  final Map<int, int> moveNumbers;

  /// 形势判断或终局点目时的领地归属：长度 n*n，0=无，1=黑方领地，2=白方领地
  final List<int>? territoryOwnerMap;

  /// 终局点目或形势判断中标记为死子的点集合
  final Set<int> deadStones;

  /// 13/19路防误触十字准星预览点（首次点击选中，再次点击确认落子）
  final int? previewPoint;
  final int previewColor;

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
    this.ghostStones = const {},
    this.glowCenter,
    this.glowRadius = 22,
    this.onPointTap,
    this.controller,
    this.capByBlack = 0,
    this.capByWhite = 0,
    this.showCoords = false,
    this.moveNumbers = const {},
    this.territoryOwnerMap,
    this.deadStones = const {},
    this.previewPoint,
    this.previewColor = 1,
  });

  @override
  State<WeiqiBoardView> createState() => _WeiqiBoardViewState();
}

class _WeiqiBoardViewState extends State<WeiqiBoardView>
    with TickerProviderStateMixin {
  static const double _pad = 6.2; // 棋盘边缘留白百分比（与测试点击映射一致）
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
      } catch (_) {}
    }
  }

  double _frac(int coord) => (_pad + coord * _step) / 100;
  double get _step => (100 - _pad * 2) / (widget.n - 1);
  double get _stoneScale => 8.0 / (widget.n - 1);

  Offset _pointOffset(int i, Size size) {
    return Offset(
      _frac(i % widget.n) * size.width,
      _frac(i ~/ widget.n) * size.height,
    );
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
    return LayoutBuilder(builder: (context, outer) {
      final maxW = outer.maxWidth;
      final maxH = outer.maxHeight;
      final boardSize = maxH.isFinite
          ? math.min(maxW, math.max(0.0, maxH - 72))
          : maxW;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: _pocketPill(
              color: 2,
              count: widget.capByBlack,
              label: '黑方提子',
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            key: const ValueKey('wq-board-square'),
            width: boardSize,
            height: boardSize,
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
                    // 孟菲斯粗黑描边 + 零模糊硬投影底座，内部保持经典护眼榧木色
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: WqTheme.ink, width: 3.0),
                        gradient: const RadialGradient(
                          center: Alignment(-0.6, -0.8),
                          radius: 1.4,
                          colors: [
                            Color(0xFFF2CD8C),
                            WqTheme.boardA,
                            WqTheme.boardB,
                          ],
                          stops: [0, 0.45, 1],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: WqTheme.ink,
                            offset: Offset(6, 6),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        size: size,
                        painter: _BoardPainter(
                          n: widget.n,
                          pad: _pad,
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
                          ghostStones: widget.ghostStones,
                          showCoords: widget.showCoords,
                          moveNumbers: widget.moveNumbers,
                          territoryOwnerMap: widget.territoryOwnerMap,
                          deadStones: widget.deadStones,
                          previewPoint: widget.previewPoint,
                          previewColor: widget.previewColor,
                        ),
                      ),
                    ),
                    // 提子飞行动画层
                    ..._flies.map((f) => AnimatedBuilder(
                          animation: f.ctrl,
                          builder: (context, _) {
                            final t =
                                Curves.easeInOutCubic.transform(f.ctrl.value);
                            final start = _pointOffset(f.point, size);
                            final end = Offset(
                              f.color == 2
                                  ? size.width * 0.90
                                  : size.width * 0.10,
                              f.color == 2 ? -8 : size.height + 8,
                            );
                            final pos = Offset.lerp(start, end, t)!;
                            final scale = 1 - 0.68 * t;
                            return Positioned(
                              left: pos.dx - size.width * 0.047 * _stoneScale,
                              top: pos.dy - size.width * 0.047 * _stoneScale,
                              child: Transform.scale(
                                scale: scale,
                                child: Opacity(
                                  opacity: (1 - t).clamp(0.0, 1.0),
                                  child: SizedBox(
                                    width: size.width * 0.094 * _stoneScale,
                                    height: size.width * 0.094 * _stoneScale,
                                    child: CustomPaint(
                                      painter: _StonePainter(
                                        color: f.color,
                                        boardSize: size.width,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: _pocketPill(
              color: 1,
              count: widget.capByWhite,
              label: '白方提子',
            ),
          ),
          const SizedBox(height: 2),
        ],
      );
    });
  }

  Widget _pocketPill({
    required int color,
    required int count,
    required String label,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WqTheme.ink, width: 2.0),
        boxShadow: const [
          BoxShadow(
            color: WqTheme.ink,
            blurRadius: 0,
            offset: Offset(2.5, 2.5),
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
              border: Border.all(color: WqTheme.ink, width: 1.2),
            ),
          ),
          const SizedBox(width: 5),
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
  final double pad;
  final List<int> stones;
  final int lastMove;
  final Set<int> breathePoints;
  final bool breatheWarn;
  final Set<int> blinkPoints;
  final int? glowCenter;
  final double glowRadius;
  final Animation<double> pulse;
  final Animation<double> pop;
  final int popPoint;
  final int? ghost;
  final int ghostColor;
  final Map<int, int> ghostStones;
  final bool showCoords;
  final Map<int, int> moveNumbers;
  final List<int>? territoryOwnerMap;
  final Set<int> deadStones;
  final int? previewPoint;
  final int previewColor;

  _BoardPainter({
    required this.n,
    required this.pad,
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
    required this.ghostStones,
    required this.showCoords,
    required this.moveNumbers,
    required this.territoryOwnerMap,
    required this.deadStones,
    required this.previewPoint,
    required this.previewColor,
  }) : super(repaint: Listenable.merge([pulse, pop]));

  double _stepFrac() => (100 - pad * 2) / (n - 1) / 100;
  double get _stoneScale => 8.0 / (n - 1);

  Offset _pt(int i, Size size) {
    final x = i % n, y = i ~/ n;
    return Offset(
      (pad + x * _stepFrac() * 100) / 100 * size.width,
      (pad + y * _stepFrac() * 100) / 100 * size.width,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (showCoords) _paintCoords(canvas, size);
    if (glowCenter != null) _paintGlow(canvas, size);
    if (previewPoint != null) _paintPreviewCrosshair(canvas, size);
    _paintStones(canvas, size);
    if (territoryOwnerMap != null) _paintTerritoryMarks(canvas, size);
    _paintBreathe(canvas, size);
    _paintBlink(canvas, size);
    if (ghost != null) {
      _paintOneStone(canvas, size, ghost!, ghostColor, alpha: 0.55);
    }
    if (previewPoint != null && stones[previewPoint!] == 0) {
      _paintOneStone(canvas, size, previewPoint!, previewColor, alpha: 0.68);
      final c = _pt(previewPoint!, size);
      canvas.drawCircle(
        c,
        size.width * 0.052 * _stoneScale,
        Paint()
          ..color = WqTheme.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.008,
      );
    }
    for (final e in ghostStones.entries) {
      if (stones[e.key] != 0) continue;
      _paintOneStone(canvas, size, e.key, e.value, alpha: 0.5);
      final c = _pt(e.key, size);
      canvas.drawCircle(
        c,
        size.width * 0.055 * _stoneScale,
        Paint()
          ..color = WqTheme.coral.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.009,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = WqTheme.line.withValues(alpha: 0.92)
      ..strokeWidth = (size.width * 0.0055).clamp(0.85, 1.7)
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < n; k++) {
      final p = pad + k * _stepFrac() * 100;
      final v = p / 100 * size.width;
      canvas.drawLine(
        Offset(pad / 100 * size.width, v),
        Offset((100 - pad) / 100 * size.width, v),
        line,
      );
      canvas.drawLine(
        Offset(v, pad / 100 * size.width),
        Offset(v, (100 - pad) / 100 * size.width),
        line,
      );
    }
    final star = Paint()..color = WqTheme.line;
    final edge = n >= 13 ? 3 : 2;
    final mid = n ~/ 2;
    final stars = n >= 13
        ? [
            for (final y in [edge, mid, n - 1 - edge])
              for (final x in [edge, mid, n - 1 - edge]) (x, y),
          ]
        : [
            (edge, edge),
            (n - 1 - edge, edge),
            (edge, n - 1 - edge),
            (n - 1 - edge, n - 1 - edge),
            (mid, mid),
          ];
    for (final (sx, sy) in stars) {
      if (sx >= n || sy >= n) continue;
      canvas.drawCircle(
        Offset(
          (pad + sx * _stepFrac() * 100) / 100 * size.width,
          (pad + sy * _stepFrac() * 100) / 100 * size.width,
        ),
        size.width * 0.012,
        star,
      );
    }
  }

  /// 绘制棋盘四周坐标（A-T / 1-19）
  void _paintCoords(Canvas canvas, Size size) {
    const cols = 'ABCDEFGHJKLMNOPQRST';
    final fontSize = (size.width * (n >= 19 ? 0.024 : 0.028)).clamp(7.5, 12.0);
    final style = TextStyle(
      color: WqTheme.line.withValues(alpha: 0.85),
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    );
    final margin = pad / 100 * size.width * 0.42;

    for (var k = 0; k < n; k++) {
      final pos = (pad + k * _stepFrac() * 100) / 100 * size.width;
      // 顶部与底部字母坐标
      final colLabel = k < cols.length ? cols[k] : '';
      final tpCol = TextPainter(
        text: TextSpan(text: colLabel, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tpCol.paint(
        canvas,
        Offset(pos - tpCol.width / 2, margin - tpCol.height / 2),
      );
      tpCol.paint(
        canvas,
        Offset(pos - tpCol.width / 2, size.height - margin - tpCol.height / 2),
      );

      // 左侧与右侧数字坐标
      final rowLabel = '${n - k}';
      final tpRow = TextPainter(
        text: TextSpan(text: rowLabel, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tpRow.paint(
        canvas,
        Offset(margin - tpRow.width / 2, pos - tpRow.height / 2),
      );
      tpRow.paint(
        canvas,
        Offset(size.width - margin - tpRow.width / 2, pos - tpRow.height / 2),
      );
    }
  }

  /// 绘制 13/19 路十字准星防误触引导线
  void _paintPreviewCrosshair(Canvas canvas, Size size) {
    final pt = previewPoint!;
    if (pt < 0 || pt >= n * n) return;
    final c = _pt(pt, size);
    final edgeStart = pad / 100 * size.width;
    final edgeEnd = (100 - pad) / 100 * size.width;
    final crossPaint = Paint()
      ..color = WqTheme.green.withValues(alpha: 0.72)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(edgeStart, c.dy), Offset(edgeEnd, c.dy), crossPaint);
    canvas.drawLine(Offset(c.dx, edgeStart), Offset(c.dx, edgeEnd), crossPaint);
  }

  void _paintStones(Canvas canvas, Size size) {
    for (var i = 0; i < stones.length; i++) {
      if (stones[i] == 0) continue;
      final isDead = deadStones.contains(i);
      final alpha = isDead ? 0.42 : 1.0;
      if (i == popPoint && pop.value < 1) {
        final t = Curves.easeOutBack.transform(pop.value);
        final scale = 1.6 - 0.6 * t;
        final c = _pt(i, size);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(scale);
        canvas.translate(-c.dx, -c.dy);
        _paintOneStone(canvas, size, i, stones[i], alpha: alpha);
        if (moveNumbers.containsKey(i)) {
          _paintMoveNumber(canvas, size, i, moveNumbers[i]!, stones[i]);
        } else if (i == lastMove) {
          _paintLastMark(canvas, size, i);
        }
        canvas.restore();
        continue;
      }
      _paintOneStone(canvas, size, i, stones[i], alpha: alpha);
      if (isDead) {
        _paintDeadCross(canvas, size, i);
      } else if (moveNumbers.containsKey(i)) {
        _paintMoveNumber(canvas, size, i, moveNumbers[i]!, stones[i]);
      } else if (i == lastMove) {
        _paintLastMark(canvas, size, i);
      }
    }
  }

  void _paintMoveNumber(
      Canvas canvas, Size size, int i, int moveNo, int stoneColor) {
    final c = _pt(i, size);
    final r = size.width * 0.047 * _stoneScale;
    final fontSize = (r * (moveNo >= 100 ? 0.82 : 0.98)).clamp(7.0, 14.0);
    final tp = TextPainter(
      text: TextSpan(
        text: '$moveNo',
        style: TextStyle(
          color: stoneColor == 1 ? Colors.white : WqTheme.ink,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
  }

  void _paintDeadCross(Canvas canvas, Size size, int i) {
    final c = _pt(i, size);
    final d = size.width * 0.024 * _stoneScale;
    final p = Paint()
      ..color = WqTheme.coral
      ..strokeWidth = (size.width * 0.008 * _stoneScale).clamp(1.5, 3.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - d, c.dy - d), Offset(c.dx + d, c.dy + d), p);
    canvas.drawLine(Offset(c.dx + d, c.dy - d), Offset(c.dx - d, c.dy + d), p);
  }

  /// 绘制形势判断 / 终局点目的黑白领地小方块
  void _paintTerritoryMarks(Canvas canvas, Size size) {
    final map = territoryOwnerMap!;
    final half = size.width * 0.017 * _stoneScale;
    for (var i = 0; i < map.length && i < n * n; i++) {
      final owner = map[i];
      if (owner != 1 && owner != 2) continue;
      final c = _pt(i, size);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: half * 2, height: half * 2),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = owner == 1 ? WqTheme.ink : Colors.white,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = owner == 1 ? Colors.white : WqTheme.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
  }

  void _paintLastMark(Canvas canvas, Size size, int i) {
    final c = _pt(i, size);
    canvas.drawCircle(
      c,
      size.width * 0.014 * _stoneScale,
      Paint()
        ..color = stones[i] == 1 ? WqTheme.sun : WqTheme.green,
    );
  }

  void _paintOneStone(
    Canvas canvas,
    Size size,
    int i,
    int color, {
    double alpha = 1.0,
  }) {
    final c = _pt(i, size);
    final r = size.width * 0.047 * _stoneScale;
    canvas.drawCircle(
      c.translate(0, size.width * 0.006 * _stoneScale),
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
              WqTheme.stoneBlackC,
            ]
          : const [
              WqTheme.stoneWhiteA,
              WqTheme.stoneWhiteB,
              WqTheme.stoneWhiteC,
            ],
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
    final scale = 0.82 + 0.18 * (t + 1) / 2 * 1.4;
    final opacity = 0.72 + 0.28 * (t + 1) / 2;
    final grad = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      colors: breatheWarn
          ? const [Color(0xFFFFE49A), Color(0xFFFFB020)]
          : const [Color(0xFFB8F1D4), Color(0xFF22C3B5)],
    );
    final ring = Paint()
      ..color = breatheWarn
          ? const Color(0xFFFFB020).withValues(alpha: 0.28 * opacity)
          : const Color(0xFF22C3B5).withValues(alpha: 0.25 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.008;
    for (final p in breathePoints) {
      final c = _pt(p, size);
      final r = size.width * 0.043 * _stoneScale * scale;
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
      final r = size.width * 0.046 * _stoneScale * scale;
      canvas.drawCircle(
        c,
        r,
        Paint()..color = WqTheme.sun.withValues(alpha: 0.28 * opacity),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = WqTheme.sun.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.01,
      );
    }
  }

  void _paintGlow(Canvas canvas, Size size) {
    final c = _pt(glowCenter!, size);
    final r = size.width * (glowRadius / 100) * 2;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = WqTheme.green.withValues(alpha: 0.12),
    );
    final dash = Paint()
      ..color = WqTheme.green.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.009;
    const segments = 28;
    final circumference = 2 * math.pi * r;
    final dashLen = circumference / segments * 0.55;
    final gapLen = circumference / segments * 0.45;
    var dist = 0.0;
    while (dist < circumference) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        dist / r,
        dashLen / r,
        false,
        dash,
      );
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
        old.showCoords != showCoords ||
        old.previewPoint != previewPoint ||
        old.previewColor != previewColor ||
        old.moveNumbers.length != moveNumbers.length ||
        old.territoryOwnerMap != territoryOwnerMap ||
        old.deadStones.length != deadStones.length ||
        old.ghostStones.length != ghostStones.length ||
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
      Paint()..shader = grad.createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _StonePainter old) => old.color != color;
}
