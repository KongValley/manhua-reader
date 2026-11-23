import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'comic_source.dart';

/// Remembers automatic crop for one open source. Bounds use fractions of the
/// original page, so the same crop applies to every render resolution.
/// 保存一个已打开来源的自动裁边结果。边界使用原始页面的相对坐标，适用于所有渲染分辨率。
class ComicPageCropController extends ChangeNotifier {
  ComicPageCropController(this.source);

  static const fullPage = ui.Rect.fromLTWH(0, 0, 1, 1);
  static const _probeEdge = 384;

  final ComicSource source;
  final _inspected = <int>{};
  final _crops = <int, ({ui.Rect bounds, double imageAspect})>{};
  bool _disposed = false;

  ui.Rect boundsFor(int index) => _crops[index]?.bounds ?? fullPage;

  ui.Size pageSize(int index) {
    final original = ComicSource.safePageSize(source.pageSize(index));
    final crop = _crops[index];
    if (crop == null) return original;
    final aspect = (original.aspectRatio / crop.imageAspect - 1).abs() > 0.01
        ? crop.imageAspect
        : original.aspectRatio;
    return ui.Size(
      original.width * crop.bounds.width,
      original.width / aspect * crop.bounds.height,
    );
  }

  /// Borrows the image only during this call and samples at most once per page.
  /// 仅在调用期间借用图像，每页最多检测一次。
  void inspectPage(int index, ui.Image image) {
    if (_disposed ||
        image.width < 48 ||
        image.height < 48 ||
        !_inspected.add(index)) {
      return;
    }
    _inspectPage(index, image);
  }

  Future<void> _inspectPage(int index, ui.Image image) async {
    ui.Image? probe;
    try {
      final imageAspect = image.width / image.height;
      probe = _createProbe(image);
      final data = await probe.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (_disposed || data == null) return;
      final bounds = detectComicBorder(data, probe.width, probe.height);
      if (bounds != fullPage) {
        _crops[index] = (bounds: bounds, imageAspect: imageAspect);
        notifyListeners();
      }
    } catch (_) {
      // A failed readback leaves this page uncropped.
      // 读取像素失败时保留完整页面。
    } finally {
      probe?.dispose();
    }
  }

  static ui.Image _createProbe(ui.Image image) {
    final edge = math.max(image.width, image.height);
    if (edge <= _probeEdge) return image.clone();
    final factor = _probeEdge / edge;
    final width = math.max(1, (image.width * factor).round());
    final height = math.max(1, (image.height * factor).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Finds narrow, uninterrupted neutral or transparent edges followed by ink.
/// 检测狭窄、连续且内侧有明显内容的中性色或透明页边。
ui.Rect detectComicBorder(ByteData data, int width, int height) {
  if (width < 48 || height < 48 || data.lengthInBytes < width * height * 4) {
    return ComicPageCropController.fullPage;
  }
  final bytes = data.buffer.asUint8List(data.offsetInBytes, width * height * 4);

  _BorderTone toneAt(int pixel) {
    final offset = pixel * 4;
    final alpha = bytes[offset + 3];
    if (alpha <= 12) return _BorderTone.transparent;
    if (alpha < 250) return _BorderTone.other;
    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    if (red >= 245 && green >= 245 && blue >= 245) return _BorderTone.white;
    if (red <= 12 && green <= 12 && blue <= 12) return _BorderTone.black;
    return _BorderTone.other;
  }

  bool hasContrast(int pixel, _BorderTone tone) {
    final offset = pixel * 4;
    final alpha = bytes[offset + 3];
    if (tone == _BorderTone.transparent) return alpha >= 96;
    if (alpha < 215) return true;
    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    return tone == _BorderTone.white
        ? red < 211 || green < 211 || blue < 211
        : red > 44 || green > 44 || blue > 44;
  }

  int trim(int start, int across, int inward, int length, int extent) {
    final tone = toneAt(start);
    if (tone == _BorderTone.other) return 0;
    final maximum = (extent * 0.15).floor();
    var depth = 0;
    for (; depth <= maximum; depth++) {
      final line = start + depth * inward;
      var column = 0;
      for (; column < length; column++) {
        if (toneAt(line + column * across) != tone) break;
      }
      if (column < length) break;
    }
    const guard = 3;
    if (depth <= guard + 1 || depth > maximum) return 0;

    // Leave a guard strip and require a visible change just inside it.
    // 保留缓冲边缘，并要求紧邻内侧有显著内容变化。
    final minimumContrast = math.max(3, (length * 0.05).ceil());
    for (var offset = 0; offset < 3; offset++) {
      final line = start + (depth + offset) * inward;
      var contrast = 0;
      for (var column = 0; column < length; column++) {
        if (hasContrast(line + column * across, tone) &&
            ++contrast >= minimumContrast) {
          return depth - guard;
        }
      }
    }
    return 0;
  }

  final left = trim(0, width, 1, height, width);
  final top = trim(0, 1, width, width, height);
  final right = trim(width - 1, width, -1, height, width);
  final bottom = trim((height - 1) * width, 1, -width, width, height);
  return ui.Rect.fromLTRB(
    left / width,
    top / height,
    (width - right) / width,
    (height - bottom) / height,
  );
}

enum _BorderTone { transparent, white, black, other }
