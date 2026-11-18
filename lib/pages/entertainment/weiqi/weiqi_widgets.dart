import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'weiqi_panda.dart';
import 'weiqi_theme.dart';

/// 棋棋的孟菲斯风格对话气泡（白底 + 粗黑描边 + 零模糊硬投影）
class WqBubble extends StatelessWidget {
  final String text;
  final bool speaking;
  final WqPandaMood mood;

  final int maxLines;
  final bool tail;
  final VoidCallback? onReplay; // 语音重播：点击气泡里的小喇叭重听一遍

  const WqBubble({
    super.key,
    required this.text,
    this.speaking = false,
    this.mood = WqPandaMood.happy,
    this.maxLines = 4,
    this.tail = false,
    this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: WqTheme.ink, width: 2.4),
            boxShadow: const [
              BoxShadow(
                color: WqTheme.ink,
                blurRadius: 0,
                offset: Offset(4, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  WqPanda(mood: mood, size: 18),
                  SizedBox(width: 5.w),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: WqTheme.sun,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: WqTheme.ink, width: 1.5),
                    ),
                    child: const Text(
                      '棋棋',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: WqTheme.ink,
                      ),
                    ),
                  ),
                  if (speaking) ...[
                    SizedBox(width: 6.w),
                    const _SpeakWave(),
                  ],
                  const Spacer(),
                  if (onReplay != null)
                    GestureDetector(
                      onTap: onReplay,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: WqTheme.greenSoft,
                            shape: BoxShape.circle,
                            border: Border.all(color: WqTheme.ink, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.volume_up_rounded,
                            size: 15,
                            color: WqTheme.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 4.h),
              Flexible(
                child: Text(
                  text,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    height: 1.48,
                    color: WqTheme.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (tail)
          Positioned(
            left: -5.5.w,
            top: 24.h,
            child: Transform.rotate(
              angle: 0.7854,
              child: Container(
                width: 11.w,
                height: 11.w,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: WqTheme.ink, width: 2.4),
                    bottom: BorderSide(color: WqTheme.ink, width: 2.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 正在说话的声波小动画
class _SpeakWave extends StatefulWidget {
  const _SpeakWave();

  @override
  State<_SpeakWave> createState() => _SpeakWaveState();
}

class _SpeakWaveState extends State<_SpeakWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          children: List.generate(3, (k) {
            final phase = (_ctrl.value * 2 + k * 0.33) % 1;
            final h = 5.0 + 6.0 * (0.5 - (phase - 0.5).abs()) * 2;
            return Container(
              margin: const EdgeInsets.only(right: 2),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: WqTheme.ink,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 孟菲斯主操作按钮（单色填充 + 粗黑描边 + 右下零模糊硬投影，按下向右下位移并收回投影）
class WqPrimaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final Color? color;
  final Color? deep;
  final double? height;
  final double? fontSize;

  const WqPrimaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.color,
    this.deep,
    this.height,
    this.fontSize,
  });

  @override
  State<WqPrimaryButton> createState() => _WqPrimaryButtonState();
}

class _WqPrimaryButtonState extends State<WqPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final c = widget.color ?? WqTheme.green;
    final shift = _pressed && enabled ? 4.0 : 0.0;
    final shadow = _pressed || !enabled ? 0.0 : 4.0;
    final fg = (c == WqTheme.sky || c == WqTheme.coral)
        ? Colors.white
        : WqTheme.ink;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 75),
        height: widget.height ?? 48,
        alignment: Alignment.center,
        transform: Matrix4.translationValues(shift, shift, 0),
        decoration: BoxDecoration(
          color: enabled ? c : const Color(0xFFE5DFD5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WqTheme.ink, width: 2.5),
          boxShadow: shadow > 0
              ? [
                  BoxShadow(
                    color: WqTheme.ink,
                    offset: Offset(shadow, shadow),
                    blurRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              widget.text,
              maxLines: 1,
              style: TextStyle(
                fontSize: widget.fontSize ?? 15.5,
                fontWeight: FontWeight.w900,
                color: enabled ? fg : WqTheme.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 孟菲斯幽灵按钮（白底 + 粗黑描边 + 右下硬投影，按压位移收回投影）
class WqGhostButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final double? height;
  final double? fontSize;

  const WqGhostButton({
    super.key,
    required this.text,
    this.onTap,
    this.height,
    this.fontSize,
  });

  @override
  State<WqGhostButton> createState() => _WqGhostButtonState();
}

class _WqGhostButtonState extends State<WqGhostButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final shift = _pressed && enabled ? 3.5 : 0.0;
    final shadow = _pressed || !enabled ? 0.0 : 3.5;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 75),
        height: widget.height ?? 44,
        alignment: Alignment.center,
        transform: Matrix4.translationValues(shift, shift, 0),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFF2ECE1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? WqTheme.ink : const Color(0xFFB8B2A8),
            width: 2.3,
          ),
          boxShadow: shadow > 0
              ? [
                  BoxShadow(
                    color: WqTheme.ink,
                    offset: Offset(shadow, shadow),
                    blurRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              widget.text,
              maxLines: 1,
              style: TextStyle(
                fontSize: widget.fontSize ?? 14.0,
                fontWeight: FontWeight.w900,
                color: enabled ? WqTheme.ink : WqTheme.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 孟菲斯彩色小胶囊/贴纸标签（带黑描边与小硬投影，支持 tiltDeg 歪斜）
class WqChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Widget? icon;
  final double? fixedFontSize;
  final double tiltDeg;

  const WqChip({
    super.key,
    required this.text,
    this.bg = WqTheme.greenSoft,
    this.fg = WqTheme.ink,
    this.icon,
    this.fixedFontSize,
    this.tiltDeg = 0.0,
  });

  factory WqChip.sun({
    required String text,
    Widget? icon,
    double tiltDeg = 0.0,
  }) =>
      WqChip(
        text: text,
        bg: WqTheme.sun,
        fg: WqTheme.ink,
        icon: icon,
        tiltDeg: tiltDeg,
      );

  factory WqChip.sky({
    required String text,
    Widget? icon,
    double tiltDeg = 0.0,
  }) =>
      WqChip(
        text: text,
        bg: WqTheme.skySoft,
        fg: WqTheme.ink,
        icon: icon,
        tiltDeg: tiltDeg,
      );

  factory WqChip.grape({
    required String text,
    Widget? icon,
    double tiltDeg = 0.0,
  }) =>
      WqChip(
        text: text,
        bg: WqTheme.grape,
        fg: WqTheme.ink,
        icon: icon,
        tiltDeg: tiltDeg,
      );

  factory WqChip.coral({
    required String text,
    Widget? icon,
    double tiltDeg = 0.0,
  }) =>
      WqChip(
        text: text,
        bg: WqTheme.coral,
        fg: Colors.white,
        icon: icon,
        tiltDeg: tiltDeg,
      );

  factory WqChip.pink({
    required String text,
    Widget? icon,
    double tiltDeg = 0.0,
  }) =>
      WqChip(
        text: text,
        bg: WqTheme.pink,
        fg: WqTheme.ink,
        icon: icon,
        tiltDeg: tiltDeg,
      );

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.5.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WqTheme.ink, width: 1.8),
        boxShadow: const [
          BoxShadow(
            color: WqTheme.ink,
            offset: Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, SizedBox(width: 4.w)],
          Text(
            text,
            style: TextStyle(
              fontSize: fixedFontSize ?? 11.sp,
              fontWeight: FontWeight.w900,
              color: fg,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
    if (tiltDeg == 0) return chip;
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180.0,
      child: chip,
    );
  }
}

/// 1~3 星的一行（模块内课程星级，仅表示完成质量）
class WqStarsRow extends StatelessWidget {
  final int stars;
  final int total;
  final double size;
  final bool pop;

  const WqStarsRow({
    super.key,
    required this.stars,
    this.total = 3,
    this.size = 16,
    this.pop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (k) {
        final on = k < stars;
        final star = Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.star_rounded,
              size: size + 3,
              color: WqTheme.ink,
            ),
            Icon(
              Icons.star_rounded,
              size: size - 1,
              color: on ? WqTheme.sun : const Color(0xFFE4E0D8),
            ),
          ],
        );
        if (!pop || !on) return star;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 420 + k * 150),
          curve: Curves.easeOutBack,
          builder: (context, v, child) =>
              Transform.scale(scale: v, child: child),
          child: star,
        );
      }),
    );
  }
}

/// 全屏孟菲斯彩带纸屑庆祝
class WqConfetti extends StatefulWidget {
  final int count;

  const WqConfetti({super.key, this.count = 32});

  static Future<void> burst(BuildContext context, {int count = 32}) {
    final overlay = OverlayEntry(
      builder: (_) => WqConfetti(count: count),
    );
    Overlay.of(context).insert(overlay);
    return Future.delayed(const Duration(milliseconds: 2100), () {
      overlay.remove();
    });
  }

  @override
  State<WqConfetti> createState() => _WqConfettiState();
}

class _WqConfettiState extends State<WqConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    final rnd = math.Random();
    const colors = [
      WqTheme.sun,
      WqTheme.green,
      WqTheme.pink,
      WqTheme.sky,
      WqTheme.grape,
      WqTheme.coral,
    ];
    _particles = List.generate(widget.count, (k) {
      return _Particle(
        dx: (rnd.nextDouble() - 0.5) * 0.75,
        dy: 0.55 + rnd.nextDouble() * 0.5,
        rot: (rnd.nextDouble() - 0.5) * 8,
        size: 7 + rnd.nextDouble() * 8,
        color: colors[k % colors.length],
        delay: rnd.nextDouble() * 0.25,
        wide: rnd.nextBool(),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return LayoutBuilder(builder: (context, box) {
            return Stack(
              children: _particles.map((p) {
                final t = ((_ctrl.value - p.delay) / 1).clamp(0.0, 1.0);
                return Positioned(
                  left: box.maxWidth * (0.5 + p.dx * t),
                  top: box.maxHeight * 0.36 + box.maxHeight * p.dy * t,
                  child: Transform.rotate(
                    angle: p.rot * t,
                    child: Opacity(
                      opacity: 1 - t,
                      child: Container(
                        width: p.size,
                        height: p.wide ? p.size : p.size * 0.55,
                        decoration: BoxDecoration(
                          color: p.color,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: WqTheme.ink, width: 1.2),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          });
        },
      ),
    );
  }
}

class _Particle {
  final double dx, dy, rot, size, delay;
  final Color color;
  final bool wide;

  const _Particle({
    required this.dx,
    required this.dy,
    required this.rot,
    required this.size,
    required this.color,
    required this.delay,
    required this.wide,
  });
}

/// 孟菲斯圆形返回/图标按钮（粗黑描边 + 右下硬投影）
class WqIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? bgColor;

  const WqIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 42,
    this.color,
    this.bgColor,
  });

  @override
  State<WqIconButton> createState() => _WqIconButtonState();
}

class _WqIconButtonState extends State<WqIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final shift = _pressed && enabled ? 3.0 : 0.0;
    final shadow = _pressed || !enabled ? 0.0 : 3.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: widget.size,
        height: widget.size,
        transform: Matrix4.translationValues(shift, shift, 0),
        decoration: BoxDecoration(
          color: widget.bgColor ?? Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? WqTheme.ink : const Color(0xFFB8B2A8),
            width: 2.2,
          ),
          boxShadow: shadow > 0
              ? [
                  BoxShadow(
                    color: WqTheme.ink,
                    offset: Offset(shadow, shadow),
                    blurRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: Center(
          child: Icon(
            widget.icon,
            size: widget.size * 0.48,
            color: enabled
                ? (widget.color ?? WqTheme.ink)
                : WqTheme.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// 孟菲斯圆角卡片（单色底 + 粗黑描边 + 右下零模糊硬投影）
class WqCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double shadowOffset;

  const WqCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.shadowOffset = 4.5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: WqTheme.ink, width: 2.5),
        boxShadow: shadowOffset > 0
            ? [
                BoxShadow(
                  color: WqTheme.ink,
                  blurRadius: 0,
                  offset: Offset(shadowOffset, shadowOffset),
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}

/// 孟菲斯风格几何山丘 + 波浪线 + 圆点背景，放在页面 Stack 底层。
class WqHills extends StatelessWidget {
  const WqHills({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return SizedBox.expand(
          child: CustomPaint(
            painter: _MemphisHillsPainter(w: w, h: h),
          ),
        );
      }),
    );
  }
}

class _MemphisHillsPainter extends CustomPainter {
  final double w;
  final double h;

  _MemphisHillsPainter({required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 稀疏黑色圆点阵
    final dotPaint = Paint()
      ..color = WqTheme.ink.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    for (var y = 24.0; y < h; y += 36) {
      for (var x = 20.0; x < w; x += 36) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }

    // 2. 底部孟菲斯纯色几何山丘（带黑描边，无渐变）
    final stroke = Paint()
      ..color = WqTheme.ink.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final hill1Center = Offset(w * 0.22, h + 68);
    final hill1Radius = w * 0.62;
    canvas.drawCircle(
      hill1Center,
      hill1Radius,
      Paint()..color = WqTheme.greenSoft,
    );
    canvas.drawCircle(hill1Center, hill1Radius, stroke);

    final hill2Center = Offset(w * 0.86, h + 88);
    final hill2Radius = w * 0.68;
    canvas.drawCircle(
      hill2Center,
      hill2Radius,
      Paint()..color = WqTheme.sunSoft,
    );
    canvas.drawCircle(hill2Center, hill2Radius, stroke);

    // 3. 顶部孟菲斯几何积木与波浪线点缀
    _drawSquiggle(canvas, Offset(w * 0.16, h * 0.08), 52, WqTheme.pink, -0.18);
    _drawSquiggle(canvas, Offset(w * 0.82, h * 0.14), 48, WqTheme.green, 0.15);
  }

  void _drawSquiggle(
      Canvas canvas, Offset c, double width, Color color, double angle) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final path = Path();
    const waves = 4;
    final step = width / (waves * 2);
    path.moveTo(-width / 2, 0);
    for (var i = 0; i < waves * 2; i++) {
      path.lineTo(-width / 2 + (i + 1) * step, i.isEven ? -4.5 : 4.5);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MemphisHillsPainter old) => false;
}
