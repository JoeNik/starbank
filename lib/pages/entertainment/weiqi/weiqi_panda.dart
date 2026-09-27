import 'dart:math';

import 'package:flutter/material.dart';

/// 熊猫「棋棋」表情
enum WqPandaMood { happy, cheer, think, sad, wow }

/// 纯 CustomPainter 绘制的熊猫吉祥物（对应原型的 CSS 棋棋）。
class WqPanda extends StatelessWidget {
  final WqPandaMood mood;
  final double size;

  const WqPanda({super.key, this.mood = WqPandaMood.happy, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: mood == WqPandaMood.cheer ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: CustomPaint(
        size: Size(size, size),
        painter: _PandaPainter(mood),
      ),
    );
  }
}

class _PandaPainter extends CustomPainter {
  final WqPandaMood mood;

  _PandaPainter(this.mood);

  static const Color _dark = Color(0xFF2E2E38);
  static const Color _eye = Color(0xFF1D2433);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100; // 以 100 为逻辑坐标系
    // 头
    canvas.drawCircle(Offset(50 * s, 50 * s), 50 * s,
        Paint()..color = Colors.white);
    // 耳朵
    final ear = Paint()..color = _dark;
    canvas.drawCircle(Offset(15 * s, 9 * s), 17 * s, ear);
    canvas.drawCircle(Offset(85 * s, 9 * s), 17 * s, ear);
    // 眼圈（旋转椭圆）
    _drawEllipse(canvas, Offset(27.5 * s, 43 * s), 13.5 * s, 17 * s, -16 * pi / 180, ear);
    _drawEllipse(canvas, Offset(72.5 * s, 43 * s), 13.5 * s, 17 * s, 16 * pi / 180, ear);
    // 眼圈里的白点
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(29 * s, 40 * s), 6 * s, white);
    canvas.drawCircle(Offset(71 * s, 40 * s), 6 * s, white);
    // 眼睛
    final eyeScale = mood == WqPandaMood.wow ? 1.3 : 1.0;
    final eyeDy = mood == WqPandaMood.think ? -4.0 : 0.0;
    final eye = Paint()..color = _eye;
    canvas.drawCircle(Offset(34 * s, (44 + eyeDy) * s), 10 * s * eyeScale, eye);
    canvas.drawCircle(Offset(66 * s, (44 + eyeDy) * s), 10 * s * eyeScale, eye);
    // 鼻子
    _drawEllipse(canvas, Offset(50 * s, 60.5 * s), 6 * s, 4.5 * s, 0, ear);
    // 嘴
    final mouth = Paint()
      ..color = _dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * s
      ..strokeCap = StrokeCap.round;
    final mouthC = Offset(50 * s, 66 * s);
    switch (mood) {
      case WqPandaMood.cheer:
        final open = Paint()..color = const Color(0xFFB33A4D);
        canvas.drawCircle(mouthC, 8 * s, open);
        canvas.drawCircle(mouthC, 8 * s, mouth);
        break;
      case WqPandaMood.sad:
        canvas.drawArc(Rect.fromCircle(center: Offset(50 * s, 71 * s), radius: 7 * s), pi, pi, false, mouth);
        break;
      case WqPandaMood.think:
        canvas.drawArc(Rect.fromCircle(center: Offset(50 * s, 63 * s), radius: 5.5 * s), 0.15 * pi, 0.7 * pi, false, mouth);
        break;
      case WqPandaMood.wow:
        canvas.drawCircle(mouthC, 4.5 * s, mouth..style = PaintingStyle.fill);
        break;
      case WqPandaMood.happy:
        canvas.drawArc(Rect.fromCircle(center: Offset(50 * s, 63 * s), radius: 7 * s), 0.1 * pi, 0.8 * pi, false, mouth);
        break;
    }
    // 腮红
    final blush = Paint()..color = const Color(0xFFFF7A59).withValues(alpha: 0.35);
    _drawEllipse(canvas, Offset(16 * s, 57 * s), 8 * s, 5 * s, 0, blush);
    _drawEllipse(canvas, Offset(84 * s, 57 * s), 8 * s, 5 * s, 0, blush);
  }

  void _drawEllipse(Canvas canvas, Offset c, double rx, double ry,
      double rotation, Paint paint) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PandaPainter old) => old.mood != mood;
}
