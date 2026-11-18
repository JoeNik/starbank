import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 孟菲斯风格通用积木卡片组件
/// 特点：一块一色、粗黑描边（#111111）、右下零模糊硬投影；
/// 当提供 [onTap] 时，按下会向右下平移并收起硬投影，还原真实积木按压手感。
class MemphisCard extends StatefulWidget {
  /// 卡片内部子组件
  final Widget child;

  /// 卡片背景色（默认纯白，保证阅读区清晰）
  final Color color;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 外边距
  final EdgeInsetsGeometry? margin;

  /// 圆角半径（默认 18）
  final double borderRadius;

  /// 黑描边粗细（默认 2.5）
  final double borderWidth;

  /// 硬投影偏移量（默认 5.0）
  final double shadowOffset;

  /// 硬投影颜色（默认孟菲斯黑 #111111）
  final Color shadowColor;

  /// 点击回调（非空时启用按压位移反馈）
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  const MemphisCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding,
    this.margin,
    this.borderRadius = 18.0,
    this.borderWidth = 2.5,
    this.shadowOffset = 5.0,
    this.shadowColor = AppTheme.ink,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<MemphisCard> createState() => _MemphisCardState();
}

class _MemphisCardState extends State<MemphisCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final dx = _pressed ? widget.shadowOffset * 0.75 : 0.0;
    final remainShadow =
        _pressed ? math.max(0.0, widget.shadowOffset * 0.25) : widget.shadowOffset;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      margin: widget.margin,
      transform: Matrix4.translationValues(dx, dx, 0),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: AppTheme.ink,
          width: widget.borderWidth,
        ),
        boxShadow: remainShadow > 0
            ? [
                BoxShadow(
                  color: widget.shadowColor,
                  offset: Offset(remainShadow, remainShadow),
                  blurRadius: 0,
                ),
              ]
            : const [],
      ),
      child: widget.child,
    );

    if (!_interactive) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: card,
    );
  }
}

/// 孟菲斯风格按压位移按钮
/// 按下时向右下平移 (shadowOffset, shadowOffset) 并完全收回投影
class MemphisButton extends StatefulWidget {
  /// 按钮文字
  final String text;

  /// 前置图标或 Emoji 组件
  final Widget? leading;

  /// 点击事件
  final VoidCallback? onTap;

  /// 按钮填充色（默认柠檬黄 #FFD23F）
  final Color color;

  /// 文字颜色（默认孟菲斯黑 #111111）
  final Color textColor;

  /// 圆角半径（默认 14，设为 999 则为胶囊）
  final double borderRadius;

  /// 高度
  final double? height;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 字号
  final double fontSize;

  /// 硬投影偏移（默认 4.0）
  final double shadowOffset;

  const MemphisButton({
    super.key,
    required this.text,
    this.leading,
    this.onTap,
    this.color = AppTheme.yellow,
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

class _MemphisButtonState extends State<MemphisButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final shift = _pressed && enabled ? widget.shadowOffset : 0.0;
    final shadow = _pressed || !enabled ? 0.0 : widget.shadowOffset;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 75),
        height: widget.height,
        transform: Matrix4.translationValues(shift, shift, 0),
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? widget.color : const Color(0xFFE5E0D8),
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: AppTheme.ink,
            width: 2.5,
          ),
          boxShadow: shadow > 0
              ? [
                  BoxShadow(
                    color: AppTheme.ink,
                    offset: Offset(shadow, shadow),
                    blurRadius: 0,
                  ),
                ]
              : const [],
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
                  color: enabled ? widget.textColor : const Color(0xFF88847E),
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 孟菲斯风格圆形/圆角图标按钮（粗黑描边 + 硬投影）
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
    this.bgColor = Colors.white,
    this.iconColor = AppTheme.ink,
    this.size = 40.0,
    this.iconSize = 20.0,
    this.tooltip,
    this.isCircle = true,
  });

  @override
  State<MemphisIconButton> createState() => _MemphisIconButtonState();
}

