import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Caps both texture edges and total pixel allocation while preserving aspect.
/// 在保持宽高比的同时限制纹理边长和像素总数。
ui.Size fitPageRasterSize(
  ui.Size source,
  ui.Size target, {
  int maxEdge = 4096,
  int maxPixels = 8 * 1024 * 1024,
}) {
  final scale = [
    target.width / source.width,
    target.height / source.height,
    maxEdge / source.longestSide,
    math.sqrt(maxPixels / (source.width * source.height)),
  ].reduce(math.min);
  return ui.Size(
    math.max(1, (source.width * scale).floor()).toDouble(),
    math.max(1, (source.height * scale).floor()).toDouble(),
  );
}

/// Uses the codec's real dimensions and only downscales the original image.
/// 使用编解码器提供的真实尺寸，原始图片只缩小、不放大。
Future<ui.Image> decodePageRaster(Uint8List bytes, ui.Size target) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final native = ui.Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      final size = fitPageRasterSize(
        native,
        ui.Size(
          math.min(target.width, native.width),
          math.min(target.height, native.height),
        ),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: size.width.toInt(),
        targetHeight: size.height.toInt(),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
