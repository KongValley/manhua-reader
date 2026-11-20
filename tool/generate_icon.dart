import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int _size = 1024;
const double _radius = 230;

void main() {
  final master = _drawIcon(rounded: true);
  final square = _drawIcon(rounded: false);

  final buildDir = Directory('build/icon')..createSync(recursive: true);
  File('${buildDir.path}/app_icon_1024.png')
      .writeAsBytesSync(img.encodePng(master));

  const androidSizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final entry in androidSizes.entries) {
    final dir = Directory('android/app/src/main/res/${entry.key}')
      ..createSync(recursive: true);
    final resized = _resize(master, entry.value);
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(resized));
  }

  final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosDir.existsSync()) {
    const iosIcons = {
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final entry in iosIcons.entries) {
      final image = entry.value == 1024 ? square : _resize(square, entry.value);
      File('${iosDir.path}/${entry.key}')
          .writeAsBytesSync(img.encodePng(image));
    }
  }

  final icoSizes = [16, 24, 32, 48, 64, 128, 256];
  final icoImages = [for (final size in icoSizes) _resize(master, size)];
  final icoBytes = img.IcoEncoder().encodeImages(icoImages);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoBytes);

  stdout.writeln('Generated app icons (${icoSizes.join(', ')} px ICO).');
}

img.Image _drawIcon({required bool rounded}) {
  final image = img.Image(width: _size, height: _size, numChannels: 4);

  const top = [255, 197, 112];
  const bottom = [242, 108, 55];
  for (var y = 0; y < _size; y++) {
    final t = y / (_size - 1);
    final inset = rounded ? _cornerInset(y.toDouble()) : 0;
    final color = img.ColorRgba8(
      _lerp(top[0], bottom[0], t),
      _lerp(top[1], bottom[1], t),
      _lerp(top[2], bottom[2], t),
      255,
    );
    img.fillRect(
      image,
      x1: inset,
      y1: y,
      x2: _size - 1 - inset,
      y2: y,
      color: color,
    );
  }

  // Warm gradient background.
  // 暖色渐变背景。
  final cream = img.ColorRgba8(255, 249, 238, 255);
  final creamShade = img.ColorRgba8(249, 236, 218, 255);
  final ink = img.ColorRgba8(198, 94, 42, 235);

  final leftPage = [
    img.Point(174, 334),
    img.Point(500, 394),
    img.Point(500, 704),
    img.Point(174, 644),
  ];
  final rightPage = [
    img.Point(524, 394),
    img.Point(850, 334),
    img.Point(850, 644),
    img.Point(524, 704),
  ];
  img.fillPolygon(image, vertices: leftPage, color: cream);
  img.fillPolygon(image, vertices: rightPage, color: creamShade);

  // Book spine.
  // 书脊。
  img.drawLine(
    image,
    x1: 512,
    y1: 392,
    x2: 512,
    y2: 706,
    color: img.ColorRgba8(226, 140, 74, 255),
    thickness: 12,
    antialias: true,
  );

  // Rounded text lines keep their shape clean at launcher sizes.
  // 圆角文字线条在启动器小尺寸下也能保持清晰。
  for (var i = 0; i < 2; i++) {
    final y = 486 + i * 78;
    img.fillRect(
      image,
      x1: 236,
      y1: y,
      x2: 446,
      y2: y + 17,
      radius: 8,
      color: ink,
    );
    img.fillRect(
      image,
      x1: 578,
      y1: y,
      x2: 788,
      y2: y + 17,
      radius: 8,
      color: ink,
    );
  }

  // Page bottom shading.
  // 页面底部阴影。
  img.drawLine(
    image,
    x1: 178,
    y1: 646,
    x2: 498,
    y2: 706,
    color: img.ColorRgba8(196, 124, 72, 70),
    thickness: 5,
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 850,
    y1: 646,
    x2: 526,
    y2: 706,
    color: img.ColorRgba8(196, 124, 72, 70),
    thickness: 5,
    antialias: true,
  );

  // A small bookmark ribbon on the right page.
  // 右页上的小书签丝带。
  final ribbon = [
    img.Point(700, 300),
    img.Point(772, 288),
    img.Point(772, 456),
    img.Point(736, 420),
    img.Point(700, 462),
  ];
  img.fillPolygon(
    image,
    vertices: ribbon,
    color: img.ColorRgba8(196, 63, 48, 255),
  );

  return image;
}

int _lerp(int a, int b, double t) => (a + (b - a) * t).round();

int _cornerInset(double y) {
  const r = _radius;
  if (y < r) {
    final dy = r - y;
    return (r - math.sqrt(math.max(0, r * r - dy * dy))).round();
  }
  final height = _size.toDouble();
  if (y > height - r) {
    final dy = y - (height - r);
    return (r - math.sqrt(math.max(0, r * r - dy * dy))).round();
  }
  return 0;
}

img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.cubic,
);