class _MemphisIconButtonState extends State<MemphisIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final shift = _pressed ? 3.0 : 0.0;
    final shadow = _pressed ? 0.0 : 3.0;
    Widget btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.onTap != null ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 75),
        width: widget.size,
        height: widget.size,
        transform: Matrix4.translationValues(shift, shift, 0),
        decoration: BoxDecoration(
          color: widget.bgColor,
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius:
              widget.isCircle ? null : BorderRadius.circular(12),
          border: Border.all(color: AppTheme.ink, width: 2.2),
          boxShadow: shadow > 0
              ? [
                  BoxShadow(
                    color: AppTheme.ink,
                    offset: Offset(shadow, shadow),
                    blurRadius: 0,
                  ),
                ]
              : const [],
        ),
        child: Center(
          child: Icon(
            widget.icon,
            color: widget.iconColor,
            size: widget.iconSize,
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

/// 孟菲斯贴纸/胶囊标签组件
/// 支持按规则 04「歪着放 TILT」设置轻微旋转角度（如 -6°, 6°），默认 0°。
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
    Widget tag = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(pill ? 999 : 8),
        border: Border.all(color: AppTheme.ink, width: 2.0),
        boxShadow: shadowOffset > 0
            ? [
                BoxShadow(
                  color: AppTheme.ink,
                  offset: Offset(shadowOffset, shadowOffset),
                  blurRadius: 0,
                ),
              ]
            : const [],
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
              color: textColor,
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

/// 孟菲斯波浪线装饰组件（Squiggle）
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
    this.strokeWidth = 3.0,
    this.waves = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SquigglePainter(
          color: color,
          strokeWidth: strokeWidth,
          waves: waves,
        ),
      ),
    );
  }
}

class _SquigglePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int waves;

  const _SquigglePainter({
    required this.color,
    required this.strokeWidth,
    required this.waves,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final step = size.width / (waves * 2);
    final midY = size.height / 2;
    final amp = (size.height - strokeWidth) / 2;
    path.moveTo(0, midY);
    for (var i = 0; i < waves * 2; i++) {
      final x = (i + 1) * step;
      final y = i.isEven ? midY - amp : midY + amp;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SquigglePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.waves != waves;
}

/// 孟菲斯几何积木装饰小贴片（圆、三角、方块、半圆）
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
        painter: _ShapeBadgePainter(
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

class _ShapeBadgePainter extends CustomPainter {
  final MemphisShapeType shape;
  final Color color;
  final double shadowOffset;

  const _ShapeBadgePainter({
    required this.shape,
    required this.color,
    required this.shadowOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppTheme.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    final shadow = Paint()
      ..color = AppTheme.ink
      ..style = PaintingStyle.fill;

    void drawGeometry(Canvas c, Offset shift, bool isShadow) {
      c.save();
      c.translate(shift.dx, shift.dy);
      final w = size.width;
      final h = size.height;
      switch (shape) {
        case MemphisShapeType.circle:
          c.drawCircle(
            Offset(w / 2, h / 2),
            w * 0.42,
            isShadow ? shadow : fill,
          );
          if (!isShadow) {
            c.drawCircle(Offset(w / 2, h / 2), w * 0.42, stroke);
          }
          break;
        case MemphisShapeType.square:
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(w / 2, h / 2), width: w * 0.78, height: h * 0.78),
            const Radius.circular(4),
          );
          c.drawRRect(rect, isShadow ? shadow : fill);
          if (!isShadow) c.drawRRect(rect, stroke);
          break;
        case MemphisShapeType.triangle:
          final p = Path()
            ..moveTo(w / 2, h * 0.12)
            ..lineTo(w * 0.88, h * 0.84)
            ..lineTo(w * 0.12, h * 0.84)
            ..close();
          c.drawPath(p, isShadow ? shadow : fill);
          if (!isShadow) c.drawPath(p, stroke);
          break;
        case MemphisShapeType.halfCircle:
          final rect = Rect.fromCenter(
              center: Offset(w / 2, h * 0.62), width: w * 0.82, height: h * 0.82);
          final p = Path()
            ..arcTo(rect, math.pi, math.pi, false)
            ..close();
          c.drawPath(p, isShadow ? shadow : fill);
          if (!isShadow) c.drawPath(p, stroke);
          break;
        case MemphisShapeType.ring:
          final ringPaint = Paint()
            ..color = isShadow ? AppTheme.ink : color
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.22;
          c.drawCircle(Offset(w / 2, h / 2), w * 0.32, ringPaint);
          if (!isShadow) {
            c.drawCircle(Offset(w / 2, h / 2), w * 0.43, stroke);
            c.drawCircle(Offset(w / 2, h / 2), w * 0.21, stroke);
          }
          break;
      }
      c.restore();
    }

    if (shadowOffset > 0) {
      drawGeometry(canvas, Offset(shadowOffset, shadowOffset), true);
    }
    drawGeometry(canvas, Offset.zero, false);
  }

  @override
  bool shouldRepaint(covariant _ShapeBadgePainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.shadowOffset != shadowOffset;
}
