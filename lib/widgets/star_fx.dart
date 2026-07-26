import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// 首页加星/扣星的全屏反馈层：
/// 加星 → 五彩纸屑+星星从星星卡片位置喷发、"+N ⭐" 弹跳浮起、清脆铃音；
/// 扣星 → 委屈表情弹跳落下带泪滴、"-N ⭐" 下沉、温和的下行"呜"声。
class StarFx {
  static final GlobalKey<StarFxLayerState> layerKey =
      GlobalKey<StarFxLayerState>();

  static void celebrate(int amount) => layerKey.currentState?.celebrate(amount);

  static void pout(int amount) => layerKey.currentState?.pout(amount);
}

class _Sfx {
  static AudioPlayer? _gain;
  static AudioPlayer? _lose;

  static Future<void> _play(String asset, AudioPlayer? Function() get,
      void Function(AudioPlayer) set) async {
    try {
      var player = get();
      if (player == null) {
        player = AudioPlayer();
        set(player);
        await player.setAsset(asset);
      } else {
        await player.seek(Duration.zero);
      }
      player.play();
    } catch (_) {
      // 音效失败不影响功能
    }
  }

  static void gain() =>
      _play('assets/sfx/star_gain.wav', () => _gain, (p) => _gain = p);

  static void lose() =>
      _play('assets/sfx/star_lose.wav', () => _lose, (p) => _lose = p);
}

class StarFxLayer extends StatefulWidget {
  const StarFxLayer({super.key});

  @override
  State<StarFxLayer> createState() => StarFxLayerState();
}

