import 'dart:typed_data';

/// Intrinsic pixel dimensions of a comic page image.
/// 漫画页面图片的原始像素尺寸。
typedef ImageDimensions = ({int width, int height});

const _jpegStartOfFrame = {
  0xC0,
  0xC1,
  0xC2,
  0xC3,
  0xC5,
  0xC6,
  0xC7,
  0xC9,
  0xCA,
  0xCB,
  0xCD,
  0xCE,
  0xCF,
};

/// Reads image dimensions from the header without decoding the whole image.
/// 仅从图片头读取尺寸，不解码整张图片。
ImageDimensions? readImageDimensions(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final dimensions =
      _readPng(bytes) ??
      _readJpeg(bytes) ??
      _readGif(bytes) ??
      _readWebp(bytes) ??
      _readBmp(bytes);
  if (dimensions == null) return null;
  if (dimensions.width <= 0 ||
      dimensions.height <= 0 ||
      dimensions.width > 100000 ||
      dimensions.height > 100000) {
    return null;
  }
  return dimensions;
}

ImageDimensions? _readPng(Uint8List bytes) {
  if (bytes.length < 24 ||
      bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47 ||
      bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return null;
  }
  return (width: _uint32be(bytes, 16), height: _uint32be(bytes, 20));
}

ImageDimensions? _readJpeg(Uint8List bytes) => readJpegDimensions(bytes);

/// Reads JPEG dimensions from SOF markers while accounting for APP1 EXIF
/// orientation (values 5–8 swap width and height).
/// 从 JPEG SOF 标记读取尺寸，并结合 APP1 EXIF 方向（5–8 会交换宽高）。
ImageDimensions? readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  var swapAxes = false;
  while (offset + 1 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    while (offset < bytes.length && bytes[offset] == 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) break;
    final marker = bytes[offset++];
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (offset + 2 > bytes.length) break;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2) break;
    if (marker == 0xE1 && offset + length <= bytes.length) {
      final orientation = _readExifOrientation(
        bytes,
        offset + 2,
        offset + length,
      );
      if (orientation != null) {
        swapAxes = orientation >= 5 && orientation <= 8;
      }
    } else if (_jpegStartOfFrame.contains(marker)) {
      if (offset + 7 > bytes.length) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) return null;
      return swapAxes
          ? (width: height, height: width)
          : (width: width, height: height);
    }
    offset += length;
  }
  return null;
}

int? _readExifOrientation(Uint8List bytes, int start, int end) {
  if (end - start < 14) return null;
  if (bytes[start] != 0x45 ||
      bytes[start + 1] != 0x78 ||
      bytes[start + 2] != 0x69 ||
      bytes[start + 3] != 0x66 ||
      bytes[start + 4] != 0x00 ||
      bytes[start + 5] != 0x00) {
    return null;
  }
  final tiff = start + 6;
  final littleEndian =
      bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
  final bigEndian = bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D;
  if (!littleEndian && !bigEndian) return null;

  int u16(int pos) => littleEndian
      ? (bytes[pos] | (bytes[pos + 1] << 8))
      : ((bytes[pos] << 8) | bytes[pos + 1]);
  int u32(int pos) => littleEndian
      ? (bytes[pos] |
            (bytes[pos + 1] << 8) |
            (bytes[pos + 2] << 16) |
            (bytes[pos + 3] << 24))
      : ((bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3]);

  if (u16(tiff + 2) != 42) return null;
  final ifdOffset = u32(tiff + 4);
  final ifd = tiff + ifdOffset;
  if (ifd < tiff || ifd + 2 > end) return null;
  final count = u16(ifd);
  var cursor = ifd + 2;
  for (var i = 0; i < count && cursor + 12 <= end; i++) {
    final tag = u16(cursor);
    if (tag == 0x0112) {
      final type = u16(cursor + 2);
      final valueCount = u32(cursor + 4);
      if (type == 3 && valueCount >= 1) {
        return u16(cursor + 8);
      }
      return null;
    }
    cursor += 12;
  }
  return null;
}

ImageDimensions? _readGif(Uint8List bytes) {
  if (bytes.length < 10 ||
      bytes[0] != 0x47 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46) {
    return null;
  }
  return (width: _uint16le(bytes, 6), height: _uint16le(bytes, 8));
}

ImageDimensions? _readWebp(Uint8List bytes) {
  if (bytes.length < 16 ||
      bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46 ||
      bytes[8] != 0x57 ||
      bytes[9] != 0x45 ||
      bytes[10] != 0x42 ||
      bytes[11] != 0x50) {
    return null;
  }
  final chunk = String.fromCharCodes(bytes, 12, 16);
  if (chunk == 'VP8X') {
    if (bytes.length < 30) return null;
    final width = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16);
    final height = bytes[27] | (bytes[28] << 8) | (bytes[29] << 16);
    return (width: width + 1, height: height + 1);
  }
  if (chunk == 'VP8L') {
    if (bytes.length < 25 || bytes[20] != 0x2F) return null;
    final b0 = bytes[21];
    final b1 = bytes[22];
    final b2 = bytes[23];
    final b3 = bytes[24];
    final width = 1 + (((b1 & 0x3F) << 8) | b0);
    final height = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
    return (width: width, height: height);
  }
  if (chunk == 'VP8 ') {
    if (bytes.length < 30 ||
        bytes[23] != 0x9D ||
        bytes[24] != 0x01 ||
        bytes[25] != 0x2A) {
      return null;
    }
    return (
      width: _uint16le(bytes, 26) & 0x3FFF,
      height: _uint16le(bytes, 28) & 0x3FFF,
    );
  }
  return null;
}

ImageDimensions? _readBmp(Uint8List bytes) {
  if (bytes.length < 26 || bytes[0] != 0x42 || bytes[1] != 0x4D) {
    return null;
  }
  final dibSize = _uint32le(bytes, 14);
  if (dibSize == 12) {
    return (width: _uint16le(bytes, 18), height: _uint16le(bytes, 20));
  }
  final width = _int32le(bytes, 18).abs();
  final height = _int32le(bytes, 22).abs();
  return (width: width, height: height);
}

int _uint16le(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32le(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _uint32be(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _int32le(Uint8List bytes, int offset) {
  final value =
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
  return (value & 0x80000000) == 0 ? value : value - 0x100000000;
}
