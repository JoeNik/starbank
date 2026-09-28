import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'weiqi_panda.dart';
import 'weiqi_theme.dart';

/// 棋棋的对话气泡
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
          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: const Color(0x12233240)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1A23324D), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  WqPanda(mood: mood, size: 18),
                  SizedBox(width: 4.w),
                  const Text(
                    '棋棋',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: WqTheme.greenDeep,
                    ),
                  ),
                  if (speaking) ...[
                    SizedBox(width: 4.w),
                    const _SpeakWave(),
                  ],
                  const Spacer(),
                  if (onReplay != null)
                    GestureDetector(
                      onTap: onReplay,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(3.w),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 16,
                          color: WqTheme.greenDeep,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 2.h),
              Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.55,
                  color: WqTheme.ink,
                ),
              ),
            ],
          ),
        ),
        if (tail)
          Positioned(
            left: -4.5.w,
            top: 26.h,
            child: Transform.rotate(
              angle: 0.7854,
              child: Container(
                width: 11.w,
                height: 11.w,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: Color(0x12233240)),
                    bottom: BorderSide(color: Color(0x12233240)),
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
                color: WqTheme.green,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 主操作按钮（竹绿立体按钮）
class WqPrimaryButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final c = color ?? WqTheme.greenBright;
    final d = deep ?? WqTheme.greenDeep;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: height ?? 50.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c, d],
            ),
            boxShadow: [
              BoxShadow(color: d, offset: const Offset(0, 5), blurRadius: 0),
              BoxShadow(
                color: d.withValues(alpha: 0.28),
                offset: const Offset(0, 10),
                blurRadius: 20,
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize ?? 16.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 幽灵按钮（白底描边）
class WqGhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double? height;
  final double? fontSize;

  const WqGhostButton(
      {super.key, required this.text, this.onTap, this.height, this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: height ?? 44.h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: WqTheme.green, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3F34B37E),
                offset: Offset(0, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize ?? 14.5.sp,
                  fontWeight: FontWeight.w800,
                  color: WqTheme.greenDeep,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 彩色小胶囊标签
class WqChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Widget? icon;
  final double? fixedFontSize; // 弹层内用固定字号，不随视口缩放

  const WqChip({
    super.key,
    required this.text,
    this.bg = WqTheme.greenSoft,
    this.fg = WqTheme.greenDeep,
    this.icon,
    this.fixedFontSize,
  });

  factory WqChip.sun({required String text, Widget? icon}) => WqChip(
      text: text, bg: WqTheme.sunSoft, fg: WqTheme.sunDeep, icon: icon);

  factory WqChip.sky({required String text, Widget? icon}) => WqChip(
      text: text,
      bg: WqTheme.skySoft,
      fg: const Color(0xFF1976C2),
      icon: icon);

  factory WqChip.grape({required String text, Widget? icon}) => WqChip(
      text: text,
      bg: WqTheme.grapeSoft,
      fg: const Color(0xFF5B45D6),
      icon: icon);

  factory WqChip.coral({required String text, Widget? icon}) => WqChip(
      text: text,
      bg: WqTheme.coralSoft,
      fg: const Color(0xFFC2492B),
      icon: icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, SizedBox(width: 4.w)],
          Text(
            text,
            style: TextStyle(
              fontSize: fixedFontSize ?? 11.5.sp,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
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
        final star = Icon(
          Icons.star_rounded,
          size: size,
          color: on ? const Color(0xFFF0A81F) : const Color(0xFFE4E7EE),
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

/// 全屏彩带庆祝（点一下可跳过）
class WqConfetti extends StatefulWidget {
  final int count;

  const WqConfetti({super.key, this.count = 30});

  static Future<void> burst(BuildContext context, {int count = 30}) {
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
      Color(0xFFFFC53D),
      Color(0xFF3FC98B),
      Color(0xFFFF7A59),
      Color(0xFF6EC6FF),
      Color(0xFF9B8CFF),
    ];
    _particles = List.generate(widget.count, (k) {
      return _Particle(
        dx: (rnd.nextDouble() - 0.5) * 0.7,
        dy: 0.55 + rnd.nextDouble() * 0.5,
        rot: (rnd.nextDouble() - 0.5) * 8,
        size: 6 + rnd.nextDouble() * 8,
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
                        height: p.wide ? p.size : p.size * 0.5,
                        decoration: BoxDecoration(
                          color: p.color,
                          borderRadius: BorderRadius.circular(2),
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

/// 圆形返回/图标按钮
class WqIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  const WqIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.48, color: color ?? WqTheme.inkSoft),
        ),
      ),
    );
  }
}

/// 白色圆角卡片
class WqCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const WqCard({super.key, required this.child, this.padding, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: const Color(0x0F23324D), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x1A23324D), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}


/// 底部山丘 + 云朵背景（对应原型 .home-hills），放在页面 Stack 底层。
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
            painter: _HillsPainter(w: w, h: h),
          ),
        );
      }),
    );
  }
}

class _HillsPainter extends CustomPainter {
  final double w;
  final double h;

  _HillsPainter({required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    final hill1 = Paint()
      ..shader = const LinearGradient(colors: [
        Color(0xFFCDEEDD),
        Color(0xFFA8DFC0),
      ]).createShader(Rect.fromLTWH(0, h - 170, w, 170));
    canvas.drawCircle(Offset(w * 0.22, h + 66), w * 0.62, hill1);
    final hill2 = Paint()
      ..shader = const LinearGradient(colors: [
        Color(0xFFDDF3E6),
        Color(0xFFBFE7CF),
      ]).createShader(Rect.fromLTWH(0, h - 190, w, 190));
    canvas.drawCircle(Offset(w * 0.86, h + 88), w * 0.68, hill2);
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
    _cloud(canvas, Offset(w * 0.16, h * 0.06), 34, cloud);
    _cloud(canvas, Offset(w * 0.78, h * 0.115), 26, cloud);
  }

  void _cloud(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawCircle(Offset(c.dx, c.dy), r * 0.42, paint);
    canvas.drawCircle(Offset(c.dx - r * 0.55, c.dy + r * 0.1), r * 0.3, paint);
    canvas.drawCircle(Offset(c.dx + r * 0.55, c.dy + r * 0.12), r * 0.32, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: c.translate(0, r * 0.18), width: r * 1.7, height: r * 0.5),
        Radius.circular(r),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HillsPainter old) => false;
}
