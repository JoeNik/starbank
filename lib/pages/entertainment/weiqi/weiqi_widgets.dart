import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'weiqi_panda.dart';
import 'weiqi_theme.dart';

/// 棋棋的中世纪现代（017 Mid-Century Modern）剪纸对话气泡
/// 核心防跳动设计：
/// 默认固定高度 [fixedHeight]（并在矮屏下按父容器约束自动钳制），内部文字区域采用 [Expanded] 恒定槽位。
/// 无论提示语是 1 行短句还是 3~4 行长句，气泡外部总高度恒定不变，确保下方棋盘永不发生位置或尺寸跳动！
class WqBubble extends StatelessWidget {
  final String text;
  final bool speaking;
  final WqPandaMood mood;

  final int maxLines;
  final bool tail;
  final VoidCallback? onReplay; // 语音重播：点击气泡里的小喇叭重听一遍
  final double fixedHeight;

  const WqBubble({
    super.key,
    required this.text,
    this.speaking = false,
    this.mood = WqPandaMood.happy,
    this.maxLines = 3,
    this.tail = false,
    this.onReplay,
    this.fixedHeight = 84.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 在常规屏幕下锁定为 fixedHeight，极端矮横屏下不超过父约束 maxHeight，兼顾防跳动与防溢出
      final targetH = constraints.hasBoundedHeight
          ? math.min(fixedHeight, constraints.maxHeight)
          : fixedHeight;

      return SizedBox(
        height: targetH,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 6.h),
              decoration: BoxDecoration(
                color: WqTheme.card,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18.r),
                  topRight: Radius.circular(14.r),
                  bottomLeft: Radius.circular(15.r),
                  bottomRight: Radius.circular(19.r),
                ),
                border: WqTheme.border(),
                boxShadow: WqTheme.paperShadow(h: 7.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      WqPanda(mood: mood, size: 17),
                      SizedBox(width: 5.w),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: WqTheme.sun,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '棋棋',
                          style: TextStyle(
                            fontSize: 10.0,
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
                            padding: EdgeInsets.symmetric(
                                horizontal: 4.w, vertical: 1.h),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: WqTheme.greenSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.volume_up_rounded,
                                size: 14,
                                color: WqTheme.ink,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          );
                        },
                        child: Text(
                          text,
                          key: ValueKey<String>(text),
                          maxLines: maxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.2.sp,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                            color: WqTheme.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (tail)
              Positioned(
                left: -5.w,
                top: 22.h,
                child: Transform.rotate(
                  angle: 0.7854,
                  child: Container(
                    width: 10.w,
                    height: 10.w,
                    decoration: const BoxDecoration(
                      color: WqTheme.card,
                      border: Border(
                        left: BorderSide(color: Color(0x223A1C0C), width: 1.0),
                        bottom:
                            BorderSide(color: Color(0x223A1C0C), width: 1.0),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
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
            final h = 4.5 + 5.5 * (0.5 - (phase - 0.5).abs()) * 2;
            return Container(
              margin: const EdgeInsets.only(right: 2),
              width: 2.8,
              height: h,
              decoration: BoxDecoration(
                color: WqTheme.coral,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 中世纪现代主操作按钮（剪纸色块 + 暖棕高度阴影 h + Q 弹弹簧按压物理）
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

class _WqPrimaryButtonState extends State<WqPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _pressed = true);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 75);
    _scale = Tween<double>(begin: _scale.value, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuad),
    );
    _ctrl.forward(from: 0);
  }

  void _onUp([TapUpDetails? _]) {
    if (widget.onTap == null) return;
    setState(() => _pressed = false);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 520);
    _scale = Tween<double>(begin: _scale.value, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final c = widget.color ?? WqTheme.coral;
    final h = _pressed || !enabled ? 0.0 : 8.5;
    final fg = (c == WqTheme.sky || c == WqTheme.coral || c == WqTheme.ink)
        ? WqTheme.card
        : WqTheme.ink;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _onDown : null,
      onTapUp: enabled ? _onUp : null,
      onTapCancel: enabled ? _onUp : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 75 : 240),
          height: widget.height ?? 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? c : const Color(0xFFE5DCCB),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(13),
              bottomRight: Radius.circular(16),
            ),
            border: WqTheme.border(),
            boxShadow: WqTheme.paperShadow(h: h),
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
      ),
    );
  }
}

/// 中世纪现代次级剪纸按钮（暖白卡纸底 + 暖棕高度阴影 + Q 弹回弹）
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

class _WqGhostButtonState extends State<WqGhostButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _pressed = true);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 75);
    _scale = Tween<double>(begin: _scale.value, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuad),
    );
    _ctrl.forward(from: 0);
  }

  void _onUp([TapUpDetails? _]) {
    if (widget.onTap == null) return;
    setState(() => _pressed = false);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 520);
    _scale = Tween<double>(begin: _scale.value, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final h = _pressed || !enabled ? 0.0 : 6.5;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _onDown : null,
      onTapUp: enabled ? _onUp : null,
      onTapCancel: enabled ? _onUp : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 75 : 240),
          height: widget.height ?? 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? WqTheme.card : const Color(0xFFF2ECE1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(11),
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(15),
            ),
            border: WqTheme.border(),
            boxShadow: WqTheme.paperShadow(h: h),
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
      ),
    );
  }
}

