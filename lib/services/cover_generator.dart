import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Generates small PNG cover thumbnails for the library grid.
class CoverGenerator {
  static const int _coverWidth = 520;

  /// Downscales an embedded image (used for MOBI pages) into [outputPath].
  static Future<String?> fromImageBytes(
    Uint8List bytes,
    String outputPath,
  ) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _coverWidth,
      );
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          return await _writePng(image, outputPath);
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (error, stack) {
      debugPrint('Cover generation failed: $error\n$stack');
      return null;
    }
  }

  /// Renders page 1 of [document] into [outputPath].
  static Future<String?> fromPdf(
    PdfDocument document,
    String outputPath,
  ) async {
    if (document.pages.isEmpty) return null;
    PdfImage? pdfImage;
    ui.Image? image;
    try {
      final page = document.pages.first;
      final width = _coverWidth.toDouble();
      final height = (width * page.height / page.width).clamp(1.0, 4000.0);
      pdfImage = await page.render(
        fullWidth: width,
        fullHeight: height,
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImage == null) return null;
      image = await pdfImage.createImage();
      return await _writePng(image, outputPath);
    } catch (error, stack) {
      debugPrint('PDF cover generation failed: $error\n$stack');
      return null;
    } finally {
      image?.dispose();
      pdfImage?.dispose();
    }
  }

  static Future<String?> _writePng(ui.Image image, String outputPath) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }
}
