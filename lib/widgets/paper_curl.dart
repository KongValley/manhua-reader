import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

class PaperSheet {
  const PaperSheet(this.image, this.rect, {this.sourceRect});

  final ui.Image image;
  final Rect rect;
  final Rect? sourceRect;

  Rect get imageRect =>
      sourceRect ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
}

class PaperTurn {
  const PaperTurn({
    required this.outgoing,
    required this.incoming,
    required this.fromRight,
    required this.progress,
    required this.touchHeight,
  });

  final List<PaperSheet> outgoing;
  final List<PaperSheet> incoming;
  final bool fromRight;
  final double progress;
  final double touchHeight;
}

/// Paints a textured paper curl over the moving horizontal viewport.
/// 在横向翻页视口上绘制带有漫画纹理的纸张卷曲。
class PaperCurlPainter extends CustomPainter {
  PaperCurlPainter({
    required this.readTurn,
    required this.background,
    required super.repaint,
  });

  final PaperTurn? Function(Size size) readTurn;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final turn = readTurn(size);
    if (turn == null) return;

    final front = turn.fromRight ? turn.outgoing.last : turn.outgoing.first;
    final bound = turn.outgoing.length == 2 && turn.incoming.length == 2;
    final back = bound
        ? (turn.fromRight ? turn.incoming.first : turn.incoming.last)
        : null;
    final paper = _PaperCurve(turn, front.rect, back?.rect);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(background, BlendMode.srcOver);
    for (final sheet in turn.incoming) {
      _drawSheet(canvas, sheet, 1);
    }
    if (turn.outgoing.length == 2) {
      final stationary = turn.fromRight
          ? turn.outgoing.first
          : turn.outgoing.last;
      final fade = ((turn.progress - 0.72) / 0.27).clamp(0.0, 1.0);
      _drawSheet(canvas, stationary, 1 - fade * fade);
    }

    final bookBounds = [
      ...turn.outgoing,
      ...turn.incoming,
    ].map((sheet) => sheet.rect).reduce((a, b) => a.expandToInclude(b));
    _drawCastShadow(canvas, paper, bookBounds);
    if (back == null) canvas.clipRect(front.rect);
    _drawFace(canvas, paper, front, backFacing: false);
    _drawFace(canvas, paper, back, backFacing: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PaperCurlPainter oldDelegate) =>
      readTurn != oldDelegate.readTurn || background != oldDelegate.background;
}

class _PaperCurve {
  _PaperCurve(this.turn, this.front, this.back)
    : wave = math.sin(math.pi * turn.progress),
      direction = turn.fromRight ? 1 : -1,
      box = back == null ? front : Rect.lerp(front, back, turn.progress)!;

  final PaperTurn turn;
  final Rect front;
  final Rect? back;
  final double wave;
  final double direction;
  final Rect box;

  double get radius => 0.025 + 0.127 * wave;

  double get spine {
    final start = turn.fromRight ? front.left : front.right;
    final reverse = back;
    if (reverse == null) return start;
    final end = turn.fromRight ? reverse.right : reverse.left;
    return ui.lerpDouble(start, end, turn.progress * turn.progress)!;
  }

  double foldAt(double v) =>
      1 -
      1.23 * turn.progress +
      (v - 0.5) * (0.5 - turn.touchHeight) * 0.66 * wave;

  double faceEdge(double v) =>
      (foldAt(v) + radius * math.pi / 2).clamp(0.0, 1.0);

  // The sheet wraps around a cylinder, then flattens as its back comes into view.
  // 纸页绕圆柱弯曲，翻到背面后逐渐展开。
  double _project(double u, double fold) {
    final run = u - fold;
    if (run <= 0) return u;
    final arc = radius * math.pi;
    if (run >= arc) return fold - (run - arc);
    return fold + radius * math.sin(run / radius);
  }

  double angleAt(double u, double v) =>
      ((u - foldAt(v)) / radius).clamp(0.0, math.pi);

  Offset pointAt(double u, double v) {
    final fold = foldAt(v);
    final plane = back == null ? 0.0 : _project(0, fold);
    final across = spine + direction * box.width * (_project(u, fold) - plane);
    final lift = radius * (1 - math.cos(angleAt(u, v)));
    final along = box.top + box.height * (v + (0.5 - v) * 0.21 * lift * wave);
    return Offset(across, along);
  }
}

