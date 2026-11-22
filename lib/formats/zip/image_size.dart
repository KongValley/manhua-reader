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

ImageDimensions? _readJpeg(Uint8List bytes) {
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 3 < bytes.length) {
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
    if (offset + 1 >= bytes.length) break;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2) break;
    if (_jpegStartOfFrame.contains(marker)) {
      if (offset + 6 >= bytes.length) return null;
      return (
        width: (bytes[offset + 5] << 8) | bytes[offset + 6],
        height: (bytes[offset + 3] << 8) | bytes[offset + 4],
      );
    }
    offset += length;
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
    final bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16);
    return (width: (bits & 0x3FFF) + 1, height: ((bits >> 14) & 0x3FFF) + 1);
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
  final width = _int32le(bytes, 18).abs();
  final height = _int32le(bytes, 22).abs();
  return (width: width, height: height);
}

int _uint16le(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

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