/// 中世纪现代剪纸小胶囊/贴片标签（无粗黑边 + 贴桌高度阴影 h=4，支持 tiltDeg 微斜）
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
        bg: WqTheme.grapeSoft,
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
        color: bg == Colors.white ? WqTheme.card : bg,
        borderRadius: BorderRadius.circular(999),
        border: WqTheme.border(),
        boxShadow: WqTheme.paperShadow(h: 4.0),
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
        final star = Icon(
          Icons.star_rounded,
          size: size + 2,
          color: on ? WqTheme.sun : const Color(0xFFE4DDD0),
          shadows: on
              ? [
                  Shadow(
                    color: WqTheme.shadowBrown.withValues(alpha: 0.25),
                    offset: const Offset(1.5, 2.5),
                    blurRadius: 2.0,
                  ),
                ]
              : null,
        );
        if (!pop || !on) return star;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 520 + k * 140),
          curve: Curves.elasticOut,
          builder: (context, v, child) =>
              Transform.scale(scale: v, child: child),
          child: star,
        );
      }),
    );
  }
}

/// 全屏中世纪现代剪纸边角料庆祝特效（规则 05：大落地溅起彩纸碎片）
class WqConfetti extends StatefulWidget {
  final int count;
  final VoidCallback? onCompleted;

  const WqConfetti({super.key, this.count = 32, this.onCompleted});

  static Future<void> burst(BuildContext context, {int count = 32}) async {
    late final OverlayEntry overlay;
    overlay = OverlayEntry(
      builder: (_) => WqConfetti(
        count: count,
        onCompleted: () {
          if (overlay.mounted) {
            overlay.remove();
          }
        },
      ),
    );
    Overlay.of(context).insert(overlay);
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
    )..forward().whenComplete(() {
        widget.onCompleted?.call();
      });
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
                          boxShadow: [
                            BoxShadow(
                              color: WqTheme.shadowBrown.withValues(alpha: 0.2),
                              offset: const Offset(1, 2),
                              blurRadius: 2,
                            ),
                          ],
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

/// 中世纪现代剪纸圆形图标按钮（暖棕高度阴影 + Q 弹缩放物理）
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

class _WqIconButtonState extends State<WqIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _pressed = true);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 70);
    _scale = Tween<double>(begin: _scale.value, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuad),
    );
    _ctrl.forward(from: 0);
  }

  void _onUp([TapUpDetails? _]) {
    if (widget.onTap == null) return;
    setState(() => _pressed = false);
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 500);
    _scale = Tween<double>(begin: _scale.value, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final h = _pressed || !enabled ? 0.0 : 6.0;
    final fill = widget.bgColor == null || widget.bgColor == Colors.white
        ? WqTheme.card
        : widget.bgColor!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _onDown : null,
      onTapUp: enabled ? _onUp : null,
      onTapCancel: enabled ? _onUp : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 70 : 220),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: WqTheme.border(),
            boxShadow: WqTheme.paperShadow(h: h),
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
      ),
    );
  }
}

