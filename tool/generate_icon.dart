import 'dart:io';

import 'package:image/image.dart' as img;

const _sourcePath = 'assets/app_icon.png';
const _size = 1024;

void main() {
  final master = img.decodePng(File(_sourcePath).readAsBytesSync());
  if (master == null || master.width != _size || master.height != _size) {
    throw FormatException('Expected a $_size x $_size PNG', _sourcePath);
  }

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
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(_resize(master, entry.value)));
  }

  final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (iosDir.existsSync()) {
    // iOS applies the corner mask, so extend the paper background to the edges.
    // iOS 会给图标加圆角遮罩，因此将纸白背景铺到四角。
    final square = img.Image(width: _size, height: _size, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(0xFF, 0xFA, 0xEF));
    img.compositeImage(square, master);

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
      final image = entry.value == _size
          ? square
          : _resize(square, entry.value);
      File('${iosDir.path}/${entry.key}')
          .writeAsBytesSync(img.encodePng(image));
    }
  }

  const icoSizes = [16, 24, 32, 48, 64, 128, 256];
  final icoImages = [for (final size in icoSizes) _resize(master, size)];
  final icoBytes = img.IcoEncoder().encodeImages(icoImages);
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoBytes);

  stdout.writeln('Generated app icons (${icoSizes.join(', ')} px ICO).');
}

img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);
