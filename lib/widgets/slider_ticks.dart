import 'package:flutter/material.dart';

/// Draws small marks along a [Slider]'s track at the given fractions, for
/// example bookmarked pages on the reader's progress slider.
///
/// Place it in a `Positioned.fill` above the Slider and inside the same
/// [SliderTheme] so the marks line up with the thumb's travel.
/// 在 [Slider] 轨道的指定比例位置绘制小刻度，例如阅读器进度条上的书签位置。
///
/// 放在 Slider 上方的 `Positioned.fill` 中，并与 Slider 处于同一个
/// [SliderTheme] 内，刻度就会与滑块的移动范围对齐。
class SliderTicks extends StatelessWidget {
  const SliderTicks({
    required this.fractions,
    required this.color,
    this.height = 10,
    this.width = 2,
    super.key,
  });

  final List<double> fractions;
  final Color color;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (fractions.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final theme = SliderTheme.of(context);
          // Ask the active track shape where its track lies instead of
          // copying the theme's padding rules here.
          // 直接询问当前轨道形状轨道的位置，不在这里复制主题的内边距规则。
          final shape = theme.trackShape;
          if (shape == null ||
              theme.thumbShape == null ||
              theme.overlayShape == null ||
              theme.trackHeight == null) {
            return const SizedBox.shrink();
          }
          final track = shape.getPreferredRect(
            parentBox: _SizeProbe(size),
            sliderTheme: theme,
            isEnabled: true,
            isDiscrete: false,
          );
          return CustomPaint(
            size: size,
            painter: _SliderTicksPainter(
              fractions: fractions,
              track: track,
              color: color,
              width: width,
              height: height,
            ),
          );
        },
      ),
    );
  }
}

class _SliderTicksPainter extends CustomPainter {
  const _SliderTicksPainter({
    required this.fractions,
    required this.track,
    required this.color,
    required this.width,
    required this.height,
  });

  final List<double> fractions;
  final Rect track;
  final Color color;
  final double width;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    if (track.width <= 0) return;
    final paint = Paint()..color = color;
    final radius = Radius.circular(width / 2);
    for (final fraction in fractions) {
      final x = track.left + fraction.clamp(0.0, 1.0) * track.width;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromCenter(
            center: Offset(x, track.center.dy),
            width: width,
            height: height,
          ),
          topLeft: radius,
          topRight: radius,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SliderTicksPainter oldDelegate) =>
      oldDelegate.fractions != fractions ||
      oldDelegate.track != track ||
      oldDelegate.color != color ||
      oldDelegate.width != width ||
      oldDelegate.height != height;
}

/// Render box that only reports a size, so a track shape can be asked for
/// its preferred rect before the real slider has been laid out.
/// 只报告尺寸的渲染盒，用于在真正的滑块完成布局前询问轨道形状的轨道位置。
class _SizeProbe extends RenderBox {
  _SizeProbe(this.fixedSize);

  final Size fixedSize;

  @override
  Size get size => fixedSize;

  @override
  Size computeDryLayout(BoxConstraints constraints) => fixedSize;

  @override
  void performLayout() {}
}