/// 中世纪现代剪纸圆角卡片（暖白卡纸 + 非对称剪纸角 + 暖棕高度阴影 h）
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
    final fill =
        color == null || color == Colors.white ? WqTheme.card : color!;
    return Container(
      padding: padding ?? EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20.r),
          topRight: Radius.circular(16.r),
          bottomLeft: Radius.circular(17.r),
          bottomRight: Radius.circular(22.r),
        ),
        border: WqTheme.border(),
        boxShadow: WqTheme.paperShadow(h: shadowOffset * 1.8),
      ),
      child: child,
    );
  }
}

/// 中世纪现代风格剪纸山丘 + 叠印太阳 + 原子球钟与八芒星背景，包裹 RepaintBoundary 零重绘开销。
class WqHills extends StatelessWidget {
  const WqHills({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          return SizedBox.expand(
            child: CustomPaint(
              painter: _MidCenturyHillsPainter(w: w, h: h),
            ),
          );
        }),
      ),
    );
  }
}

class _MidCenturyHillsPainter extends CustomPainter {
  final double w;
  final double h;

  _MidCenturyHillsPainter({required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 底部中世纪现代剪纸山丘（绿松石 + 向日葵黄叠印，带暖棕高度阴影）
    final hill1Center = Offset(w * 0.22, h + 68);
    final hill1Radius = w * 0.62;
    canvas.drawCircle(
      hill1Center.translate(0, -6),
      hill1Radius,
      Paint()
        ..color = WqTheme.shadowBrown.withValues(alpha: 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      hill1Center,
      hill1Radius,
      Paint()..color = WqTheme.greenSoft,
    );

    final hill2Center = Offset(w * 0.86, h + 88);
    final hill2Radius = w * 0.68;
    canvas.drawCircle(
      hill2Center,
      hill2Radius,
      Paint()
        ..color = WqTheme.sunSoft
        ..blendMode = BlendMode.multiply,
    );

    // 2. 顶部 George Nelson 原子球钟局部与钴蓝八芒星
    final clockCenter = Offset(w * 0.86, h * 0.12);
    final spokePaint = Paint()
      ..color = WqTheme.ink.withValues(alpha: 0.14)
      ..strokeWidth = 1.3;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final tip = Offset(
        clockCenter.dx + math.cos(a) * 32,
        clockCenter.dy + math.sin(a) * 32,
      );
      canvas.drawLine(clockCenter, tip, spokePaint);
      canvas.drawCircle(
        tip,
        3.2,
        Paint()
          ..color = (i.isEven ? WqTheme.coral : WqTheme.green)
              .withValues(alpha: 0.45),
      );
    }
    canvas.drawCircle(
      clockCenter,
      6.0,
      Paint()..color = WqTheme.sun.withValues(alpha: 0.65),
    );

    // 左上八芒星
    final starCenter = Offset(w * 0.14, h * 0.09);
    final starPath = Path();
    for (var i = 0; i < 16; i++) {
      final r = i.isEven ? 16.0 : 4.5;
      final a = i * math.pi / 8 - math.pi / 2;
      final pt = Offset(
        starCenter.dx + math.cos(a) * r,
        starCenter.dy + math.sin(a) * r,
      );
      if (i == 0) {
        starPath.moveTo(pt.dx, pt.dy);
      } else {
        starPath.lineTo(pt.dx, pt.dy);
      }
    }
    starPath.close();
    canvas.drawPath(
      starPath,
      Paint()..color = WqTheme.sky.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(covariant _MidCenturyHillsPainter old) => false;
}
