import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// 通用 Q 弹弹簧按压包装器（Bouncy Spring Tap Wrapper）
/// 按下时快速缩至 [pressedScale]，松手时以 [Curves.elasticOut] Q 弹回跃至 1.0。
class BouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool enableHaptic;

  const BouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.92,
    this.enableHaptic = false,
  });

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _scaleAnim = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    if (!_enabled) return;
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 85);
    _scaleAnim = Tween<double>(
      begin: _scaleAnim.value,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuad));
    _ctrl.forward(from: 0);
  }

  void _up([TapUpDetails? _]) {
    if (!_enabled) return;
    _ctrl.stop();
    _ctrl.duration = const Duration(milliseconds: 520);
    _scaleAnim = Tween<double>(
      begin: _scaleAnim.value,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _up,
      onTap: () {
        if (widget.enableHaptic) HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: widget.child,
      ),
    );
  }
}

/// 中世纪现代（017 Mid-Century Modern）剪纸卡片组件
/// 遵循规则 01 & 02：
/// - 剪刀代替尺子：非对称微弧剪纸角、无粗黑描边；
/// - 影子 = 高度 (h)：暖深棕 #3A1C0C 高度投影；
/// - Q 弹物理交互：按下时纸片贴桌（h -> 2）并微缩，松开时以弹簧曲线 Q 弹跃起。
class MemphisCard extends StatefulWidget {
  /// 卡片内部子组件
  final Widget child;

  /// 卡片纸面背景色（默认暖白卡纸）
  final Color color;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 外边距
  final EdgeInsetsGeometry? margin;

  /// 圆角半径（默认 18）
  final double borderRadius;

  /// 保留兼容字段（中世纪现代风格不使用粗黑描边）
  final double borderWidth;

  /// 纸片高度基准值（默认 5.0，映射为桌面高度 h = shadowOffset * 1.8）
  final double shadowOffset;

  /// 投影颜色（默认暖深棕 #3A1C0C）
  final Color shadowColor;

  /// 点击回调（非空时启用 Q 弹按压与纸片高度变化）
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  const MemphisCard({
    super.key,
    required this.child,
    this.color = AppTheme.paperWhite,
    this.padding,
    this.margin,
    this.borderRadius = 18.0,
    this.borderWidth = 0.0,
    this.shadowOffset = 5.0,
    this.shadowColor = AppTheme.shadowBrown,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<MemphisCard> createState() => _MemphisCardState();
}

class _MemphisCardState extends State<MemphisCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late Animation<double> _scale;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (!_interactive) return;
    setState(() => _pressed = true);
    _bounceCtrl.stop();
    _bounceCtrl.duration = const Duration(milliseconds: 80);
    _scale = Tween<double>(begin: _scale.value, end: 0.94).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOutQuad),
    );
    _bounceCtrl.forward(from: 0);
  }

  void _onUp([TapUpDetails? _]) {
    if (!_interactive) return;
    setState(() => _pressed = false);
    _bounceCtrl.stop();
    _bounceCtrl.duration = const Duration(milliseconds: 500);
    _scale = Tween<double>(begin: _scale.value, end: 1.0).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut),
    );
    _bounceCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final baseH = widget.shadowOffset * 1.8;
    final currentH = _pressed ? 1.5 : baseH;
    final surfaceColor =
        widget.color == Colors.white ? AppTheme.paperWhite : widget.color;
    final r = widget.borderRadius;

    Widget card = AnimatedContainer(
      duration: Duration(milliseconds: _pressed ? 80 : 280),
      curve: Curves.easeOutCubic,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: surfaceColor,
        // 模拟手工剪纸的微妙非对称圆角
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r * 0.82),
          bottomLeft: Radius.circular(r * 0.88),
          bottomRight: Radius.circular(r * 1.06),
        ),
        border: Border.all(
          color: const Color(0x1C3A1C0C),
          width: 1.0,
        ),
        boxShadow: AppTheme.paperShadow(h: currentH),
      ),
      child: widget.child,
    );

    if (!_interactive) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onUp,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: card,
      ),
    );
  }
}

/// 中世纪现代剪纸按钮（带纸片高度阴影与 Q 弹回弹物理）
class MemphisButton extends StatefulWidget {
  final String text;
  final Widget? leading;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;
  final double borderRadius;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double fontSize;
  final double shadowOffset;

  const MemphisButton({
    super.key,
    required this.text,
    this.leading,
    this.onTap,
    this.color = AppTheme.tomato,
    this.textColor = AppTheme.ink,
    this.borderRadius = 14.0,
    this.height,
    this.padding,
    this.fontSize = 15.0,
    this.shadowOffset = 4.0,
  });

  @override
  State<MemphisButton> createState() => _MemphisButtonState();
}