void _drawSheet(Canvas canvas, PaperSheet sheet, double opacity) {
  canvas.drawImageRect(
    sheet.image,
    sheet.imageRect,
    sheet.rect,
    Paint()
      ..color = Color.fromRGBO(255, 255, 255, opacity)
      ..filterQuality = FilterQuality.low,
  );
}

void _drawCastShadow(Canvas canvas, _PaperCurve paper, Rect bounds) {
  final top = paper.pointAt(paper.faceEdge(0), 0);
  final bottom = paper.pointAt(paper.faceEdge(1), 1);
  final reach = paper.box.width * (0.035 + 0.17 * paper.wave);
  final offset = Offset(reach * paper.direction, 0);
  final start = Offset.lerp(top, bottom, 0.5)!;
  final dark = Color.fromRGBO(13, 7, 2, 0.48 * paper.wave);
  final shadow = Path()
    ..moveTo(top.dx, top.dy)
    ..lineTo(top.dx + offset.dx, top.dy)
    ..lineTo(bottom.dx + offset.dx, bottom.dy)
    ..lineTo(bottom.dx, bottom.dy)
    ..close();
  canvas.save();
  canvas.clipRect(bounds);
  canvas.drawPath(
    shadow,
    Paint()
      ..shader = ui.Gradient.linear(
        start - offset * 0.18,
        start + offset * 0.84,
        [dark, dark.withValues(alpha: 0)],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
  );
  canvas.restore();
}

const _columns = 24;
const _rows = 8;
final _meshIndices = [
  for (var row = 0; row < _rows; row++)
    for (var column = 0; column < _columns; column++) ...[
      row * (_columns + 1) + column,
      row * (_columns + 1) + column + 1,
      (row + 1) * (_columns + 1) + column,
      row * (_columns + 1) + column + 1,
      (row + 1) * (_columns + 1) + column + 1,
      (row + 1) * (_columns + 1) + column,
    ],
];
final _identity = Float64List.fromList(const [
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  1,
]);

void _drawFace(
  Canvas canvas,
  _PaperCurve paper,
  PaperSheet? sheet, {
  required bool backFacing,
}) {
  final image = sheet?.image;
  final imageRect = sheet?.imageRect;
  final points = <Offset>[];
  final colors = <Color>[];
  final texture = image == null ? null : <Offset>[];
  final followsU = paper.turn.fromRight != backFacing;

  for (var row = 0; row <= _rows; row++) {
    final v = row / _rows;
    final edge = paper.faceEdge(v);
    final start = backFacing ? edge : 0.0;
    final end = backFacing ? 1.0 : edge;
    for (var column = 0; column <= _columns; column++) {
      final u = start + (end - start) * column / _columns;
      final angle = paper.angleAt(u, v);
      final bent = math.sin(angle);
      points.add(paper.pointAt(u, v));
      if (image == null) {
        final light = (0.44 + 0.43 * math.cos(angle - 2.45)).clamp(0.0, 1.0);
        colors.add(
          Color.lerp(const Color(0xFFBAA892), const Color(0xFFFFF8E9), light)!,
        );
      } else {
        final shade = 1 - (backFacing ? 0.35 : 0.28) * bent;
        final level = (shade * 255).round();
        colors.add(Color.fromARGB(255, level, level, level));
        texture!.add(
          Offset(
            imageRect!.left + (followsU ? u : 1 - u) * imageRect.width,
            imageRect.top + v * imageRect.height,
          ),
        );
      }
    }
  }

  final mesh = ui.Vertices(
    VertexMode.triangles,
    points,
    colors: colors,
    textureCoordinates: texture,
    indices: _meshIndices,
  );
  final shader = image == null
      ? null
      : ui.ImageShader(image, TileMode.clamp, TileMode.clamp, _identity);
  canvas.drawVertices(
    mesh,
    BlendMode.modulate,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..shader = shader
      ..filterQuality = FilterQuality.low,
  );
  mesh.dispose();
  shader?.dispose();
}