class StarFxLayerState extends State<StarFxLayer>
    with TickerProviderStateMixin {
  static final _rand = math.Random();
  static const _confettiColors = [
    Color(0xFFFF6B9D), // 草莓粉
    Color(0xFFFF8E53), // 蜜桃橙
    Color(0xFFFFC371), // 杏黄
    Color(0xFFFFD84D), // 柠檬
    Color(0xFF7BD3A9), // 薄荷
    Color(0xFF6FB6F2), // 天空
    Color(0xFFA99BF0), // 香芋
  ];

  late final AnimationController _celebrateCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _celebrating = false);
      }
    });

  late final AnimationController _poutCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _pouting = false);
      }
    });

  List<_ConfettiPiece> _pieces = const [];
  List<_TearDrop> _tears = const [];
  int _amount = 0;
  bool _celebrating = false;
  bool _pouting = false;

  @override
  void dispose() {
    _celebrateCtrl.dispose();
    _poutCtrl.dispose();
    super.dispose();
  }

  void celebrate(int amount) {
    _amount = amount;
    _pieces = List.generate(56, (_) => _ConfettiPiece.random(_rand));
    setState(() => _celebrating = true);
    _celebrateCtrl.forward(from: 0);
    HapticFeedback.mediumImpact();
    _Sfx.gain();
  }

  void pout(int amount) {
    _amount = amount;
    _tears = List.generate(7, (_) => _TearDrop.random(_rand));
    setState(() => _pouting = true);
    _poutCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();
    _Sfx.lose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_celebrating && !_pouting) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_celebrating)
            AnimatedBuilder(
              animation: _celebrateCtrl,
              builder: (context, _) => _buildCelebrate(_celebrateCtrl.value),
            ),
          if (_pouting)
            AnimatedBuilder(
              animation: _poutCtrl,
              builder: (context, _) => _buildPout(_poutCtrl.value),
            ),
        ],
      ),
    );
  }

  // ------------------------ 加星：撒花 ------------------------

  Widget _buildCelebrate(double t) {
    final size = MediaQuery.sizeOf(context);
    // "+N ⭐" 弹性放大后上浮淡出
    final popIn = Curves.elasticOut.transform(math.min(1.0, t / 0.35));
    final fade = t < 0.62 ? 1.0 : (1 - (t - 0.62) / 0.38).clamp(0.0, 1.0);
    final rise = Curves.easeOutCubic.transform(t) * 64;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _ConfettiPainter(_pieces, t)),
        Positioned(
          left: 0,
          right: 0,
          top: size.height * 0.30 - rise,
          child: Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: popIn,
              child: Text(
                '+$_amount ⭐',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFF8E53),
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      blurRadius: 3,
                    ),
                    const Shadow(
                      color: Color(0x55D96B3B),
                      blurRadius: 16,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------ 扣星：委屈 ------------------------

  Widget _buildPout(double t) {
    final size = MediaQuery.sizeOf(context);
    // 表情弹性落下 → 左右委屈摇摆 → 下沉淡出
    final dropIn = Curves.elasticOut.transform(math.min(1.0, t / 0.4));
    final wobble = math.sin(t * math.pi * 6) * 0.07 * (1 - t);
    final sink = t < 0.72 ? 0.0 : Curves.easeIn.transform((t - 0.72) / 0.28);
    final fade = t < 0.72 ? 1.0 : (1 - sink).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _TearPainter(_tears, t)),
        Positioned(
          left: 0,
          right: 0,
          top: size.height * 0.26 + sink * 60,
          child: Opacity(
            opacity: fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: wobble,
                  child: Transform.scale(
                    scale: dropIn,
                    child: const Text(
                      '🥺',
                      style: TextStyle(
                        fontSize: 88,
                        shadows: [
                          Shadow(
                            color: Color(0x30000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Transform.scale(
                  scale: dropIn,
                  child: Text(
                    '-$_amount ⭐',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF5B8DEF),
                      shadows: [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.9),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 粒子
// ---------------------------------------------------------------------------

class _ConfettiPiece {
  _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
    required this.isStar,
  });

  factory _ConfettiPiece.random(math.Random rand) {
    // 向上的喷发锥形（-90° ± 65°）
    final angle = -math.pi / 2 + (rand.nextDouble() - 0.5) * 2.3;
    return _ConfettiPiece(
      angle: angle,
      speed: 0.55 + rand.nextDouble() * 0.9,
      size: 7 + rand.nextDouble() * 8,
      color: StarFxLayerState._confettiColors[
          rand.nextInt(StarFxLayerState._confettiColors.length)],
      spin: (rand.nextDouble() - 0.5) * 14,
      phase: rand.nextDouble() * math.pi * 2,
      isStar: rand.nextDouble() < 0.3,
    );
  }

  final double angle;
  final double speed; // 相对屏幕高度的初速度
  final double size;
  final Color color;
  final double spin;
  final double phase;
  final bool isStar;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_ConfettiPiece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.32);
    final paint = Paint();
    final fade = t < 0.65 ? 1.0 : (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0);
    for (final p in pieces) {
      final travel = Curves.easeOutCubic.transform(t);
      final vx = math.cos(p.angle) * p.speed * size.height * 0.42;
      final vy = math.sin(p.angle) * p.speed * size.height * 0.42;
      final x = origin.dx + vx * travel + math.sin(t * 5 + p.phase) * 9;
      final y = origin.dy + vy * travel + size.height * 0.55 * t * t; // 重力
      if (y > size.height + 20) continue;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t + p.phase);
      if (p.isStar) {
        canvas.drawPath(_starPath(p.size), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.62),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  Path _starPath(double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(math.cos(a) * radius, math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.pieces != pieces;
}

class _TearDrop {
  _TearDrop({
    required this.dx,
    required this.delay,
    required this.size,
    required this.drift,
  });

  factory _TearDrop.random(math.Random rand) => _TearDrop(
        dx: (rand.nextDouble() - 0.5) * 150,
        delay: rand.nextDouble() * 0.35,
        size: 4.5 + rand.nextDouble() * 4,
        drift: (rand.nextDouble() - 0.5) * 26,
      );

  final double dx;
  final double delay;
  final double size;
  final double drift;
}

class _TearPainter extends CustomPainter {
  _TearPainter(this.tears, this.t);

  final List<_TearDrop> tears;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.30);
    final paint = Paint();
    for (final tear in tears) {
      final local = ((t - tear.delay) / 0.9).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final fall = Curves.easeIn.transform(local);
      final x = origin.dx + tear.dx + tear.drift * local;
      final y = origin.dy + fall * size.height * 0.34;
      paint.color =
          const Color(0xFF8BB8E8).withValues(alpha: (1 - local) * 0.85);
      canvas.drawCircle(Offset(x, y), tear.size * (1 - local * 0.3), paint);
    }
  }

  @override
  bool shouldRepaint(_TearPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.tears != tears;
}