class _MemphisButtonState extends State<MemphisButton>
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
    final h = _pressed || !enabled ? 0.0 : widget.shadowOffset * 1.9;
    final isDarkFill = widget.color == AppTheme.tomato ||
        widget.color == AppTheme.cobalt ||
        widget.color == AppTheme.ink;
    final effectiveTextColor = (widget.textColor == AppTheme.ink && isDarkFill)
        ? AppTheme.paperWhite
        : widget.textColor;
    final r = widget.borderRadius;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? _onDown : null,
      onTapUp: enabled ? _onUp : null,
      onTapCancel: enabled ? _onUp : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 75 : 260),
          height: widget.height,
          padding: widget.padding ??
              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: enabled ? widget.color : const Color(0xFFE5DCCB),
            borderRadius: r >= 100
                ? BorderRadius.circular(r)
                : BorderRadius.only(
                    topLeft: Radius.circular(r),
                    topRight: Radius.circular(r * 0.84),
                    bottomLeft: Radius.circular(r * 0.88),
                    bottomRight: Radius.circular(r * 1.08),
                  ),
            border: Border.all(
              color: const Color(0x223A1C0C),
              width: 1.0,
            ),
            boxShadow: AppTheme.paperShadow(h: h),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  widget.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? effectiveTextColor : AppTheme.textSub,
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 中世纪现代剪纸圆形/圆角图标按钮（暖棕高度投影 + Q 弹缩放）
class MemphisIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color bgColor;
  final Color iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool isCircle;

  const MemphisIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.bgColor = AppTheme.paperWhite,
    this.iconColor = AppTheme.ink,
    this.size = 40.0,
    this.iconSize = 20.0,
    this.tooltip,
    this.isCircle = true,
  });

  @override
  State<MemphisIconButton> createState() => _MemphisIconButtonState();
}

class _MemphisIconButtonState extends State<MemphisIconButton>
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
    final h = _pressed ? 0.0 : 6.0;
    final fill =
        widget.bgColor == Colors.white ? AppTheme.paperWhite : widget.bgColor;
    Widget btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? _onDown : null,
      onTapUp: widget.onTap != null ? _onUp : null,
      onTapCancel: widget.onTap != null ? _onUp : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 75 : 240),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: fill,
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle ? null : BorderRadius.circular(12),
            border: Border.all(color: const Color(0x223A1C0C), width: 1.0),
            boxShadow: AppTheme.paperShadow(h: h),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              color: widget.iconColor,
              size: widget.iconSize,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// 中世纪现代剪纸贴片标签组件
/// 支持按规则 01 设置轻微剪纸倾斜角度（±2°~3°），带贴桌高度阴影 h=4。
class MemphisTag extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final double tiltDeg;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final Widget? leading;
  final bool pill;
  final double shadowOffset;

  const MemphisTag({
    super.key,
    required this.text,
    this.color = AppTheme.yellow,
    this.textColor = AppTheme.ink,
    this.tiltDeg = 0.0,
    this.fontSize = 11.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.leading,
    this.pill = true,
    this.shadowOffset = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = color == AppTheme.tomato ||
        color == AppTheme.cobalt ||
        color == AppTheme.ink;
    final fg = (textColor == AppTheme.ink && isDark)
        ? AppTheme.paperWhite
        : textColor;

    Widget tag = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color == Colors.white ? AppTheme.paperWhite : color,
        borderRadius: pill
            ? BorderRadius.circular(999)
            : const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(9),
              ),
        border: Border.all(color: const Color(0x1E3A1C0C), width: 0.9),
        boxShadow: AppTheme.paperShadow(h: shadowOffset * 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ],
      ),
    );

    if (tiltDeg == 0) return tag;
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180.0,
      child: tag,
    );
  }
}

/// 中世纪现代 Eames Hang-It-All（钢丝折线 + 彩色木球）装饰分隔条
class MemphisSquiggle extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final double strokeWidth;
  final int waves;

  const MemphisSquiggle({
    super.key,
    this.width = 72,
    this.height = 12,
    this.color = AppTheme.ink,
    this.strokeWidth = 2.0,
    this.waves = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _HangItAllLinePainter(
          color: color,
          strokeWidth: strokeWidth,
          waves: waves,
        ),
      ),
    );
  }
}

class _HangItAllLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int waves;

  const _HangItAllLinePainter({
    required this.color,
    required this.strokeWidth,
    required this.waves,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制 Eames 钢丝折线 + 原子彩球
    final wirePaint = Paint()
      ..color = AppTheme.ink.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final step = size.width / (waves * 2);
    final midY = size.height / 2;
    final amp = (size.height - 4) / 2;
    path.moveTo(2, midY);
    for (var i = 0; i < waves * 2; i++) {
      final x = (i + 1) * step;
      final y = i.isEven ? midY - amp : midY + amp;
      path.lineTo(x.clamp(2.0, size.width - 2.0), y);
    }
    canvas.drawPath(path, wirePaint);

    // 节点彩球
    const ballColors = [
      AppTheme.tomato,
      AppTheme.yellow,
      AppTheme.teal,
      AppTheme.cobalt,
      AppTheme.pink,
    ];
    for (var i = 0; i < waves * 2; i += 2) {
      final x = ((i + 1) * step).clamp(3.0, size.width - 3.0);
      final y = i.isEven ? midY - amp : midY + amp;
      canvas.drawCircle(
        Offset(x, y),
        2.6,
        Paint()..color = ballColors[(i ~/ 2) % ballColors.length],
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HangItAllLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.waves != waves;
}

/// 中世纪现代原子时代几何零件贴片
/// 将原枚举映射为：
/// - circle -> 太阳圆盘 + 叠印月牙
/// - triangle -> 原子星芒 (Starburst)
/// - square -> 腰果/肾形 (Kidney Shape)
/// - halfCircle -> 回旋镖 (Boomerang)
/// - ring -> 原子轨道与球钟 (Atomic Orbit)
enum MemphisShapeType { circle, triangle, square, halfCircle, ring }

class MemphisShapeBadge extends StatelessWidget {
  final MemphisShapeType shape;
  final Color color;
  final double size;
  final double tiltDeg;
  final double shadowOffset;

  const MemphisShapeBadge({
    super.key,
    required this.shape,
    required this.color,
    this.size = 28,
    this.tiltDeg = 0,
    this.shadowOffset = 3,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MidCenturyBadgePainter(
          shape: shape,
          color: color,
          shadowOffset: shadowOffset,
        ),
      ),
    );
    if (tiltDeg == 0) return child;
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180.0,
      child: child,
    );
  }
}

class _MidCenturyBadgePainter extends CustomPainter {
  final MemphisShapeType shape;
  final Color color;
  final double shadowOffset;

  const _MidCenturyBadgePainter({
    required this.shape,
    required this.color,
    required this.shadowOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final shadowPaint = Paint()
      ..color = AppTheme.shadowBrown.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);

    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    switch (shape) {
      case MemphisShapeType.circle:
        // 太阳剪纸圆 + 叠印小圆
        if (shadowOffset > 0) {
          canvas.drawCircle(
            center.translate(shadowOffset * 0.5, shadowOffset),
            w * 0.40,
            shadowPaint,
          );
        }
        canvas.drawCircle(center, w * 0.40, fill);
        canvas.drawCircle(
          Offset(w * 0.64, h * 0.36),
          w * 0.20,
          Paint()
            ..color = AppTheme.yellow.withValues(alpha: 0.78)
            ..blendMode = BlendMode.multiply,
        );
        break;

      case MemphisShapeType.triangle:
        // 八芒原子星芒 (Starburst)
        final starPath = _buildStarburstPath(center, w * 0.46, w * 0.14, 8);
        if (shadowOffset > 0) {
          canvas.save();
          canvas.translate(shadowOffset * 0.5, shadowOffset);
          canvas.drawPath(starPath, shadowPaint);
          canvas.restore();
        }
        canvas.drawPath(starPath, fill);
        canvas.drawCircle(center, w * 0.10, Paint()..color = AppTheme.cream);
        break;

      case MemphisShapeType.square:
        // 1950s 有机腰果/肾形剪纸 (Kidney / Palette)
        final kidney = Path()
          ..moveTo(w * 0.22, h * 0.26)
          ..cubicTo(w * 0.52, h * 0.06, w * 0.92, h * 0.18, w * 0.86, h * 0.54)
          ..cubicTo(w * 0.82, h * 0.88, w * 0.42, h * 0.94, w * 0.18, h * 0.72)
          ..cubicTo(w * 0.04, h * 0.56, w * 0.34, h * 0.50, w * 0.22, h * 0.26)
          ..close();
        if (shadowOffset > 0) {
          canvas.save();
          canvas.translate(shadowOffset * 0.5, shadowOffset);
          canvas.drawPath(kidney, shadowPaint);
          canvas.restore();
        }
        canvas.drawPath(kidney, fill);
        break;

      case MemphisShapeType.halfCircle:
        // Formica 1950 回旋镖 (Boomerang)
        final boom = Path()
          ..moveTo(w * 0.10, h * 0.72)
          ..quadraticBezierTo(w * 0.46, h * 0.08, w * 0.90, h * 0.32)
          ..quadraticBezierTo(w * 0.52, h * 0.42, w * 0.10, h * 0.72)
          ..close();
        if (shadowOffset > 0) {
          canvas.save();
          canvas.translate(shadowOffset * 0.5, shadowOffset);
          canvas.drawPath(boom, shadowPaint);
          canvas.restore();
        }
        canvas.drawPath(boom, fill);
        break;

      case MemphisShapeType.ring:
        // George Nelson 原子球钟 / 轨道
        final spokePaint = Paint()
          ..color = AppTheme.ink.withValues(alpha: 0.75)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final p = Offset(
            center.dx + math.cos(a) * w * 0.38,
            center.dy + math.sin(a) * h * 0.38,
          );
          canvas.drawLine(center, p, spokePaint);
          canvas.drawCircle(
            p,
            w * 0.08,
            Paint()..color = i.isEven ? color : AppTheme.yellow,
          );
        }
        canvas.drawCircle(center, w * 0.14, fill);
        break;
    }
  }

  Path _buildStarburstPath(
      Offset center, double outerR, double innerR, int points) {
    final path = Path();
    final total = points * 2;
    for (var i = 0; i < total; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = i * math.pi / points - math.pi / 2;
      final x = center.dx + math.cos(a) * r;
      final y = center.dy + math.sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _MidCenturyBadgePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.shadowOffset != shadowOffset;
}
